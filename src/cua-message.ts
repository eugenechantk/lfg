import { mkdir, readFile, writeFile, rename, readdir } from 'node:fs/promises';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import type { CuaTools } from './cua-mcp';
import type { CuaContainers, CuaContainerRuntime } from './cua-container';
import { CuaStreams, type CuaStream } from './cua-stream';

type Message = { id: string; text: string; date: number };
type AgentEvent = {seq:number;kind:string;ts_ms?:number;category?:string;text?:string;summary?:string};
type Space = { id: string; name: string; cuaName: string; spaceID?: string; agent: string; runID?: string; powerState: string; messages: Message[]; pending?: string; error?: string; createdAt: number; containerName?:string; guestCodexAuth?:boolean; sharedPaths?:{path:string;readOnly:boolean}[]; lastActivityAt?:number; idleSince?:number; events?:AgentEvent[]; eventCursor?:number; eventOffset?:number; lastRunID?:string };
type LifecycleOptions = {runtime?:Pick<CuaContainerRuntime,'state'|'power'>;now?:()=>number;idleTimeoutMs?:number};
const agents = new Set(['claude-code','openai-codex']);
class InputError extends Error { constructor(message:string,public status=400){super(message);} }
const reply=(value:unknown,status=200)=>Response.json(value,{status,headers:{'Cache-Control':'no-store'}});
const text=(value:unknown,max=32000)=>{if(typeof value!=='string'||!value.trim()||value.length>max)throw new InputError('Enter valid text');return value.trim();};
const object=(value:any)=>value?.result??value;

