import { test, expect } from 'bun:test';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { messageRoutes } from './cua-message';

test('create, message, follow up and reload retain the same Space and agent run', async () => {
 const root = await mkdtemp(join(tmpdir(), 'lfg-cua-'));
 const calls: any[] = [];
 const cua = { async call(name: string, args: any) {
  calls.push({name,args});
  if(name==='create_space') return {id:'local:lfg-message-test', name:args.name};
  if(name==='list_spaces') return [{id:'local:lfg-message-test',power_state:'running'}];
  if(name==='agent_start') return {run_id:'run-test'};
  if(name==='agent_message') return {delivered:true};
  if(name==='agent_events') return {events:[{seq:1,kind:'message',text:'Research complete'}],cursor:1,status:'idle'};
  return {};
 }};
 const route=messageRoutes(cua,root);
 const req=async(path:string,body?:any)=>route(new Request('http://test/api/message'+path,{method:body?'POST':'GET',...(body?{body:JSON.stringify(body)}:{})}));
 try {
  const created=await (await req('/spaces',{name:'Scout',agent:'claude-code'}))!.json() as any;
  const id=created.space.id;
  expect((await req(`/spaces/${id}/messages`,{text:'Research this',requestID:'first'}))!.status).toBe(200);
  expect((await req(`/spaces/${id}/messages`,{text:'Research this',requestID:'first'}))!.status).toBe(200);
  expect(calls.filter(c=>c.name==='agent_start')).toHaveLength(1);
  await req(`/spaces/${id}/messages`,{text:'Explain more',requestID:'second'});
  expect(calls.find(c=>c.name==='agent_message').args.run_id).toBe('run-test');
  const reloaded=messageRoutes(cua,root);
  const detail=await (await reloaded(new Request(`http://test/api/message/spaces/${id}?cursor=0`)))!.json() as any;
  expect(detail.space.messages.map((m:any)=>m.text)).toEqual(['Research this','Explain more']);
  expect(detail.events[0].text).toBe('Research complete');
  const list=await (await req('/spaces'))!.json() as any;
  expect(list.spaces[0].powerState).toBe('running');
  expect(calls.find(c=>c.name==='create_space').args.on).toBe('local');
 } finally {await rm(root,{recursive:true,force:true});}
});

test('invalid input and path traversal never reach Cua',async()=>{
 const root=await mkdtemp(join(tmpdir(),'lfg-cua-'));
 let count=0;
 const route=messageRoutes({call:async()=>{count++;return {};}},root);
 try {
  for(const body of [{name:''},{name:'A',agent:'unknown'}]) {
   expect((await route(new Request('http://t/api/message/spaces',{method:'POST',body:JSON.stringify(body)})))!.status).toBe(400);
  }
  expect((await route(new Request('http://t/api/message/spaces/not-owned/messages',{method:'POST',body:'{}'})))!.status).toBe(404);
  expect(count).toBe(0);
 } finally {await rm(root,{recursive:true,force:true});}
});

test('uncertain starts cannot be repeated and rejected followups preserve the run',async()=>{
 const root=await mkdtemp(join(tmpdir(),'lfg-cua-'));let starts=0;
 const route=messageRoutes({call:async(name,args)=>{
  if(name==='create_space')return {id:'local:test'};
  if(name==='agent_start'){starts++;throw Error('connection lost');}
  return {};
 }},root);
 try {
 const created=await (await route(new Request('http://t/api/message/spaces',{method:'POST',body:'{"name":"A"}'})))!.json() as any;
 const path=`http://t/api/message/spaces/${created.space.id}/messages`;
 expect((await route(new Request(path,{method:'POST',body:'{"text":"Work","requestID":"one"}'})))!.status).toBe(502);
 expect((await route(new Request(path,{method:'POST',body:'{"text":"Work","requestID":"two"}'})))!.status).toBe(409);
 expect(starts).toBe(1);
 }finally{await rm(root,{recursive:true,force:true});}
});

