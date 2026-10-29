import {test,expect} from 'bun:test';
import {mkdtemp,mkdir,rm,readFile,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {ChatSessions} from './chat-sessions';
import {chatRoutes} from './chat-api';

test('client-created identity survives duplicate concurrent creation, edits and restart',async()=>{
 const root=await mkdtemp(join(tmpdir(),'chat-offline-create-'));
 const events:any[]=[];let calls=0;
 let store=new ChatSessions(root,{run:async()=>{calls++;return 'OK';}},{emit:(...args)=>events.push(args)});
 const id='chat-11111111-1111-4111-8111-111111111111';
 try{
  const input={id,name:'Offline Scout',instructions:'Be concise',memory:'Pip'};
  const records=await Promise.all([store.create(input),store.create(input)]);
  expect(records.map(x=>x.id)).toEqual([id,id]);expect(await store.list()).toHaveLength(1);expect(events).toHaveLength(1);
  await store.update(id,{revision:1,memory:'Updated after sync'});
  expect((await store.create(input)).memory).toBe('Updated after sync');
  await store.send(id,{requestID:'queued-message',text:'Hello'});await store.settled(id);await store.close();
  store=new ChatSessions(root,{run:async()=>{calls++;return 'Wrong duplicate';}});
  expect((await store.create(input)).id).toBe(id);
  expect((await store.send(id,{requestID:'queued-message',text:'Hello'})).duplicate).toBe(true);
  expect(calls).toBe(1);
  expect((await store.detail(id)).messages.map(m=>m.text)).toEqual(['Hello','OK']);
 }finally{await store.close();await rm(root,{recursive:true,force:true});}
});
test('creation capability and invalid client ids are explicit and preserve legacy creation',async()=>{
 const root=await mkdtemp(join(tmpdir(),'chat-offline-api-'));
 const store=new ChatSessions(root,{run:async()=>''}),route=chatRoutes(store);
 try{
  const caps=await route(new Request('http://test/api/sessions/chats/capabilities'));
  expect(caps?.status).toBe(200);expect(await caps?.json()).toEqual({clientChatIDs:true});
  const post=(body:any)=>route(new Request('http://test/api/sessions/chats',{method:'POST',body:JSON.stringify(body)}));
  expect((await post({id:'../../escape',name:'Bad'}))?.status).toBe(400);
  expect((await post({id:42,name:'Bad'}))?.status).toBe(400);
  expect((await store.list()).length).toBe(0);
  expect((await post({name:'Legacy'}))?.status).toBe(201);
 }finally{await store.close();await rm(root,{recursive:true,force:true});}
});

test('restart skips only an uncommitted empty creation and retries the same identity',async()=>{
 const root=await mkdtemp(join(tmpdir(),'chat-offline-partial-'));
 let store=new ChatSessions(root,{run:async()=> 'OK'});
 const id='chat-22222222-2222-4222-8222-222222222222';
 try{
  const existing=await store.create({name:'Existing'});await store.close();
  await mkdir(join(root,id,'turns'),{recursive:true});
  const tmp=join(root,id,'session.json.33333333-3333-4333-8333-333333333333.tmp');
  await writeFile(tmp,'uncommitted metadata');
  store=new ChatSessions(root,{run:async()=> 'OK'});await store.ready;
  expect((await store.list()).map(x=>x.id)).toEqual([existing.id]);
  expect((await store.create({id,name:'Recovered draft'})).id).toBe(id);
  expect((await store.detail(existing.id)).session.name).toBe('Existing');
  // Recovery preserves crash artifacts instead of deleting unexamined files.
  expect(await readFile(tmp,'utf8')).toBe('uncommitted metadata');
 }finally{await store.close();await rm(root,{recursive:true,force:true});}
});

test('a missing-metadata chat with saved data is never recreated or erased',async()=>{
 const root=await mkdtemp(join(tmpdir(),'chat-offline-orphan-data-'));
 let store=new ChatSessions(root,{run:async()=> 'OK'});
 const id='chat-44444444-4444-4444-8444-444444444444';
 try{
  await store.ready;await mkdir(join(root,id,'turns'),{recursive:true});
  const path=join(root,id,'turns','a'.repeat(64)+'.json');
  const saved='{"privateHistory":"must be preserved"}';await writeFile(path,saved);
  await expect(store.create({id,name:'Do not overwrite'})).rejects.toThrow('saved data without metadata');
  expect(await readFile(path,'utf8')).toBe(saved);
  await expect(readFile(join(root,id,'session.json'),'utf8')).rejects.toThrow();
  await store.close();
  store=new ChatSessions(root,{run:async()=> 'OK'});
  await expect(store.ready).rejects.toThrow('Chat not found');
  expect(await readFile(path,'utf8')).toBe(saved);
 }finally{await store.close();await rm(root,{recursive:true,force:true});}
});

test('shutdown drains an accepted creation before releasing store ownership',async()=>{
 const root=await mkdtemp(join(tmpdir(),'chat-offline-shutdown-'));
 const store=new ChatSessions(root,{run:async()=> 'OK'});
 let release!:()=>void,entered!:()=>void;
 const gate=new Promise<void>(r=>release=r),started=new Promise<void>(r=>entered=r);
 const original=(store as any).save.bind(store);
 (store as any).save=async(s:unknown)=>{entered();await gate;return original(s);};
 let contender:ChatSessions|undefined,replacement:ChatSessions|undefined;
 try{
  await store.ready;
  const creating=store.create({id:'chat-55555555-5555-4555-8555-555555555555',name:'Racing'});
  await started;let finished=false;
  const closing=store.close();expect(store.close()).toBe(closing);
  void closing.then(()=>{finished=true;});await Bun.sleep(20);
  expect(finished).toBe(false);
  contender=new ChatSessions(root,{run:async()=> 'OK'});
  await expect(contender.ready).rejects.toThrow('already open');await contender.close();
  release();const created=await creating;await closing;
  await expect(store.create({name:'Too late'})).rejects.toThrow('stopping');
  replacement=new ChatSessions(root,{run:async()=> 'OK'});await replacement.ready;
  expect((await replacement.detail(created.id)).session.name).toBe('Racing');
 }finally{release();await contender?.close();await store.close();await replacement?.close();await rm(root,{recursive:true,force:true});}
});