export function messageRoutes(cua:CuaTools,root:string,upgrade?:(req:Request,stream:CuaStream)=>boolean,containers?:CuaContainers,options:LifecycleOptions={}) {
 const streams=new CuaStreams(cua);
 const runtime=options.runtime??containers,now=options.now??Date.now,idleTimeoutMs=options.idleTimeoutMs??5*60_000;
 const terminal=new Set(['idle','failed','crashed']);
 const active = new Set<string>();
 const captures = new Map<string, {width:number;height:number;captureID?:string}>();
 const file=(id:string)=>{if(!/^[a-f0-9-]{36}$/.test(id))throw new InputError('Space not found',404);return join(root,id+'.json');};
 async function save(space:Space){await mkdir(root,{recursive:true,mode:0o700});const path=file(space.id),tmp=path+'.tmp';await writeFile(tmp,JSON.stringify(space),{mode:0o600});await rename(tmp,path);}
 async function load(id:string):Promise<Space>{try{return JSON.parse(await readFile(file(id),'utf8'));}catch(e){if(e instanceof InputError)throw e;throw new InputError('Space not found',404);}}
 async function records(){await mkdir(root,{recursive:true,mode:0o700});const names=(await readdir(root)).filter(n=>/^[a-f0-9-]{36}\.json$/.test(n));return Promise.all(names.map(n=>load(n.slice(0,-5))));}
 async function lock<T>(id:string,work:()=>Promise<T>){if(active.has(id))throw new InputError('An operation is already running. Refresh to check its result.',409);active.add(id);try{return await work();}finally{active.delete(id);}}
 async function body(req:Request){if(Number(req.headers.get('content-length')??0)>65536)throw new InputError('Request too large',413);const raw=await req.text();if(raw.length>65536)throw new InputError('Request too large',413);try{const b=JSON.parse(raw);if(!b||typeof b!=='object'||Array.isArray(b))throw Error();return b;}catch{throw new InputError('Expected a JSON object');}}
 const localName=(s:Space)=>s.containerName??(s.spaceID?.startsWith('local:')&&s.cuaName==='lfg-message-'+s.id?s.cuaName:undefined);
 const touch=(s:Space)=>{s.lastActivityAt=now();delete s.idleSince;};
 async function cacheEvents(s:Space,drain=false){
  let status='unknown';
  for(let page=0;page<(drain?50:1);page++){
   const before=s.eventCursor??0;
   const result=object(await cua.call('agent_events',{space:s.spaceID,run_id:s.runID,cursor:before,max:200}));
   status=result.status??'unknown';
   const cursor=result.cursor??before;
   if(!Number.isSafeInteger(cursor)||cursor<before)throw Error('Cua returned an invalid event cursor');
   const visibleKinds=new Set(['message','tool_call','error','turn_started','turn_ended']);
   const visible=(result.events??[]).filter((e:any)=>visibleKinds.has(e.kind)&&e.category!=='hidden'&&Number.isSafeInteger(e.seq)&&e.seq>before).map((e:any)=>({
    seq:e.seq+(s.eventOffset??0),kind:e.kind,ts_ms:e.ts_ms,category:e.category,
    ...(e.kind==='message'||e.kind==='error'?{text:e.text}:{}),...(e.kind==='tool_call'?{summary:e.summary??e.text}:{}),
   }));
   const known=new Set((s.events??[]).map(e=>e.seq));
   s.events=[...(s.events??[]),...visible.filter((e:AgentEvent)=>!known.has(e.seq))];s.eventCursor=cursor;
   await save(s);
   if(!drain||(result.events??[]).length<200||cursor===before)return status;
  }
  throw Error('Space history is still being saved; cleanup will continue later');
 }
 function retireRun(s:Space){
  if(s.runID){s.lastRunID=s.runID;delete s.runID;}
  s.eventOffset=Math.max((s.eventOffset??0)+(s.eventCursor??0),...(s.events??[]).map(e=>e.seq),0);s.eventCursor=0;
 }
 async function stopLocal(s:Space){
  const name=localName(s);if(!name||!runtime)throw Error('Local container runtime unavailable');
  streams.stop(s.spaceID!);await runtime.power(name,'stop');retireRun(s);s.powerState='stopped';delete s.idleSince;await save(s);
 }
 let sweeping=false;
 async function sweepIdle(){
  if(sweeping||!runtime)return;
  sweeping=true;
  try{for(const saved of await records()){
   if(active.has(saved.id)||saved.pending||!saved.spaceID||!localName(saved))continue;
   try{await lock(saved.id,async()=>{
    const s=await load(saved.id),name=localName(s);
    if(!name||s.pending||streams.hasViewers(s.spaceID!))return;
    const state=await runtime.state(name);
    if(state==='stopped'){
     if(s.powerState!=='stopped'||s.runID){if(s.runID)try{await cacheEvents(s,true);}catch{}retireRun(s);s.powerState='stopped';await save(s);}return;
    }
    if(state==='suspended'){if(s.runID)try{await cacheEvents(s,true);}catch{}await stopLocal(s);return;}
    if(state!=='running')return;
    if(s.runID){
     const result=object(await cua.call('agent_status',{space:s.spaceID,run_id:s.runID}));
     if(!terminal.has(result.status)){touch(s);await save(s);return;}
    }
    if(s.idleSince===undefined){s.idleSince=now();await save(s);return;}
    if(now()-Math.max(s.idleSince,s.lastActivityAt??0)<idleTimeoutMs)return;
    if(s.runID){
     await cacheEvents(s,true);
     const latest=object(await cua.call('agent_status',{space:s.spaceID,run_id:s.runID}));
     if(!terminal.has(latest.status)){touch(s);await save(s);return;}
    }
    if(!streams.hasViewers(s.spaceID!))await stopLocal(s);
   });}catch{
    // A gap in observation starts a fresh idle grace period after recovery.
    if(!active.has(saved.id))try{await lock(saved.id,async()=>{const latest=await load(saved.id);delete latest.idleSince;await save(latest);});}catch{}
   }
  }}finally{sweeping=false;}
 }
 let timer:ReturnType<typeof setTimeout>|undefined,closed=false;
 function startIdleCleanup(intervalMs=30_000){
  if(timer||closed)return;
  const tick=async()=>{try{await sweepIdle();}catch(error){console.warn('CUA idle cleanup failed:',error instanceof Error?error.message:String(error));}finally{if(!closed){timer=setTimeout(tick,intervalMs);timer.unref();}}};
  timer=setTimeout(tick,intervalMs);timer.unref();
 }
 function close(){closed=true;clearTimeout(timer);}
 const route=async(req:Request):Promise<Response|undefined>=>{
  const url=new URL(req.url),path=url.pathname;
  if(!path.startsWith('/api/message/'))return;
  // Same-origin browser mutations only. Native clients omit Origin.
  const origin=req.headers.get('origin');
  if((req.method!=='GET'||path.endsWith('/stream'))&&origin&&origin!==url.origin)return reply({error:'Cross-origin request refused'},403);
  try {
   if(path==='/api/message/spaces'&&req.method==='GET'){
    const saved=await records();
    const result=object(await cua.call('list_spaces',{}));
    const listed=Array.isArray(result)?result:result?.spaces??[];
    for(const s of saved){
     const live=listed.find((l:any)=>l.id===s.spaceID)??listed.find((l:any)=>l.name===s.cuaName);
     if(live){
      s.spaceID=live.id;s.powerState=localName(s)&&runtime?await runtime.state(localName(s)!):live.power_state||live.phase||'ready';
      if(!active.has(s.id))await lock(s.id,async()=>{const latest=await load(s.id);latest.spaceID=s.spaceID;latest.powerState=s.powerState;await save(latest);});
     }
     else if(s.spaceID)s.powerState='unavailable';
    }
    return reply({spaces:saved.sort((a,b)=>a.createdAt-b.createdAt)});
   }
   if(path==='/api/message/spaces'&&req.method==='POST'){
    const b=await body(req), name=text(b.name,60),agent=b.agent??(containers?'openai-codex':'claude-code');
    if(!agents.has(agent))throw new InputError('Choose Claude Code or Codex');
    const id=randomUUID();
    const space:Space={id,name,cuaName:'lfg-message-'+id,agent,powerState:'creating',messages:[],createdAt:now(),lastActivityAt:now()};
    active.add(id);
    await save(space);
    try{
     const result=containers?await containers.create(space.cuaName):object(await cua.call('create_space',{name:space.cuaName,image:'linux',on:'local',kind:'container',runtime:'runc',reuse:false}));
     const created=Array.isArray(result)?result[0]:result?.space??result;
     if(typeof created?.id!=='string')throw Error('Cua did not return a Space id. Refresh before creating another.');
     space.containerName=created.containerName;space.guestCodexAuth=created.guestCodexAuth;space.sharedPaths=created.sharedPaths;space.spaceID=created.id;space.powerState='running';await save(space);return reply({space},201);
    }catch(error){space.powerState='unknown';space.error=String(error instanceof Error?error.message:error);await save(space);throw error;}finally{active.delete(id);}
   }
   const match=path.match(/^\/api\/message\/spaces\/([^/]+)(?:\/(messages|browser|power|interrupt|stream))?$/);
   if(!match)return reply({error:'Not found'},404);
   const [,id,action]=match;const space=await load(id);
   if(req.method==='GET'&&action==='stream'){
    if(req.headers.get('upgrade')?.toLowerCase()!=='websocket'||!upgrade)throw new InputError('Expected a WebSocket upgrade',426);
    if(!space.spaceID||['stopped','suspended','unavailable'].includes(space.powerState))throw new InputError('Turn the Space on to watch it.',409);
    const stream=await lock(id,async()=>{const current=await load(id);if(['stopped','suspended','unavailable'].includes(current.powerState))throw new InputError('Turn the Space on to watch it.',409);touch(current);await save(current);return streams.prepare(current.spaceID!);});
    if(!upgrade(req,stream)){stream.close();throw new InputError('Could not open live view',400);}
    return;
   }
   if(req.method==='GET'&&!action){
    const cursor=Number(url.searchParams.get('cursor')??0);
    if(!Number.isSafeInteger(cursor)||cursor<0)throw new InputError('Invalid event cursor');
    if(!space.runID||['stopped','suspended','unavailable'].includes(space.powerState)||active.has(id))return reply({space,events:(space.events??[]).filter(e=>e.seq>cursor),cursor:Math.max(cursor,(space.eventOffset??0)+(space.eventCursor??0)),status:space.powerState});
    return await lock(id,async()=>{const current=await load(id),status=await cacheEvents(current);return reply({space:current,events:(current.events??[]).filter(e=>e.seq>cursor),cursor:Math.max(cursor,(current.eventOffset??0)+(current.eventCursor??0)),status});});
   }
   if(req.method!=='POST')return reply({error:'Method not allowed'},405);
   if(!space.spaceID)throw new InputError('Space creation is not confirmed. Refresh the list before continuing.',409);
   const b=await body(req);
   return await lock(id,async()=>{
    const current=await load(id);
    if(action==='messages'){
     if(['stopped','suspended','unavailable'].includes(current.powerState))throw new InputError('Turn the Space on before sending a message.',409);
     const prompt=text(b.text),requestID=text(b.requestID,100);
     if(current.messages.some(m=>m.id===requestID)){
      if(current.pending===requestID)throw new InputError('This message is still unconfirmed. Check the agent in Cua before sending again.',409);
      return reply({space:current});
     }
     if(current.pending)throw new InputError('The previous message is unconfirmed. Check the agent in Cua before sending again.',409);
     if(!current.runID){
      const capability=object(await cua.call('agent_capabilities',{}));
      const harness=capability.harnesses?.find((item:any)=>item.id===current.agent);
      if(harness?.auth==='missing'&&!(current.agent==='openai-codex'&&current.guestCodexAuth))throw new InputError(`${current.agent==='claude-code'?'Claude Code':'Codex'} needs authentication on this computer. Configure its provider key in Cua Spaces → Settings → Agents, then send your message again.`,503);
      // The MIT CLI can create desktops but cannot host persistent-agent homes.
      // Verify this read-only capability before recording a pending send.
      await cua.call('persistent_agent_list',{});
     }
     const context=current.lastRunID&&!current.runID?[...current.messages.map(m=>({date:m.date,text:`You: ${m.text}`})),...(current.events??[]).filter(e=>e.kind==='message').map(e=>({date:e.ts_ms??0,text:`Agent: ${e.text??''}`}))].sort((a,b)=>a.date-b.date).map(m=>m.text).join('\n').slice(-16000):'';
     current.messages.push({id:requestID,text:prompt,date:now()});current.pending=requestID;touch(current);delete current.error;await save(current);
     try{
      if(current.runID){
       const result=object(await cua.call('agent_message',{space:current.spaceID,run_id:current.runID,text:prompt,force:false}));
       if(result.delivered===false){
        current.messages=current.messages.filter(message=>message.id!==requestID);
        delete current.pending;
        throw new InputError(result.reason||'Agent did not accept the message. Wait for its current turn to finish.',409);
       }
      } else {
       const resumed=context?`The desktop was stopped to release memory. Continue using this saved conversation:\n${context}\n\nCurrent request:\n${prompt}`:prompt;
       const result=object(await cua.call('agent_start',{space:current.spaceID,agent:current.agent,prompt:current.containerName?`Tools are preinstalled: Codex, Firefox, gog, Node, Python and Git. Pro folders are mounted at ${(current.sharedPaths??[]).map(p=>p.path+(p.readOnly?' (read-only)':' (read/write)')).join(', ')||'none yet'}. Google MCP and gog require a Google account login if not configured. User request:\n${resumed}`:resumed,home:'lfg-message-'+current.id,
        label:'lfg-message-'+current.id,
        ...(current.containerName?{model:containers?.profile.codexModel}:{}),
        env_from_host:(current.agent==='claude-code'?['ANTHROPIC_API_KEY','CLAUDE_CODE_OAUTH_TOKEN','ANTHROPIC_AUTH_TOKEN']:['OPENAI_API_KEY','CODEX_API_KEY']).filter(name=>!!process.env[name]),show:false}));
       if(typeof result.run_id!=='string')throw Error('Cua did not confirm the agent run. Inspect it in Cua before retrying.');
       current.runID=result.run_id;
      }
      delete current.pending;await save(current);return reply({space:current});
     }catch(error){current.error=error instanceof Error?error.message:String(error);await save(current);throw error;}
    }
    if(action==='interrupt'){
     if(!current.runID)throw new InputError('No agent run to pause',409);
     const result=await cua.call('agent_interrupt',{space:current.spaceID,run_id:current.runID});return reply({result});
    }
    if(action==='power'){
     if(!['start','stop'].includes(b.action))throw new InputError('Choose start or stop');
     if(b.action==='stop')streams.stop(current.spaceID!);
     if(localName(current)&&runtime){
      if(b.action==='stop'){
       if(current.runID&&await runtime.state(localName(current)!)==='running'){try{await cacheEvents(current,true);}catch{/* Explicit off still stops when the guest is unreachable. */}}
       await stopLocal(current);return reply({space:current});
      }
      const stopped=await runtime.state(localName(current)!)==='stopped';
      if(stopped){if(current.runID)try{await cacheEvents(current,true);}catch{}retireRun(current);}
      if(stopped&&current.containerName&&containers)current.spaceID=await containers.resume(current.containerName);
      else await runtime.power(localName(current)!,'start');
     }
     else await cua.call(b.action==='start'?'start_space':'stop_space',{space:current.spaceID});
     current.powerState=b.action==='start'?'running':'stopped';touch(current);await save(current);return reply({space:current});
    }
    if(action==='browser'){
     if(['stopped','suspended','unavailable'].includes(current.powerState))throw new InputError('Turn the Space on before using its browser.',409);
     touch(current);await save(current);
     const driver = async(tool:string,args:Record<string,unknown>)=>cua.call('call_tool',{space:current.spaceID,service:'driver',tool,arguments:{session:'lfg-message-'+id,...args}});
     if(b.action==='screenshot'){
      const result=object(await driver('get_desktop_state',{}));
      const image=result.content?.find((part:any)=>part.type==='image');
      if(!image?.data)throw Error('Cua returned no desktop image');
      captures.set(id,{width:result.screenshot_width??result.screen_width,height:result.screenshot_height??result.screen_height,captureID:result.capture_id});
      return reply({imageBase64:image.data,mimeType:image.mimeType??'image/png'});
     }
     if(!['navigate','click','rightClick','move','drag','type','key','scroll','takeControl'].includes(b.action))throw new InputError('Unknown browser action');
     if(b.action==='takeControl'){
      if(current.runID){
       const state=object(await cua.call('agent_status',{space:current.spaceID,run_id:current.runID}));
       if(!['idle','failed','crashed'].includes(state.status))await cua.call('agent_interrupt',{space:current.spaceID,run_id:current.runID});
       let stopped=false;
       for(let attempt=0;attempt<120;attempt++){
        const result=object(await cua.call('agent_status',{space:current.spaceID,run_id:current.runID}));
        if(['idle','failed','crashed'].includes(result.status)){stopped=true;break;}
        await Bun.sleep(250);
       }
       if(!stopped)throw new InputError('The agent is still stopping. Wait, then take control again.',409);
      }
      return reply({text:'You have control. Send a message in Chat when you want the agent to continue.'});
     }
     if(current.runID){
      const state=object(await cua.call('agent_status',{space:current.spaceID,run_id:current.runID}));
      if(!['idle','failed','crashed'].includes(state.status))throw new InputError('Pause the agent and wait for it to stop before controlling its browser.',409);
     }
     if(b.action==='navigate'){
      let target:URL;try{target=new URL(text(b.url,4096));}catch{throw new InputError('Enter a complete website URL');}
      if(!['http:','https:'].includes(target.protocol))throw new InputError('Use an http or https URL');
      const escaped="'"+target.href.replaceAll("'","'\\''")+"'";
      const result=await cua.call('space_bash',{space:current.spaceID,command:`xdg-open ${escaped}`,timeout:15});
      if(/\[exit [1-9][0-9]*\]/.test(result.text??''))throw Error(result.text);
      return reply({text:'Website opened'});
     }
     const args:Record<string,unknown>={target:{kind:'desktop',display_id:'primary'},delivery_mode:'foreground'};
     let tool:string;
     if(['click','rightClick','move','drag'].includes(b.action)){
      // Capture immediately before clicking to bind coordinates to fresh geometry.
      if(b.live==='true'||(b.action==='move'&&!captures.has(id))){const frame=object(await driver('get_desktop_state',{}));captures.set(id,{width:frame.screenshot_width??frame.screen_width,height:frame.screenshot_height??frame.screen_height,captureID:frame.capture_id});}
      const capture=captures.get(id);if(!capture)throw new InputError('Refresh the desktop image before clicking',409);
      const x=Number(b.x),y=Number(b.y);if(!Number.isFinite(x)||!Number.isFinite(y)||x<0||x>1||y<0||y>1)throw new InputError('Invalid click coordinates');
      args.x=Math.round(x*(capture.width-1));args.y=Math.round(y*(capture.height-1));
      if(capture.captureID)args.capture_id=capture.captureID;
      if(b.action==='rightClick')args.button='right';
      tool=b.action==='move'?'move_cursor':b.action==='drag'?'drag':'click';
      if(b.action==='move'){delete args.delivery_mode;delete args.capture_id;delete args.target;args.scope='desktop';}
      if(b.action==='drag'){
       const fromX=Number(b.fromX),fromY=Number(b.fromY);
       if(!Number.isFinite(fromX)||!Number.isFinite(fromY)||fromX<0||fromX>1||fromY<0||fromY>1)throw new InputError('Invalid drag coordinates');
       args.from_x=Math.round(fromX*(capture.width-1));args.from_y=Math.round(fromY*(capture.height-1));
       args.to_x=args.x;args.to_y=args.y;delete args.x;delete args.y;delete args.capture_id;delete args.target;args.scope='desktop';args.duration_ms=200;
      }
     }else if(b.action==='scroll'){
      const direction=text(b.direction,10);if(!['up','down'].includes(direction))throw new InputError('Unsupported scroll direction');
      tool='scroll';args.direction=direction;args.amount=3;
     }else if(b.action==='type'){tool='type_text';if(typeof b.text!=='string'||b.text.length===0||b.text.length>8000)throw new InputError('Enter text up to 8000 characters');args.text=b.text;}
     else{tool='press_key';const key=text(b.key,80).toLowerCase();
      const parts=key.split('+');const last=parts.pop()!;
      if(!/^[a-z0-9]$/.test(last)&&!['enter','tab','escape','backspace','delete','home','end','space','pageup','pagedown','up','down','left','right'].includes(last)&&!/^f([1-9]|1[0-2])$/.test(last))throw new InputError('Unsupported key');
      if(parts.length>3||parts.some(p=>!['ctrl','alt','shift','super'].includes(p))||new Set(parts).size!==parts.length)throw new InputError('Unsupported modifiers');
      if(parts.length){tool='hotkey';args.keys=[...parts,last];}else args.key=last;}
     await driver(tool,args);return reply({text:'Browser input sent'});
    }
    return reply({error:'Not found'},404);
   });
  }catch(error){return reply({error:error instanceof Error?error.message:String(error)},error instanceof InputError?error.status:502);}
 };
 return Object.assign(route,{sweepIdle,startIdleCleanup,close});
}