test('browser actions stay bound to their Space and require an observed frame for clicks',async()=>{
 const root=await mkdtemp(join(tmpdir(),'lfg-cua-'));const calls:any[]=[];
 const route=messageRoutes({call:async(name,args)=>{
  calls.push({name,args});
  if(name==='create_space')return {id:'local:browser'};
  if(name==='call_tool'&&args.tool==='get_desktop_state')return {screenshot_width:1000,screenshot_height:600,capture_id:'capture-test',content:[{type:'image',data:'cG5n',mimeType:'image/png'}]};
  return {};
 }},root);
 try {
 const space=(await (await route(new Request('http://t/api/message/spaces',{method:'POST',body:'{"name":"Browser"}'})))!.json() as any).space;
 const send=async(body:any)=>route(new Request(`http://t/api/message/spaces/${space.id}/browser`,{method:'POST',body:JSON.stringify(body)}));
 expect((await send({action:'click',x:'0.5',y:'0.5'}))!.status).toBe(409);
 const image=await (await send({action:'screenshot'}))!.json() as any;expect(image.imageBase64).toBe('cG5n');
 expect((await send({action:'click',x:'0.5',y:'0.5'}))!.status).toBe(200);
 const click=calls.find(c=>c.name==='call_tool'&&c.args.tool==='click');
 expect(click.args.space).toBe('local:browser');expect(click.args.arguments.x).toBe(500);expect(click.args.arguments.y).toBe(300);
 expect(click.args.arguments.capture_id).toBe('capture-test');
 expect(click.args.arguments.scope).toBeUndefined();
 expect(click.args.arguments.target).toEqual({kind:'desktop',display_id:'primary'});
 expect((await send({action:'move',x:'1',y:'0'}))!.status).toBe(200);
 expect((await send({action:'rightClick',x:'0.3',y:'0.4',live:'true'}))!.status).toBe(200);expect(calls.filter(c=>c.args.tool==='click').at(-1).args.arguments.button).toBe('right');
 const move=calls.find(c=>c.args.tool==='move_cursor');expect(move.args.arguments.x).toBe(999);expect(move.args.arguments.scope).toBe('desktop');expect(move.args.arguments.delivery_mode).toBeUndefined();expect(move.args.arguments.target).toBeUndefined();
 expect((await send({action:'drag',x:'0.9',y:'0.8',fromX:'0.1',fromY:'0.2'}))!.status).toBe(200);
 const drag=calls.find(c=>c.args.tool==='drag');expect(drag.args.arguments.from_x).toBe(100);expect(drag.args.arguments.to_y).toBe(479);
 expect((await send({action:'drag',x:'0.9',y:'0.8',fromX:'-1',fromY:'0.2'}))!.status).toBe(400);
 expect((await send({action:'move',x:'2',y:'0'}))!.status).toBe(400);
 expect((await send({action:'type',text:'  hello \n'}))!.status).toBe(200);expect(calls.find(c=>c.args.tool==='type_text').args.arguments.text).toBe('  hello \n');
 expect((await send({action:'key',key:'ctrl+shift+a'}))!.status).toBe(200);expect(calls.find(c=>c.args.tool==='hotkey').args.arguments.keys).toEqual(['ctrl','shift','a']);
 expect((await send({action:'key',key:'ctrl+shell+rm'}))!.status).toBe(400);
 expect((await send({action:'navigate',url:'file:///etc/passwd'}))!.status).toBe(400);
 expect((await send({action:'navigate',url:'https://example.com/?q=%27%3Btouch%20%2Ftmp%2Fbad'}))!.status).toBe(200);
 expect(calls.find(c=>c.name==='space_bash').args.command).toStartWith("xdg-open 'https://example.com/");
 }finally{await rm(root,{recursive:true,force:true});}
});

test('a running agent blocks manual browser mutations',async()=>{
 const root=await mkdtemp(join(tmpdir(),'lfg-cua-'));const calls:any[]=[];
 const route=messageRoutes({call:async(name,args)=>{
  calls.push(name);if(name==='create_space')return {id:'local:test'};
  if(name==='agent_start')return {run_id:'run'};
  if(name==='agent_status')return {status:'running'};return {};
 }},root);
 try {
 const space=(await (await route(new Request('http://t/api/message/spaces',{method:'POST',body:'{"name":"A"}'})))!.json() as any).space;
 await route(new Request(`http://t/api/message/spaces/${space.id}/messages`,{method:'POST',body:'{"text":"Work","requestID":"one"}'}));
 const r=await route(new Request(`http://t/api/message/spaces/${space.id}/browser`,{method:'POST',body:'{"action":"navigate","url":"https://example.com"}'}));
 expect(r!.status).toBe(409);expect(calls.includes('space_bash')).toBe(false);
 for(const action of ['move','drag','rightClick','key','type']){
  const blocked=await route(new Request(`http://t/api/message/spaces/${space.id}/browser`,{method:'POST',body:JSON.stringify({action,x:'0',y:'0',key:'a',text:'hello'})}));expect(blocked!.status).toBe(409);
 }
 expect(calls.includes('call_tool')).toBe(false);
 }finally{await rm(root,{recursive:true,force:true});}
});

