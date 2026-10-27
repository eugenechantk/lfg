import {test,expect} from 'bun:test';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {ChatSessions,type ChatRunInput} from './chat-sessions';
import {ChatJobs} from './chat-jobs';
import {parseJobResult} from './chat-job-result';
const answer=(run:string,notify=false,stop=false)=>`Checked the saved condition.\n<lfg_job_result>${JSON.stringify({run_id:run,notify,message:notify?'Your submission was approved.':'',stop})}</lfg_job_result>`;
async function fixture(){
 const root=await mkdtemp(join(tmpdir(),'lfg-jobs-'));let time=Date.parse('2026-10-26T01:00:00Z');let notify=false,stop=false;
 const calls:ChatRunInput[]=[],sent:any[]=[];let failPush=false;
 const chats=new ChatSessions(join(root,'chats'),{nativeConversations:true,run:async i=>{calls.push(i);await i.native!.onReady();const p=JSON.parse(i.prompt);return p.scheduledJob?answer(p.scheduledJob.runID,notify,stop):'Normal reply';}});
 const push={devices:async()=>[{token:'phone',env:'sandbox' as const,owner:null}],send:async(_d:any,p:any)=>{sent.push(p);return failPush?{ok:false,status:503}:{ok:true,status:200};},hostId:()=> 'test-host'};
 let jobs=new ChatJobs(join(root,'jobs.json'),chats,{now:()=>time,push});
 const chat=await chats.create({name:'Scout',instructions:'Be precise',memory:'My dog is Pip'});
 const input=(action='notify')=>({chatId:chat.id,name:'Review reminder',instructions:'Check this submission and notify only when approved.',action,schedule:{kind:'once',timezone:'Asia/Hong_Kong',at:new Date(time+1000).toISOString()},requestID:crypto.randomUUID()});
 return {root,chats,chat,get jobs(){return jobs},calls,sent,input,setTime:(n:number)=>time+=n,setDecision:(n:boolean,s=false)=>{notify=n;stop=s},setPushFailure:(v:boolean)=>failPush=v,reload:()=>jobs=new ChatJobs(join(root,'jobs.json'),chats,{now:()=>time,push}),close:async()=>{await jobs.close();await chats.close();await rm(root,{recursive:true,force:true});}};
}
async function finish(f:Awaited<ReturnType<typeof fixture>>){await f.jobs.tick();await f.chats.settled(f.chat.id);await f.jobs.tick();}

test('one-off reminder persists, notifies without a model call and never repeats after restart',async()=>{
 const f=await fixture();try{
  const input=f.input(),j=await f.jobs.create(input);expect((await f.jobs.create(input)).id).toBe(j.id);
  f.setTime(1000);await finish(f);expect(f.calls).toHaveLength(0);expect(f.sent).toHaveLength(1);expect(f.sent[0].sid).toBe(f.chat.id);
  expect((await f.chats.detail(f.chat.id)).messages.at(-1)!.text).toContain(input.instructions);
  f.reload();await finish(f);expect(f.sent).toHaveLength(1);expect((await f.jobs.list(f.chat.id))[0]!.enabled).toBe(false);
 }finally{await f.close();}
});
test('the same recurring instruction job stays quiet until it requests notification and stops',async()=>{
 const f=await fixture();try{
  await f.jobs.create({...f.input('run'),schedule:{kind:'interval',timezone:'Asia/Hong_Kong',everyMinutes:1}});
  f.setTime(60000);await finish(f);expect(f.calls).toHaveLength(1);expect(f.sent).toHaveLength(0);
  expect(f.calls[0]!.system).toContain('Be precise');expect(JSON.parse(f.calls[0]!.prompt).privateMemory).toContain('Pip');
  f.setDecision(true,true);f.setTime(60000);await finish(f);expect(f.sent).toHaveLength(1);expect((await f.jobs.list(f.chat.id))[0]!.enabled).toBe(false);
  expect(f.calls[1]!.native!.providerSessionID).toBe(f.calls[0]!.native!.providerSessionID);
  expect((await f.chats.detail(f.chat.id)).messages.at(-1)!.text).not.toContain('lfg_job_result');
 }finally{await f.close();}
});
test('push failure keeps a durable intent and retries it after restart without rerunning work',async()=>{
 const f=await fixture();try{
  f.setPushFailure(true);await f.jobs.create(f.input());f.setTime(1000);await finish(f);expect(f.sent).toHaveLength(1);
  f.reload();f.setPushFailure(false);f.setTime(120000);await f.jobs.tick();expect(f.sent).toHaveLength(2);expect(f.calls).toHaveLength(0);
  await f.jobs.tick();expect(f.sent).toHaveLength(2);
 }finally{await f.close();}
});
test('pause, revision checks, cancellation and invalid schedules preserve existing records',async()=>{
 const f=await fixture();try{
  const j=await f.jobs.create(f.input());await f.jobs.update(j.id,{revision:j.revision,enabled:false});
  await expect(f.jobs.update(j.id,{revision:j.revision,name:'Stale'})).rejects.toThrow('changed');
  f.setTime(2000);await finish(f);expect(f.sent).toHaveLength(0);
  await f.jobs.cancel(j.id);await expect(f.jobs.update(j.id,{revision:2,enabled:true})).rejects.toThrow('cancelled');
  await expect(f.jobs.create({...f.input(),schedule:{kind:'once',timezone:'Bad/Zone',at:'tomorrow'}})).rejects.toThrow();
 }finally{await f.close();}
});
test('result parser requires the matching run and distinguishes quiet checks from notifications',()=>{
 expect(parseJobResult(answer('one'),'one').decision.notify).toBe(false);
 expect(()=>parseJobResult(answer('other',true),'one')).toThrow();
 expect(()=>parseJobResult('I checked it; probably approved.','one')).toThrow();
 expect(()=>parseJobResult('```\n'+answer('one')+'\n```','one')).toThrow();
});

