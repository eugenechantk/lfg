import {test,expect} from 'bun:test';
import {mkdtemp,readFile,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {messageRoutes} from './cua-message';

async function fixture(){
 const root=await mkdtemp(join(tmpdir(),'lfg-idle-'));
 let time=0,state='running',status='idle',starts=0,stops=0,failStatus=false,failHistory=false;
 const calls:{name:string;args:any}[]=[];
 const cua={call:async(name:string,args:any):Promise<any>=>{
  calls.push({name,args});
  if(name==='create_space')return {id:'local:test'};
  if(name==='list_spaces')return [{id:'local:test',power_state:'running'}];
  if(name==='agent_start'){starts++;return {run_id:'run-'+starts};}
  if(name==='agent_status'){if(failStatus)throw Error('offline');return {status};}
  if(name==='agent_events'){if(failHistory)throw Error('history offline');return {status,events:[{seq:1,kind:'message',text:'Saved answer',ts_ms:1000}],cursor:1};}
  if(name==='agent_message')return {delivered:true};
  if(name==='stream_endpoint')return {wire_version:2,ws_url:'ws://127.0.0.1:1234',ticket_expires_at:new Date(Date.now()+60_000).toISOString()};
  return {};
 }};
 const runtime={state:async()=>state,power:async(_name:string,action:'start'|'stop')=>{state=action==='stop'?'stopped':'running';if(action==='stop')stops++;}};
 let viewer:any;
 const route=messageRoutes(cua,root,(_req,stream)=>{viewer=stream;return true;},undefined,{runtime,now:()=>time,idleTimeoutMs:1000});
 const request=(path:string,body?:any)=>route(new Request('http://test/api/message'+path,{method:body?'POST':'GET',...(body?{body:JSON.stringify(body)}:{})}));
 const created=await request('/spaces',{name:'Idle'}),space=(await created!.json() as any).space;
 const path='/spaces/'+space.id;
 const read=async()=>JSON.parse(await readFile(join(root,space.id+'.json'),'utf8'));
 const update=async(values:any)=>writeFile(join(root,space.id+'.json'),JSON.stringify({...await read(),...values}));
 return {route,request,path,read,update,calls,cua,root,runtime,
  time:(value:number)=>{time=value;},state:(value:string)=>{state=value;},status:(value:string)=>{status=value;},
  failStatus:(value=true)=>{failStatus=value;},failHistory:()=>{failHistory=true;},stops:()=>stops,viewer:()=>viewer,
  close:async()=>{viewer?.close();route.close();await rm(root,{recursive:true,force:true});},
 };
}

test('an unused local Space stops after the idle grace period without a UI request',async()=>{
 const f=await fixture();try{
  await f.route.sweepIdle();f.time(999);await f.route.sweepIdle();expect(f.stops()).toBe(0);
  f.time(1000);await f.route.sweepIdle();expect(f.stops()).toBe(1);expect((await f.read()).powerState).toBe('stopped');
  await f.route.sweepIdle();expect(f.stops()).toBe(1);
  expect(f.calls.some(c=>c.name==='stop_space')).toBe(false);
 }finally{await f.close();}
});

for(const status of ['running','queued','starting','unknown'])test(`${status} agents are never treated as idle`,async()=>{
 const f=await fixture();try{
  await f.request(f.path+'/messages',{text:'Work',requestID:'one'});f.status(status);
  await f.route.sweepIdle();f.time(100_000);await f.route.sweepIdle();expect(f.stops()).toBe(0);
 }finally{await f.close();}
});

test('pending delivery and status failures protect a Space',async()=>{
 const f=await fixture();try{
  await f.request(f.path+'/messages',{text:'Work',requestID:'one'});
  await f.update({pending:'unconfirmed'});await f.route.sweepIdle();f.time(2000);await f.route.sweepIdle();expect(f.stops()).toBe(0);
  await f.update({pending:undefined});f.failStatus();await f.route.sweepIdle();f.time(4000);await f.route.sweepIdle();expect(f.stops()).toBe(0);
 }finally{await f.close();}
});

test('a connected viewer protects an otherwise idle desktop',async()=>{
 const f=await fixture();try{
  await f.route(new Request('http://test/api/message'+f.path+'/stream',{headers:{upgrade:'websocket'}}));
  await f.route.sweepIdle();f.time(2000);await f.route.sweepIdle();expect(f.stops()).toBe(0);
  f.viewer().close();await f.route.sweepIdle();f.time(3000);await f.route.sweepIdle();expect(f.stops()).toBe(1);
 }finally{await f.close();}
});

test('browser activity resets idle time while background chat polling does not',async()=>{
 const f=await fixture();try{
  await f.route.sweepIdle();f.time(900);
  await f.request(f.path+'/browser',{action:'type',text:'hello'});
  await f.route.sweepIdle();f.time(1000);await f.request(f.path);await f.route.sweepIdle();expect(f.stops()).toBe(0);
  f.time(1900);await f.route.sweepIdle();expect(f.stops()).toBe(1);
 }finally{await f.close();}
});

test('completed replies survive automatic stop, reload and a fresh follow-up run',async()=>{
 const f=await fixture();try{
  await f.request(f.path+'/messages',{text:'First task',requestID:'one'});
  await f.route.sweepIdle();f.time(1000);await f.route.sweepIdle();expect(f.stops()).toBe(1);
  const reloaded=messageRoutes(f.cua,f.root,undefined,undefined,{runtime:f.runtime});
  const detail=await (await reloaded(new Request('http://test/api/message'+f.path)))!.json() as any;
  expect(detail.events[0].text).toBe('Saved answer');expect(detail.space.runID).toBeUndefined();expect(detail.space.lastRunID).toBe('run-1');
  expect((await f.request(f.path+'/messages',{text:'Too soon',requestID:'blocked'}))!.status).toBe(409);
  await f.request(f.path+'/power',{action:'start'});
  expect((await f.request(f.path+'/messages',{text:'Follow up',requestID:'two'}))!.status).toBe(200);
  const starts=f.calls.filter(c=>c.name==='agent_start');expect(starts).toHaveLength(2);expect(starts[1].args.prompt).toContain('Saved answer');
  const after=await (await f.request(f.path+'?cursor=1'))!.json() as any;
  expect(after.events[0].seq).toBe(2);expect(after.cursor).toBe(2);
  expect(f.calls.some(c=>c.name==='agent_message')).toBe(false);reloaded.close();
 }finally{await f.close();}
});

test('history failure prevents automatic stop but explicit off can stop an unreachable guest',async()=>{
 const f=await fixture();try{
  await f.request(f.path+'/messages',{text:'Work',requestID:'one'});f.failHistory();
  await f.route.sweepIdle();f.time(1000);await f.route.sweepIdle();expect(f.stops()).toBe(0);
  expect((await f.request(f.path+'/power',{action:'stop'}))!.status).toBe(200);expect(f.stops()).toBe(1);
 }finally{await f.close();}
});

test('cleanup rechecks the agent after saving final events',async()=>{
 const f=await fixture();try{
  await f.request(f.path+'/messages',{text:'Work',requestID:'one'});await f.route.sweepIdle();f.time(1000);
  const original=f.cua.call;f.cua.call=async(name,args)=>{const value=await original(name,args);if(name==='agent_events')f.status('running');return value;};
  await f.route.sweepIdle();expect(f.stops()).toBe(0);
 }finally{await f.close();}
});

test('legacy suspended Spaces release memory without needing an agent connection',async()=>{
 const f=await fixture();try{
  f.state('suspended');await f.route.sweepIdle();expect(f.stops()).toBe(1);expect(f.calls.some(c=>c.name==='agent_status')).toBe(false);
 }finally{await f.close();}
});

test('cleanup ignores remote and unowned records',async()=>{
 const f=await fixture();try{
  await f.update({spaceID:'cloud:foreign'});await f.route.sweepIdle();f.time(5000);await f.route.sweepIdle();expect(f.stops()).toBe(0);
 }finally{await f.close();}
});

test('a failed status observation resets the idle grace period',async()=>{
 const f=await fixture();try{
  await f.request(f.path+'/messages',{text:'Work',requestID:'one'});await f.route.sweepIdle();
  f.time(900);f.failStatus();await f.route.sweepIdle();f.failStatus(false);
  f.time(1000);await f.route.sweepIdle();expect(f.stops()).toBe(0);
  f.time(2000);await f.route.sweepIdle();expect(f.stops()).toBe(1);
 }finally{await f.close();}
});

test('manual start retires stale process references after an external container stop',async()=>{
 const f=await fixture();try{
  await f.request(f.path+'/messages',{text:'Work',requestID:'one'});f.state('stopped');
  await f.request(f.path+'/power',{action:'start'});
  expect((await f.read()).runID).toBeUndefined();expect((await f.read()).lastRunID).toBe('run-1');
 }finally{await f.close();}
});

test('cleanup skips in-flight requests and does not overlap itself',async()=>{
 const f=await fixture();try{
  await f.route.sweepIdle();f.time(1000);
  let release!:()=>void;const gate=new Promise<void>(r=>release=r),original=f.cua.call;
  f.cua.call=async(name,args)=>{if(name==='space_bash')await gate;return original(name,args);};
  const mutation=f.request(f.path+'/browser',{action:'navigate',url:'https://example.com'});
  await Bun.sleep(10);await Promise.all([f.route.sweepIdle(),f.route.sweepIdle()]);expect(f.stops()).toBe(0);
  release();await mutation;
 }finally{await f.close();}
});

test('profile power start persists the refreshed Cua endpoint for subsequent requests',async()=>{
 const root=await mkdtemp(join(tmpdir(),'lfg-endpoint-'));let state='running',cuaName='';const calls:any[]=[];
 const containers={profile:{},create:async()=>({id:'direct:127.0.0.1:1234',containerName:'lfg-profile'}),state:async()=>state,power:async(_name:string,action:string)=>{state=action==='stop'?'stopped':'running';},resume:async()=>{state='running';return 'direct:127.0.0.1:5678';}} as any;
 const route=messageRoutes({call:async(name,args)=>{calls.push({name,args});if(name==='list_spaces')return [{id:'direct:127.0.0.1:1234',name:cuaName},{id:'direct:127.0.0.1:5678',name:cuaName}];return {};}},root,undefined,containers);
 const req=(path:string,body:any)=>route(new Request('http://test/api/message'+path,{method:'POST',body:JSON.stringify(body)}));
 try{
  const space=(await (await req('/spaces',{name:'Profile'}))!.json() as any).space,path='/spaces/'+space.id;
  cuaName=space.cuaName;
  await req(path+'/power',{action:'stop'});
  const restarted=await (await req(path+'/power',{action:'start'}))!.json() as any;expect(restarted.space.spaceID).toBe('direct:127.0.0.1:5678');
  await req(path+'/browser',{action:'type',text:'test'});expect(calls.at(-1).args.space).toBe('direct:127.0.0.1:5678');
  const list=await (await route(new Request('http://test/api/message/spaces')))!.json() as any;
  expect(list.spaces[0].spaceID).toBe('direct:127.0.0.1:5678');
 }finally{route.close();await rm(root,{recursive:true,force:true});}
});