test('missing provider authentication fails before recording a pending message',async()=>{
 const root=await mkdtemp(join(tmpdir(),'lfg-cua-'));let starts=0;
 const route=messageRoutes({call:async(name)=>{
  if(name==='create_space')return {id:'local:test'};
  if(name==='agent_capabilities')return {harnesses:[{id:'claude-code',auth:'missing',auth_hint:'Configure an Anthropic key in Cua'}]};
  if(name==='agent_start')starts++;return {};
 }},root);
 try {
 const space=(await (await route(new Request('http://t/api/message/spaces',{method:'POST',body:'{"name":"A"}'})))!.json() as any).space;
 const path=`http://t/api/message/spaces/${space.id}`;
 expect((await route(new Request(path+'/messages',{method:'POST',body:'{"text":"Work","requestID":"one"}'})))!.status).toBe(503);
 const after=await (await route(new Request(path)))!.json() as any;
 expect(after.space.pending).toBeUndefined();expect(after.space.messages).toEqual([]);expect(starts).toBe(0);
 }finally{await rm(root,{recursive:true,force:true});}
});

test('a definitively rejected followup does not block the next message',async()=>{
 const root=await mkdtemp(join(tmpdir(),'lfg-cua-'));let reject=true;
 const route=messageRoutes({call:async(name)=>{
  if(name==='create_space')return {id:'local:test'};
  if(name==='agent_start')return {run_id:'run'};
  if(name==='agent_message')return reject?{delivered:false,reason:'Turn is busy'}:{delivered:true};
  return {};
 }},root);
 try {
 const space=(await (await route(new Request('http://t/api/message/spaces',{method:'POST',body:'{"name":"A"}'})))!.json() as any).space;
 const path=`http://t/api/message/spaces/${space.id}/messages`;
 await route(new Request(path,{method:'POST',body:'{"text":"Start","requestID":"one"}'}));
 expect((await route(new Request(path,{method:'POST',body:'{"text":"Followup","requestID":"two"}'})))!.status).toBe(409);
 reject=false;
 const response=await route(new Request(path,{method:'POST',body:'{"text":"Followup","requestID":"three"}'}));
 expect(response!.status).toBe(200);
 const result=await response!.json() as any;expect(result.space.pending).toBeUndefined();
 expect(result.space.messages.map((m:any)=>m.id)).toEqual(['one','three']);
 }finally{await rm(root,{recursive:true,force:true});}
});

test('a CLI without persistent-agent extensions fails before recording pending work',async()=>{
 const root=await mkdtemp(join(tmpdir(),'lfg-cua-'));let starts=0;
 const route=messageRoutes({call:async(name)=>{
  if(name==='create_space')return {id:'local:test'};
  if(name==='persistent_agent_list')throw Error('Persistent agents require the full Cua Spaces runtime');
  if(name==='agent_start')starts++;return {};
 }},root);
 try {
 const space=(await (await route(new Request('http://t/api/message/spaces',{method:'POST',body:'{"name":"A"}'})))!.json() as any).space;
 const path=`http://t/api/message/spaces/${space.id}`;
 expect((await route(new Request(path+'/messages',{method:'POST',body:'{"text":"Work","requestID":"one"}'})))!.status).toBe(502);
 const after=await (await route(new Request(path)))!.json() as any;
 expect(after.space.pending).toBeUndefined();expect(after.space.messages).toEqual([]);expect(starts).toBe(0);
 }finally{await rm(root,{recursive:true,force:true});}
});

