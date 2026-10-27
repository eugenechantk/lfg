import {test,expect} from 'bun:test';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {ChatSessions} from './chat-sessions';
import {ChatJobs} from './chat-jobs';
import {chatJobRoutes} from './chat-job-api';
import {apnsBody} from './push/apns';

test('chat-scoped MCP creates both job actions, retains schedule receipts and rejects cross-chat mutation',async()=>{
 const root=await mkdtemp(join(tmpdir(),'jobs-api-')),chats=new ChatSessions(join(root,'chats'),{run:async()=>''});const jobs=new ChatJobs(join(root,'jobs.json'),chats),route=chatJobRoutes(jobs);
 try{
 const a=await chats.create({name:'A'}),b=await chats.create({name:'B'});
 const rpc=async(chat:string,name:string,args:any={})=>{const r=await route(new Request(`http://test/api/chat-jobs/mcp/${chat}`,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({jsonrpc:'2.0',id:1,method:'tools/call',params:{name,arguments:args}})}));return await r!.json() as any;};
 const input={name:'Review',instructions:'Check until approved, notify and stop.',action:'run',schedule:{kind:'interval',timezone:'Asia/Hong_Kong',everyMinutes:60},requestID:'review'};
 const result=await rpc(a.id,'create_job',input);const j=JSON.parse(result.result.content[0].text).job;expect(j.chatId).toBe(a.id);expect(j.action).toBe('run');
 const reminder=await rpc(a.id,'create_job',{...input,action:'notify',requestID:'reminder'});expect(JSON.parse(reminder.result.content[0].text).job.action).toBe('notify');
 const forbidden=await rpc(b.id,'cancel_job',{jobId:j.id});expect(forbidden.result.isError).toBe(true);expect((await jobs.detail(j.id)).job.enabled).toBe(true);
 const otherOrigin=await route(new Request('http://test/api/chat-jobs',{method:'POST',headers:{origin:'http://evil'},body:'{}'}));expect(otherOrigin!.status).toBe(403);
 const updated=await route(new Request(`http://test/api/chat-jobs/${j.id}`,{method:'POST',body:JSON.stringify({revision:1,enabled:false})}));expect(updated!.status).toBe(200);
 const stale=await route(new Request(`http://test/api/chat-jobs/${j.id}`,{method:'POST',body:JSON.stringify({revision:1,enabled:true})}));expect(stale!.status).toBe(409);
 const wire=JSON.parse(apnsBody({title:'Reminder',body:'Review',sid:a.id,kind:'job',notificationId:'event',hostId:'host',session:{id:a.id,kind:'chat'}}));expect(wire.sid).toBe(a.id);expect(wire.notificationId).toBe('event');expect(wire.aps.alert.body).toBe('Review');expect(wire.session.kind).toBe('chat');
 }finally{await jobs.close();await chats.close();await rm(root,{recursive:true,force:true});}
});