test('creation receipt survives its due time and edits without duplicating or changing the original request',async()=>{
 const f=await fixture();try{const input=f.input(),j=await f.jobs.create(input);await f.jobs.update(j.id,{revision:j.revision,name:'Edited'});f.setTime(10000);expect((await f.jobs.create(input)).name).toBe('Edited');await expect(f.jobs.create({...input,notification:'always',stopOnNotify:true})).rejects.toThrow('different');}finally{await f.close();}
});
test('cancel suppresses an unsent retry and malformed results never create an alert',async()=>{
 const f=await fixture();try{f.setPushFailure(true);const j=await f.jobs.create(f.input());f.setTime(1000);await finish(f);expect(f.sent).toHaveLength(1);await f.jobs.cancel(j.id);f.setTime(120000);f.setPushFailure(false);f.reload();await f.jobs.tick();expect(f.sent).toHaveLength(1);expect((await f.jobs.detail(j.id)).notifications[0]!.state).toBe('cancelled');}finally{await f.close();}
});
test('busy chats defer queued reminders and resume them after a pause without losing the occurrence',async()=>{
 const root=await mkdtemp(join(tmpdir(),'lfg-jobs-busy-'));let time=Date.now(),release!:(s:string)=>void;
 const chats=new ChatSessions(join(root,'chats'),{nativeConversations:true,run:async i=>{await i.native!.onReady();return new Promise<string>(r=>{release=r;});}});
 const jobs=new ChatJobs(join(root,'jobs.json'),chats,{now:()=>time});
 try{const chat=await chats.create({name:'Busy'});await chats.send(chat.id,{requestID:'manual',text:'Working'});while(!release)await Bun.sleep(1);
 const j=await jobs.create({chatId:chat.id,name:'Reminder',instructions:'Take a break',action:'notify',schedule:{kind:'once',timezone:'UTC',at:new Date(time+1000).toISOString()},requestID:'reminder'});
 time+=1000;await jobs.tick();expect((await jobs.detail(j.id)).runs[0]!.state).toBe('queued');
 const paused=await jobs.update(j.id,{revision:1,enabled:false});release('Done');await chats.settled(chat.id);await jobs.tick();expect((await jobs.detail(j.id)).runs[0]!.state).toBe('queued');
 await jobs.update(j.id,{revision:paused.revision,enabled:true});await jobs.tick();expect((await jobs.detail(j.id)).runs[0]!.state).toBe('completed');
 }finally{await jobs.close();await chats.close();await rm(root,{recursive:true,force:true});}
});