test('event responses preserve the cursor while excluding raw tool output and internal thoughts',async()=>{
 const root=await mkdtemp(join(tmpdir(),'lfg-cua-'));
 const route=messageRoutes({call:async(name)=>{
  if(name==='create_space')return {id:'local:test'};
  if(name==='agent_start')return {run_id:'run'};
  if(name==='agent_events')return {cursor:100,status:'idle',events:[
   {seq:1,kind:'message',text:'Done',ts_ms:1,raw:{secret:'raw-payload'}},
   {seq:2,kind:'tool_update',text:'PRIVATE RAW TREE'},
   {seq:3,kind:'thought',text:'PRIVATE THOUGHT'},
   {seq:4,kind:'tool_call',summary:'Tool launch_app',raw:{secret:'raw-tool'}}]};
  return {};
 }},root);
 try {
 const space=(await (await route(new Request('http://t/api/message/spaces',{method:'POST',body:'{"name":"A"}'})))!.json() as any).space;
 const path=`http://t/api/message/spaces/${space.id}`;
 await route(new Request(path+'/messages',{method:'POST',body:'{"text":"Work","requestID":"one"}'}));
 const r=await (await route(new Request(path)))!.json() as any;
 expect(r.cursor).toBe(100);expect(r.events.map((e:any)=>e.seq)).toEqual([1,4]);
 expect(JSON.stringify(r)).not.toContain('PRIVATE');expect(JSON.stringify(r)).not.toContain('raw-payload');
 }finally{await rm(root,{recursive:true,force:true});}
});

test('a stopped Space returns its state without polling an unreachable agent',async()=>{
 const root=await mkdtemp(join(tmpdir(),'lfg-cua-'));let eventCalls=0;
 const route=messageRoutes({call:async(name)=>{
  if(name==='create_space')return {id:'local:test'};
  if(name==='agent_start')return {run_id:'run'};
  if(name==='agent_events'){eventCalls++;return {events:[],cursor:42,status:'idle'};}
  return {};
 }},root);
 try {
 const space=(await (await route(new Request('http://t/api/message/spaces',{method:'POST',body:'{"name":"A"}'})))!.json() as any).space;
 const path=`http://t/api/message/spaces/${space.id}`;
 await route(new Request(path+'/messages',{method:'POST',body:'{"text":"Work","requestID":"one"}'}));
 await route(new Request(path+'/power',{method:'POST',body:'{"action":"stop"}'}));
 const off=await (await route(new Request(path+'?cursor=42')))!.json() as any;
 expect(off.status).toBe('stopped');expect(off.cursor).toBe(42);expect(eventCalls).toBe(0);
 await route(new Request(path+'/power',{method:'POST',body:'{"action":"start"}'}));
 const on=await (await route(new Request(path+'?cursor=42')))!.json() as any;
 expect(on.status).toBe('idle');expect(eventCalls).toBe(1);
 }finally{await rm(root,{recursive:true,force:true});}
});

test('live view only upgrades owned, running Spaces and rejects foreign origins',async()=>{
 const root=await mkdtemp(join(tmpdir(),'lfg-cua-live-'));let upgrades=0;const calls:string[]=[];
 const route=messageRoutes({call:async(name)=>{calls.push(name);if(name==='create_space')return {id:'local:live'};
  if(name==='stream_endpoint')return {wire_version:2,ws_url:'ws://127.0.0.1:12345/media?ticket=private',ticket_expires_at:new Date(Date.now()+60000).toISOString()};return {};
 }},root,(_req,stream)=>{upgrades++;stream.close();return true;});
 try{
  const space=(await (await route(new Request('http://t/api/message/spaces',{method:'POST',body:'{"name":"Live"}'})))!.json() as any).space;
  const path=`http://t/api/message/spaces/${space.id}`;
  expect((await route(new Request(path+'/stream')))!.status).toBe(426);
  expect((await route(new Request(path+'/stream',{headers:{upgrade:'websocket',origin:'http://evil'}})))!.status).toBe(403);
  expect(await route(new Request(path+'/stream',{headers:{upgrade:'websocket'}}))).toBeUndefined();
  expect(upgrades).toBe(1);
  await route(new Request(path+'/power',{method:'POST',body:'{"action":"stop"}'}));
  expect((await route(new Request(path+'/stream',{headers:{upgrade:'websocket'}})))!.status).toBe(409);
  expect(calls.filter(n=>n==='stream_endpoint')).toHaveLength(1);
 }finally{await rm(root,{recursive:true,force:true});}
});

