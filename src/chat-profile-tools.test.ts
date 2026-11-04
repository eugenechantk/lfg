import {test,expect} from 'bun:test';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {ChatSessions,type ChatRunInput} from './chat-sessions';
import {ChatJobs} from './chat-jobs';
import {chatJobRoutes} from './chat-job-api';

test('conversation profile MCP persists requested settings during a turn and applies them on the next turn',async()=>{
 const root=await mkdtemp(join(tmpdir(),'lfg-profile-')),calls:ChatRunInput[]=[];
 let route:ReturnType<typeof chatJobRoutes>,first=true;
 const rpc=async(id:string,name:string,args:any={})=>{
  const response=await route(new Request(`http://test/api/scheduled-tasks/mcp/${id}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({jsonrpc:'2.0',id:1,method:'tools/call',params:{name,arguments:args}})}));
  return (await response!.json() as any).result;
 };
 const chats=new ChatSessions(join(root,'chats'),{nativeConversations:true,run:async input=>{
  calls.push(input);await input.native!.onReady();
  if(first){first=false;
   const read=JSON.parse((await rpc(input.native!.id,'get_chat_profile')).content[0].text).profile;
   expect(read.instructions).toBe('');
   const saved=await rpc(input.native!.id,'update_chat_profile',{revision:read.revision,name:'Editor',instructions:'Always use short sentences.',memory:'My dog is Pip',model:'sonnet'});
   expect(saved.isError).not.toBe(true);expect(JSON.parse(saved.content[0].text).profile.instructions).toBe('Always use short sentences.');
   const forbidden=await rpc(input.native!.id,'update_chat_profile',{revision:read.revision+1,chatId:'other',name:'Wrong'});
   expect(forbidden.isError).toBe(true);
   const stale=await rpc(input.native!.id,'update_chat_profile',{revision:read.revision,name:'Stale'});
   expect(stale.isError).toBe(true);
  }
  return 'Saved the requested settings.';
 }},{jobMcpURL:id=>`http://test/api/scheduled-tasks/mcp/${id}`});
 const jobs=new ChatJobs(join(root,'jobs.json'),chats);
 route=chatJobRoutes(jobs,async()=>null,chats);
 try{
  const chat=await chats.create({name:'Willow'}),other=await chats.create({name:'Other'});
  await chats.send(chat.id,{requestID:'one',text:'Call yourself Editor, remember Pip, and always use short sentences.'});await chats.settled(chat.id);
  expect((await chats.detail(other.id)).session.instructions).toBe('');
  expect((await chats.detail(chat.id)).session.name).toBe('Editor');
  await chats.send(chat.id,{requestID:'two',text:'Continue'});await chats.settled(chat.id);
  expect(calls[0]!.system).not.toContain('Current standing instructions:');
  expect(calls[0]!.system).toContain('Never conduct a setup interview');
  expect(calls[1]!.system).toContain('Always use short sentences.');
  expect(calls[1]!.model).toBe('sonnet');expect(JSON.parse(calls[1]!.prompt).privateMemory).toBe('My dog is Pip');
  await chats.close();
  const restored=new ChatSessions(join(root,'chats'),{run:async()=>''});
  try{expect((await restored.detail(chat.id)).session.instructions).toBe('Always use short sentences.');}finally{await restored.close();}
 }finally{await jobs.close();await chats.close();await rm(root,{recursive:true,force:true});}
});

test('profile writes require an active user turn and never run from scheduled work',async()=>{
 const root=await mkdtemp(join(tmpdir(),'lfg-profile-guard-'));
 let chats:ChatSessions;
 chats=new ChatSessions(root,{nativeConversations:true,run:async input=>{
  await input.native!.onReady();
  await expect(chats.updateFromConversation(input.native!.id,{revision:1,instructions:'Inferred by scheduler'})).rejects.toThrow('active user conversation');
  const run=JSON.parse(input.prompt).scheduledJob.runID;
  return `Checked.\n<lfg_job_result>${JSON.stringify({run_id:run,notify:false,message:'',stop:false})}</lfg_job_result>`;
 }});
 try{
  const chat=await chats.create({name:'Scheduled'});
  await expect(chats.updateFromConversation(chat.id,{revision:1,name:'No active user'})).rejects.toThrow('active user conversation');
  await chats.send(chat.id,{requestID:'job',text:'Check condition'},{runID:'run',name:'Condition'});await chats.settled(chat.id);
  expect((await chats.detail(chat.id)).session.instructions).toBe('');
 }finally{await chats.close();await rm(root,{recursive:true,force:true});}
});
