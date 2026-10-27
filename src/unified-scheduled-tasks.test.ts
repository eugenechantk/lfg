import {test,expect} from 'bun:test';
import {mkdtemp,readFile,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {TaskStore} from './scheduled-tasks';
import {taskRuntime,scheduledTaskRoutes,type TaskApiCall} from './scheduled-task-api';
import {ChatSessions} from './chat-sessions';
import {ChatJobs} from './chat-jobs';
import {chatJobRoutes} from './chat-job-api';
import {taskOriginsBySession} from './task-origin';

async function setup(hold=false){
 const root=await mkdtemp(join(tmpdir(),'lfg-unified-'));let now=Date.now();const launches:any[]=[],pushes:any[]=[],calls:any[]=[];let release!:()=>void;const gate=new Promise<void>(r=>release=r);
 const chats=new ChatSessions(join(root,'chats'),{nativeConversations:true,run:async i=>{calls.push(i);await i.native!.onReady();if(hold)await gate;const p=JSON.parse(i.prompt);return `Current memory: ${p.privateMemory}\n<lfg_job_result>${JSON.stringify({run_id:p.scheduledJob.runID,notify:true,message:'Matched',stop:true})}</lfg_job_result>`;}});
 const chat=await chats.create({name:'Shared chat',memory:'Miso'}),store=new TaskStore(join(root,'scheduled-tasks.json'));
 const call:TaskApiCall=async(path:string,body?:any):Promise<any>=>{if(path==='/api/sessions/new'){launches.push(body);return {sessionId:'terminal-run'};}if(path==='/api/sessions')return {sessions:[{sessionId:'terminal-run',busy:true}]};throw Error(path);};
 const scheduler=taskRuntime(store,call,()=>now);
 const jobs=new ChatJobs(store,chats,{scheduler,now:()=>now,push:{devices:async()=>[{token:'fake',env:'sandbox'}],hostId:()=> 'fixture',send:async(_d,p)=>{pushes.push(p);return {ok:true,status:200};}}});
 await jobs.ready;
 const route=scheduledTaskRoutes(store,scheduler,call,{root,port:18989,defaultCwd:root}),compat=chatJobRoutes(jobs,route);
 const request=(path:string,body?:any)=>new Request('http://fixture'+path,body?{method:'POST',body:JSON.stringify(body)}:{});
 const schedule=()=>({kind:'once' as const,timezone:'UTC',at:new Date(now+1000).toISOString()});
 return {root,chats,chat,store,scheduler,jobs,route,compat,request,schedule,launches,calls,pushes,release,advance:()=>now+=1000,close:async()=>{release();await jobs.close();await chats.close();await rm(root,{recursive:true,force:true});}};
}

test('one canonical store and scheduler execute session, chat and reminder actions',async()=>{
 const f=await setup();try{
  const terminal=await f.store.save({name:'Coding',prompt:'Do work',cwd:f.root,agent:'claude',schedule:f.schedule()});
  const reminder=await f.jobs.create({chatId:f.chat.id,name:'Reminder',instructions:'Drink water',action:'notify',schedule:f.schedule(),requestID:'reminder'});
  const response=await f.route(f.request('/api/scheduled-tasks',{action:'chat',chatId:f.chat.id,name:'Check',prompt:'Check memory and notify',schedule:f.schedule(),requestID:'check'}));
  expect(response!.status).toBe(201);const check=(await response!.json() as any).task;
  expect((await f.store.read()).tasks.map(t=>t.id).sort()).toEqual([terminal.id,reminder.id,check.id].sort());
  expect((await f.jobs.list(f.chat.id)).map(j=>j.id).sort()).toEqual([reminder.id,check.id].sort());
  f.advance();for(let i=0;i<4;i++){await f.scheduler.tick();await f.chats.settled(f.chat.id);}
  const state=await f.store.read();expect(f.launches).toHaveLength(1);expect(f.calls).toHaveLength(1);expect(f.pushes).toHaveLength(2);
  expect(state.runs.filter(r=>r.status==='succeeded')).toHaveLength(2);expect(state.runs.find(r=>r.taskId===terminal.id)!.sessionId).toBe('terminal-run');
  expect(JSON.parse(f.calls[0].prompt).privateMemory).toBe('Miso');
  expect(taskOriginsBySession(state.runs).has(f.chat.id)).toBe(false);
  expect(taskOriginsBySession(state.runs).has('terminal-run')).toBe(true);
  const filtered=await f.route(f.request('/api/scheduled-tasks?chatId='+f.chat.id));expect((await filtered!.json() as any).tasks).toHaveLength(2);
  const canonical=await f.route(f.request('/api/scheduled-tasks/'+reminder.id,{revision:reminder.revision,name:'Updated reminder'}));expect(canonical!.status).toBe(200);
  expect((await f.jobs.detail(reminder.id)).job.name).toBe('Updated reminder');
  await f.compat(f.request('/api/chat-jobs/'+check.id+'/cancel',{}));expect((await f.store.read()).tasks.find(t=>t.id===check.id)!.cancelledAt).toBeDefined();
 }finally{await f.close();}
});

test('canonical scoped tools use the Tasks API and cannot inspect or mutate another chat',async()=>{
 const f=await setup();try{
  const other=await f.chats.create({name:'Other'}),foreign=await f.jobs.create({chatId:other.id,name:'Private',instructions:'Keep private',action:'notify',schedule:f.schedule(),requestID:'foreign'});
  const rpc=async(name:string,args:any={})=>{const response=await f.compat(f.request('/api/scheduled-tasks/mcp/'+f.chat.id,{jsonrpc:'2.0',id:1,method:'tools/call',params:{name,arguments:args}}));return await response!.json() as any;};
  const created=await rpc('create_scheduled_task',{action:'notify',name:'Shared task',prompt:'Remember',schedule:f.schedule(),requestID:'canonical'});
  const task=JSON.parse(created.result.content[0].text).task;expect(task.chatId).toBe(f.chat.id);expect(task.action).toBe('notify');
  const listed=await rpc('list_scheduled_tasks');expect(JSON.parse(listed.result.content[0].text).tasks.map((t:any)=>t.id)).toEqual([task.id]);
  expect((await rpc('cancel_scheduled_task',{task_id:foreign.id})).result.isError).toBe(true);
  expect((await rpc('scheduled_task_runs',{task_id:foreign.id})).result.isError).toBe(true);
  expect((await f.store.read()).tasks.find(t=>t.id===foreign.id)!.enabled).toBe(true);
 }finally{await f.close();}
});

test('migration collisions and malformed source data leave the destination unchanged',async()=>{
 const f=await setup();try{
  const original=await f.jobs.create({chatId:f.chat.id,name:'Existing',instructions:'Keep',action:'notify',schedule:f.schedule(),requestID:'existing'});
  const legacy=join(f.root,'old-chat-jobs.json'),before=await readFile(f.store.path,'utf8');
  await writeFile(legacy,JSON.stringify({version:1,jobs:[original],runs:[],notifications:[]}));
  await expect(f.store.importChatJobs(legacy)).rejects.toThrow('collision');expect(await readFile(f.store.path,'utf8')).toBe(before);
  await writeFile(legacy,JSON.stringify({version:1,jobs:[original,original],runs:[],notifications:[]}));
  await expect(f.store.importChatJobs(legacy)).rejects.toThrow('Duplicate');expect(await readFile(f.store.path,'utf8')).toBe(before);
 }finally{await f.close();}
});

test('a migrated running receipt completes and delivers without accepting the provider work again',async()=>{
 const f=await setup(true);let migrated:ChatJobs|undefined;try{
  const input={chatId:f.chat.id,name:'Migrating',instructions:'Check',action:'run',schedule:f.schedule(),requestID:'migrating'};
  const job=await f.jobs.create(input);f.advance();await f.scheduler.tick();f.release();await f.chats.settled(f.chat.id);
  const detail=await f.jobs.detail(job.id);
  expect(detail.runs[0]!.state).toBe('running');expect(f.calls).toHaveLength(1);
  const path=join(f.root,'old-jobs.json');await writeFile(path,JSON.stringify({version:1,jobs:[detail.job],runs:detail.runs,notifications:[]}));
  const target=new TaskStore(join(f.root,'new-tasks.json'));
  migrated=new ChatJobs(target,f.chats,{migrateFrom:path,push:{devices:async()=>[{token:'migrated',env:'sandbox'}],hostId:()=> 'new',send:async(_d,p)=>{f.pushes.push(p);return {ok:true,status:200};}}});
  await migrated.ready;await migrated.tick();await migrated.tick();expect(f.calls).toHaveLength(1);expect(f.pushes).toHaveLength(1);
  expect((await target.read()).runs[0]!.status).toBe('succeeded');expect((await target.read()).notifications[0]!.state).toBe('accepted');
  expect((await migrated.create(input)).id).toBe(job.id);
 }finally{await migrated?.close();await f.close();}
});

test('version-one tasks and old chat jobs import once without changing identities or replaying completed runs',async()=>{
 const root=await mkdtemp(join(tmpdir(),'lfg-unified-import-'));const now=Date.now(),chatId='chat-'+crypto.randomUUID(),id=crypto.randomUUID(),runId=crypto.randomUUID();
 const task={id:crypto.randomUUID(),name:'Existing',prompt:'Keep',cwd:root,agent:'claude',schedule:{kind:'interval',timezone:'UTC',everyMinutes:60},enabled:true,createdAt:now,updatedAt:now,nextRunAt:now+3600000};
 const job={id,chatId,name:'Old reminder',instructions:'Saved text',action:'notify',schedule:{kind:'once',timezone:'UTC',at:new Date(now-1000).toISOString()},notification:'always',stopOnNotify:false,enabled:false,nextRunAt:null,createdAt:now-2000,updatedAt:now,revision:3,scheduledRunCount:1,requestID:'old',requestFingerprint:'old-fingerprint'};
 const notification={id:runId,runId,jobId:id,chatId,title:job.name,body:job.instructions,createdAt:now,state:'accepted',devices:{phone:{state:'accepted',attempts:1,nextAttemptAt:now}}};
 const legacy=join(root,'chat-jobs.json'),path=join(root,'scheduled-tasks.json');
 try{
  const legacyText=JSON.stringify({version:1,jobs:[job],runs:[{id:runId,jobId:id,chatId,scheduledFor:now-1000,state:'completed',snapshot:job,createdAt:now-1000,finishedAt:now,summary:'Saved text'}],notifications:[notification]});
  await writeFile(path,JSON.stringify({version:1,tasks:[task],runs:[]}));await writeFile(legacy,legacyText);
  const store=new TaskStore(path);await store.importChatJobs(legacy);await store.importChatJobs(legacy);
  const state=await new TaskStore(path).read();expect(state.version).toBe(2);expect(state.tasks).toHaveLength(2);expect(state.tasks.find(t=>t.id===id)!.revision).toBe(3);
  expect(state.runs[0]!.id).toBe(runId);expect(state.runs[0]!.status).toBe('succeeded');expect(state.notifications[0]!.id).toBe(runId);expect(state.notifications[0]!.state).toBe('accepted');
  expect(await readFile(legacy,'utf8')).toBe(legacyText);expect(state.tasks.find(t=>t.id===task.id)!.prompt).toBe('Keep');
 }finally{await rm(root,{recursive:true,force:true});}
});
