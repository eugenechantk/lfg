import {test,expect} from 'bun:test';
import {mkdtemp,rm,readFile,writeFile,mkdir,access} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {ChatSessions} from './chat-sessions';
import {chatRoutes} from './chat-api';
import {TaskStore} from './scheduled-tasks';
import {purgeChatProviderHistory} from './chat-native';

test('deletion removes saved content, cancels only owned jobs, and cannot be resurrected by an old create',async()=>{
 const root=await mkdtemp(join(tmpdir(),'lfg-delete-'));const store=new TaskStore(join(root,'tasks.json'));
 let chats=new ChatSessions(join(root,'chats'),{run:async()=> 'Saved answer'},{beforeDelete:id=>store.cancelForChat(id)});
 try{
  const chat=await chats.create({name:'Remove me',instructions:'Private instruction',memory:'Private memory'});
  const other=await chats.create({name:'Keep me'});
  await chats.send(chat.id,{requestID:'one',text:'Private question'});await chats.settled(chat.id);
  const input={name:'Reminder',prompt:'Remember this',action:'notify' as const,requestID:'reminder-request',schedule:{kind:'once' as const,timezone:'UTC',at:new Date(Date.now()+60000).toISOString()}};
  const owned=await store.save({...input,chatId:chat.id}),unrelated=await store.save({...input,chatId:other.id});
  const run=await store.claim(owned.id,Date.now(),true);
  await store.transaction(s=>{s.notifications.push({id:'owned-alert',runId:run!.id,taskId:owned.id,chatId:chat.id,title:'Reminder',body:'Private reminder',createdAt:Date.now(),state:'pending',devices:{}});});
  await writeFile(join(root,'external-report.md'),'Keep this report');
  const revision=(await chats.detail(chat.id)).session.revision;
  expect(await chats.remove(chat.id,revision)).toEqual({ok:true,deletedID:chat.id});
  expect(await chats.list()).toHaveLength(1);
  expect((await chats.list())[0]!.id).toBe(other.id);
  await expect(chats.detail(chat.id)).rejects.toMatchObject({status:410});
  await expect(chats.create({id:chat.id,name:'Stale client'})).rejects.toMatchObject({status:410});
  await expect(access(join(root,'chats',chat.id))).rejects.toThrow();
  expect(await readFile(join(root,'external-report.md'),'utf8')).toBe('Keep this report');
  const tasks=await store.read();
  expect(tasks.tasks.find(t=>t.id===owned.id)!.cancelledAt).toBeNumber();
  expect(tasks.tasks.find(t=>t.id===unrelated.id)!.cancelledAt).toBeUndefined();
  expect(tasks.runs.find(r=>r.id===run!.id)!.status).toBe('cancelled');
  expect(tasks.notifications[0]!.state).toBe('cancelled');
  await expect(new TaskStore(store.path).save({...input,chatId:chat.id,requestID:'late-creation'})).rejects.toMatchObject({status:410});
  await store.transaction(s=>{const t=s.tasks.find(t=>t.id===owned.id)!;delete t.cancelledAt;t.enabled=true;});
  expect(await new TaskStore(store.path).claim(owned.id,Date.now(),true)).toBeNull();
  await store.record(run!.id,{status:'succeeded',finishedAt:Date.now(),summary:'Late callback'});
  expect((await store.read()).runs.find(r=>r.id===run!.id)!.status).toBe('cancelled');
  await chats.close();chats=new ChatSessions(join(root,'chats'),{run:async()=>''},{beforeDelete:id=>store.cancelForChat(id)});
  await chats.ready;
  expect(await chats.deletedIDs()).toEqual([chat.id]);
  expect(await chats.remove(chat.id,revision)).toEqual({ok:true,deletedID:chat.id});
 }finally{await chats.close();await rm(root,{recursive:true,force:true});}
});

test('stale revisions and active replies cannot delete a chat',async()=>{
 const root=await mkdtemp(join(tmpdir(),'lfg-delete-active-'));
 const chats=new ChatSessions(root,{run:async input=>new Promise<string>((resolve)=>input.signal.addEventListener('abort',()=>resolve('Stopped'),{once:true}))});
 try{
  const chat=await chats.create({name:'Busy'});
  await expect(chats.remove(chat.id,chat.revision+1)).rejects.toMatchObject({status:409});
  await chats.send(chat.id,{requestID:'active',text:'Work'});
  await expect(chats.remove(chat.id,chat.revision)).rejects.toMatchObject({status:409});
  expect(await chats.deletedIDs()).toEqual([]);
  await chats.interrupt(chat.id);await chats.settled(chat.id);
  expect((await chats.list())[0]!.id).toBe(chat.id);
 }finally{await chats.close();await rm(root,{recursive:true,force:true});}
});