test('taking control confirms an agent stopped before accepting manual input',async()=>{
 const root=await mkdtemp(join(tmpdir(),'lfg-cua-control-'));let interrupted=false;const calls:string[]=[];
 const route=messageRoutes({call:async(name,args)=>{calls.push(name);if(name==='create_space')return {id:'local:control'};
  if(name==='agent_start')return {run_id:'run'};
  if(name==='agent_interrupt'){interrupted=true;return {};}
  if(name==='agent_status')return {status:interrupted?'idle':'running'};
  return {};
 }},root);
 try{
  const space=(await (await route(new Request('http://t/api/message/spaces',{method:'POST',body:'{"name":"Control"}'})))!.json() as any).space;
  const path=`http://t/api/message/spaces/${space.id}`;
  await route(new Request(path+'/messages',{method:'POST',body:'{"text":"Work","requestID":"one"}'}));
  expect((await route(new Request(path+'/browser',{method:'POST',body:'{"action":"type","text":"test"}'})))!.status).toBe(409);
  expect((await route(new Request(path+'/browser',{method:'POST',body:'{"action":"takeControl"}'})))!.status).toBe(200);
  expect(calls).toContain('agent_interrupt');
  expect((await route(new Request(path+'/browser',{method:'POST',body:'{"action":"type","text":"test"}'})))!.status).toBe(200);
  expect((await route(new Request(path+'/browser',{method:'POST',body:'{"action":"scroll","direction":"sideways"}'})))!.status).toBe(400);
 }finally{await rm(root,{recursive:true,force:true});}
});

test('takeover waits through queued cancellation and sends only one interrupt',async()=>{
 const root=await mkdtemp(join(tmpdir(),'lfg-cua-delay-'));let polls=0,interrupts=0;
 const route=messageRoutes({call:async(name)=>{
  if(name==='create_space')return {id:'local:starting'};
  if(name==='agent_start')return {run_id:'run'};
  if(name==='agent_interrupt'){interrupts++;return {};}
  if(name==='agent_status')return {status:++polls<4?'running':'idle'};
  return {};
 }},root);
 try{
  const space=(await (await route(new Request('http://t/api/message/spaces',{method:'POST',body:'{"name":"Starting"}'})))!.json() as any).space;
  const path=`http://t/api/message/spaces/${space.id}`;
  await route(new Request(path+'/messages',{method:'POST',body:'{"text":"Work","requestID":"one"}'}));
  const response=await route(new Request(path+'/browser',{method:'POST',body:'{"action":"takeControl"}'}));
  expect(response!.status).toBe(200);expect(interrupts).toBe(1);expect(polls).toBe(4);
 }finally{await rm(root,{recursive:true,force:true});}
});

test('configured image profile provisions Codex, preserves mount context, and owns power lifecycle',async()=>{
 const root=await mkdtemp(join(tmpdir(),'lfg-profile-route-'));const calls:any[]=[];let power='running';
 const cua={call:async(name:string,args:any)=>{calls.push({name,args});if(name==='list_spaces')return [{id:'direct:127.0.0.1:4321',phase:'ready'}];if(name==='agent_capabilities')return {harnesses:[{id:'openai-codex',auth:'missing'}]};if(name==='agent_start')return {run_id:'codex-run'};return {};}};
 const containers={profile:{codexModel:'gpt-6.1-sol'},create:async()=>({id:'direct:127.0.0.1:4321',containerName:'lfg-owned',guestCodexAuth:true,sharedPaths:[{path:'/pro/projects',readOnly:true}]}),state:async()=>power,power:async(_name:string,action:string)=>{power=action==='stop'?'stopped':'running';}} as any;
 const route=messageRoutes(cua,root,undefined,containers);
 const req=(path:string,body?:any)=>route(new Request('http://test/api/message'+path,{method:body?'POST':'GET',...(body?{body:JSON.stringify(body)}:{})}));
 const space=(await (await req('/spaces',{name:'Ready'}))!.json() as any).space;
 expect(space.agent).toBe('openai-codex');expect(space.containerName).toBe('lfg-owned');
 expect((await req(`/spaces/${space.id}/messages`,{text:'Read a file',requestID:'one'}))!.status).toBe(200);
 const start=calls.find(c=>c.name==='agent_start');expect(start.args.model).toBe('gpt-6.1-sol');expect(start.args.prompt).toContain('/pro/projects (read-only)');expect(start.args.mcp_servers).toBeUndefined();
 expect((await req(`/spaces/${space.id}/power`,{action:'stop'}))!.status).toBe(200);
 const list=await (await req('/spaces'))!.json() as any;expect(list.spaces[0].powerState).toBe('stopped');expect(calls.some(c=>c.name==='stop_space')).toBe(false);
});