test('delete waits outside the chat lock for worker callbacks and blocks concurrent sends',async()=>{
 const root=await mkdtemp(join(tmpdir(),'lfg-delete-worker-'));
 let enter!:()=>void,release!:()=>void;const entered=new Promise<void>(r=>enter=r),wait=new Promise<void>(r=>release=r);
 const chats=new ChatSessions(root,{run:async()=>'',interrupt:async()=>{enter();await wait;}});
 try{
  const chat=await chats.create({name:'Warm worker'});
  const deletion=chats.remove(chat.id,chat.revision);await entered;
  await expect(chats.send(chat.id,{requestID:'late',text:'Do not run'})).rejects.toMatchObject({status:409});
  release();await deletion;
  await expect(chats.send(chat.id,{requestID:'later',text:'Still do not run'})).rejects.toMatchObject({status:410});
 }finally{release?.();await chats.close();await rm(root,{recursive:true,force:true});}
});

test('failed physical cleanup is retried after restart without exposing or recreating the chat',async()=>{
 const root=await mkdtemp(join(tmpdir(),'lfg-delete-recovery-'));
 let chats=new ChatSessions(root,{run:async()=>'',purge:async()=>{throw Error('Temporarily unavailable');}});
 try{
  const chat=await chats.create({name:'Pending cleanup'});
  await expect(chats.remove(chat.id,chat.revision)).rejects.toThrow('Temporarily');
  expect(await chats.list()).toEqual([]);
  await chats.close();chats=new ChatSessions(root,{run:async()=>''});await chats.ready;
  await expect(access(join(root,chat.id))).rejects.toThrow();
  await expect(chats.create({id:chat.id,name:'Old cached chat'})).rejects.toMatchObject({status:410});
 }finally{await chats.close();await rm(root,{recursive:true,force:true});}
});

test('HTTP delete is explicit, owner-local, origin checked and advertises a tombstone',async()=>{
 const root=await mkdtemp(join(tmpdir(),'lfg-delete-api-'));const chats=new ChatSessions(root,{run:async()=>''});
 try{
  const chat=await chats.create({name:'HTTP'}),route=chatRoutes(chats);
  const request=(body:unknown,origin?:string)=>new Request(`http://owner/api/sessions/${chat.id}/delete`,{method:'POST',headers:{'Content-Type':'application/json',...(origin?{origin}:{})},body:JSON.stringify(body)});
  expect((await route(request({revision:chat.revision},'http://other')))!.status).toBe(403);
  expect((await route(request({revision:99})))!.status).toBe(409);
  expect((await route(request({revision:chat.revision})))!.status).toBe(200);
  const list=await (await route(new Request('http://owner/api/sessions/chats')))!.json() as any;
  expect(list.sessions).toEqual([]);expect(list.deletedIDs).toEqual([chat.id]);
 }finally{await chats.close();await rm(root,{recursive:true,force:true});}
});

test('native cleanup removes only the owned provider transcript and child sidecars',async()=>{
 const root=await mkdtemp(join(tmpdir(),'lfg-provider-purge-')),directory='/tmp/chat.provider';
 const id='12345678-1234-4123-8123-123456789abc';
 try{
  for(const encoded of new Set([directory.replace(/\//g,'-'),directory.replace(/[/.]/g,'-')])){
   const p=join(root,encoded);await mkdir(join(p,id,'subagents'),{recursive:true});
   await writeFile(join(p,id+'.jsonl'),'private history');await writeFile(join(p,id,'subagents','child.jsonl'),'private child');
   await writeFile(join(p,'unrelated.jsonl'),'keep');
  }
  await purgeChatProviderHistory(directory,id,root);
  for(const encoded of new Set([directory.replace(/\//g,'-'),directory.replace(/[/.]/g,'-')])){
   await expect(access(join(root,encoded,id+'.jsonl'))).rejects.toThrow();
   expect(await readFile(join(root,encoded,'unrelated.jsonl'),'utf8')).toBe('keep');
  }
  await expect(purgeChatProviderHistory(directory,'../unsafe',root)).rejects.toThrow('Invalid provider');
 }finally{await rm(root,{recursive:true,force:true});}
});

test('service shutdown drains deletion before releasing storage ownership',async()=>{
 const root=await mkdtemp(join(tmpdir(),'lfg-delete-shutdown-'));
 let release!:()=>void,entered!:()=>void;
 const gate=new Promise<void>(r=>release=r),ready=new Promise<void>(r=>entered=r);
 const chats=new ChatSessions(root,{run:async()=>'',interrupt:async()=>{entered();await gate;}});
 try{
  const chat=await chats.create({name:'Delete before shutdown'});
  const deletion=chats.remove(chat.id,chat.revision);await ready;
  let closed=false;const closing=chats.close().then(()=>{closed=true;});
  await Bun.sleep(20);const premature=closed;
  release();await deletion;await closing;
  expect(premature).toBe(false);
  const reopened=new ChatSessions(root,{run:async()=>''});
  try{await reopened.ready;await expect(reopened.detail(chat.id)).rejects.toMatchObject({status:410});}
  finally{await reopened.close();}
 }finally{release?.();await chats.close();await rm(root,{recursive:true,force:true});}
});
