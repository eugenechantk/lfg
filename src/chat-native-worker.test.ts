import {test,expect} from 'bun:test';
import {mkdtemp,readFile,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {NativeClaudeRunner} from './chat-native';
import {ChatSessions} from './chat-sessions';
import {isChatRuntimePid,isChatProviderSession} from './chat-claude';

async function fixture(idleMs=10000){
 const root=await mkdtemp(join(tmpdir(),'chat-worker-')),executable=join(root,'fake-claude');
 await writeFile(executable,`#!${process.execPath}
import {appendFileSync,readFileSync,writeFileSync} from 'node:fs';
appendFileSync('launches.jsonl',JSON.stringify(process.argv.slice(2))+'\\n');
let buffer='';for await(const chunk of Bun.stdin.stream()){buffer+=new TextDecoder().decode(chunk);let end;while((end=buffer.indexOf('\\n'))>=0){let line=buffer.slice(0,end);buffer=buffer.slice(end+1);if(!line.trim())continue;
const message=JSON.parse(line),p=JSON.parse(message.message.content),sid=message.session_id;
const emit=e=>console.log(JSON.stringify({...e,session_id:sid}));
emit({type:'system',subtype:'init',tools:['Read','Write','Edit','Bash','Skill','mcp__probe__echo'],mcp_servers:[{name:'probe',status:'connected'}]});
if(p.currentMessage==='tool'){
 for(const name of ['Read','Bash','Skill','mcp__probe__echo']){
  emit({type:'stream_event',event:{type:'content_block_start',content_block:{type:'tool_use',id:name,name}}});
  emit({type:'assistant',message:{content:[{type:'tool_use',id:name,name,input:{secret:'TOOL_INPUT'}}]}});
  emit({type:'user',message:{content:[{type:'tool_result',tool_use_id:name,content:'TOOL_RESULT'}]}});
 }
 emit({type:'stream_event',parent_tool_use_id:'agent',event:{type:'content_block_delta',delta:{type:'text_delta',text:'SUBAGENT_TEXT'}}});
 emit({type:'result',parent_tool_use_id:'agent',subtype:'success',result:'SUBAGENT_RESULT'});
 appendFileSync('actions.txt','one action\\n');
 emit({type:'stream_event',event:{type:'content_block_delta',delta:{type:'text_delta',text:'Tools completed'}}});
 emit({type:'result',subtype:'success',result:'Tools completed'});continue;
}
if(p.currentMessage==='tool-wait'){
 const child=Bun.spawn([process.execPath,'-e',"setTimeout(()=>{},60000)"],{stdin:'ignore',stdout:'ignore',stderr:'ignore'});
 writeFileSync('tool-child.pid',String(child.pid));
 emit({type:'stream_event',event:{type:'content_block_delta',delta:{type:'text_delta',text:'Tool running'}}});continue;
}
if(p.currentMessage==='partial'){emit({type:'stream_event',event:{type:'content_block_delta',delta:{type:'text_delta',text:'Partial reply'}}});continue;}
let state={};try{state=JSON.parse(readFileSync('native-state.json','utf8'));}catch{}
if(p.currentMessage.startsWith('Remember'))state.fact=p.currentMessage;
writeFileSync('native-state.json',JSON.stringify(state));
const text=JSON.stringify({fact:state.fact,memory:p.privateMemory,system:readFileSync('instructions.txt','utf8'),imported:p.importedHistory?.length??0});
emit({type:'stream_event',event:{type:'content_block_delta',delta:{type:'text_delta',text}}});emit({type:'result',subtype:'success',result:text});
}}
`,{mode:0o700});
 const runner=new NativeClaudeRunner(executable,idleMs),chats=new ChatSessions(join(root,'store'),runner);await chats.ready;
 return {root,executable,runner,chats,close:async()=>{await chats.close();await rm(root,{recursive:true,force:true});}};
}
async function send(chats:ChatSessions,id:string,text:string,requestID=text){await chats.send(id,{text,requestID});await chats.settled(id);return await chats.detail(id);}

test('warm native worker handles successive turns; edited instructions restart and resume the same conversation',async()=>{
 const f=await fixture();try{
  const s=await f.chats.create({name:'Scout',instructions:'Before',memory:'Pip'});
  await send(f.chats,s.id,'Remember willow');
  const directory=join(f.root,'store',s.id,'provider'),first=JSON.parse(await readFile(join(directory,'worker.json'),'utf8'));
  expect(isChatRuntimePid(first.pid)).toBe(true);expect(isChatProviderSession(first.sessionID)).toBe(true);
  let d=await send(f.chats,s.id,'Recall');expect(d.session.state).toBe('idle');expect(d.messages.at(-1)!.text).toContain('Remember willow');
  const second=JSON.parse(await readFile(join(directory,'worker.json'),'utf8'));expect(second.pid).toBe(first.pid);
  await f.chats.update(s.id,{revision:s.revision,instructions:'After',memory:'Miso'});d=await send(f.chats,s.id,'Updated recall');
  expect(d.session.providerSessionID).toBe(first.sessionID);expect(d.session.providerRevision).toBe(2);
  expect(d.messages.at(-1)!.text).toContain('Miso');expect(d.messages.at(-1)!.text).toContain('After');
  const launches=(await readFile(join(directory,'launches.jsonl'),'utf8')).trim().split('\n').map(line=>JSON.parse(line));
  expect(launches).toHaveLength(2);expect(launches[0]).toContain('--session-id');expect(launches[1]).toContain('--resume');
  expect(launches[0]).not.toContain('--no-session-persistence');expect(launches[1]).toContain('--system-prompt-snapshot');
  expect(launches[1].join(' ')).not.toContain('Miso');expect(launches[1].join(' ')).not.toContain('After');
 }finally{await f.close();}
});

test('idle shutdown preserves native identity and the next message resumes saved context',async()=>{
 const f=await fixture(20);try{
  const s=await f.chats.create({name:'Scout'});let d=await send(f.chats,s.id,'Remember birch');const id=d.session.providerSessionID;
  await Bun.sleep(100);d=await send(f.chats,s.id,'Recall');expect(d.session.providerSessionID).toBe(id!);expect(d.messages.at(-1)!.text).toContain('Remember birch');
 }finally{await f.close();}
});

test('stop keeps partial text, rejects duplicate replay, and resumes on a new request',async()=>{
 const f=await fixture();try{
  const s=await f.chats.create({name:'Scout'});await f.chats.send(s.id,{requestID:'one',text:'partial'});
  for(let n=0;n<100&&(await f.chats.detail(s.id)).messages.length<2;n++)await Bun.sleep(10);
  await f.chats.interrupt(s.id);await f.chats.settled(s.id);
  const stopped=await f.chats.detail(s.id);expect(stopped.messages.at(-1)!.text).toBe('Partial reply');expect(stopped.turns[0]!.state).toBe('interrupted');
  expect((await f.chats.send(s.id,{requestID:'one',text:'partial'})).duplicate).toBe(true);
  const next=await send(f.chats,s.id,'Continue');expect(next.session.state).toBe('idle');expect(next.session.providerSessionID).toBe(stopped.session.providerSessionID!);
 }finally{await f.close();}
});

test('tool, MCP and skill cycles complete without leaking payloads or replaying actions after resume',async()=>{
 const f=await fixture();try{
  const s=await f.chats.create({name:'Scout'});const d=await send(f.chats,s.id,'tool');
  expect(d.session.state).toBe('idle');expect(d.messages.map(m=>m.text)).toEqual(['tool','Tools completed']);
  await f.chats.send(s.id,{text:'tool',requestID:'tool'});await f.chats.settled(s.id);
  const directory=join(f.root,'store',s.id,'provider');
  expect(await readFile(join(directory,'actions.txt'),'utf8')).toBe('one action\n');
  await f.chats.update(s.id,{revision:s.revision,instructions:'Updated instructions',memory:'Miso'});
  const resumed=await send(f.chats,s.id,'tool','second-tool');
  expect(resumed.session.state).toBe('idle');expect(resumed.session.providerSessionID).toBe(d.session.providerSessionID!);
  expect(await readFile(join(directory,'actions.txt'),'utf8')).toBe('one action\none action\n');
 }finally{await f.close();}
});

test('stop terminates the owned worker process group including an active tool child',async()=>{
 const f=await fixture();let childPID:number|undefined;
 try{
  const s=await f.chats.create({name:'Scout'});await f.chats.send(s.id,{text:'tool-wait',requestID:'tool-wait'});
  const pidPath=join(f.root,'store',s.id,'provider','tool-child.pid');
  for(let n=0;n<100;n++){try{childPID=Number(await readFile(pidPath,'utf8'));break;}catch{await Bun.sleep(10);}}
  expect(childPID).toBeGreaterThan(1);process.kill(childPID!,0);
  await f.chats.interrupt(s.id);await f.chats.settled(s.id);
  const d=await f.chats.detail(s.id);expect(d.turns[0]!.state).toBe('interrupted');
  const inspect=Bun.spawnSync(['/bin/ps','-p',String(childPID),'-o','state=']);
  const state=new TextDecoder().decode(inspect.stdout).trim();
  expect(state===''||state.startsWith('Z')).toBe(true);
  expect((await f.chats.send(s.id,{text:'tool-wait',requestID:'tool-wait'})).duplicate).toBe(true);
 }finally{if(childPID){try{process.kill(childPID,'SIGKILL');}catch{}}await f.close();}
});

test('recovery preserves the lease and blocks resume when the worker leader vanished before a tool child',async()=>{
 const root=await mkdtemp(join(tmpdir(),'chat-orphan-group-')),sid=crypto.randomUUID();
 const script=join(root,'leader.ts');let leader:ReturnType<typeof Bun.spawn>|undefined;
 const runner=new NativeClaudeRunner();
 try{
  await writeFile(script,`import {writeFileSync} from 'node:fs';\nconst child=Bun.spawn([process.execPath,'-e','setTimeout(()=>{},60000)'],{stdin:'ignore',stdout:'ignore',stderr:'ignore'});\nwriteFileSync(${JSON.stringify(join(root,'child.pid'))},String(child.pid));process.exit(0);`);
  leader=Bun.spawn([process.execPath,script],{detached:true,stdin:'ignore',stdout:'ignore',stderr:'ignore'});await leader.exited;
  const childPID=Number(await readFile(join(root,'child.pid'),'utf8'));process.kill(childPID,0);
  const lease=JSON.stringify({pid:leader.pid,processGroup:true,sessionID:sid,systemFile:join(root,'instructions.txt')});
  await writeFile(join(root,'worker.json'),lease);
  await expect(runner.recover(root,sid)).rejects.toThrow('prevent overlapping actions');
  expect(await readFile(join(root,'worker.json'),'utf8')).toBe(lease);process.kill(childPID,0);
  process.kill(-leader.pid,'SIGKILL');
  await runner.recover(root,sid);
  await expect(readFile(join(root,'worker.json'),'utf8')).rejects.toThrow('ENOENT');
 }finally{if(leader){try{process.kill(-leader.pid,'SIGKILL');}catch{}}await runner.close();await rm(root,{recursive:true,force:true});}
});

test('host crash retires only its verified orphan worker and never replays the interrupted turn',async()=>{
 const f=await fixture();let child:ReturnType<typeof Bun.spawn>|undefined;let recovered:ChatSessions|undefined;
 try{
  await f.chats.close();const script=join(f.root,'host.ts');
  await writeFile(script,`import {ChatSessions} from ${JSON.stringify(join(import.meta.dir,'chat-sessions.ts'))};
import {NativeClaudeRunner} from ${JSON.stringify(join(import.meta.dir,'chat-native.ts'))};
const chats=new ChatSessions(${JSON.stringify(join(f.root,'store'))},new NativeClaudeRunner(${JSON.stringify(f.executable)}));
const s=await chats.create({name:'Crash probe'});
await chats.send(s.id,{requestID:'saved',text:'Remember cedar'});await chats.settled(s.id);
await chats.send(s.id,{requestID:'interrupted',text:'partial'});
while((await chats.detail(s.id)).messages.length<4)await Bun.sleep(10);
console.log(JSON.stringify({id:s.id}));setInterval(()=>{},1000);
`);
  child=Bun.spawn([process.execPath,script],{stdin:'ignore',stdout:'pipe',stderr:'pipe'});
  const reader=(child.stdout as ReadableStream<Uint8Array>).getReader();
  const first=await Promise.race([reader.read(),Bun.sleep(4000).then(()=>{throw Error('Crash fixture did not start');})]);
  const {id}=JSON.parse(new TextDecoder().decode(first.value));child.kill('SIGKILL');await child.exited;
  recovered=new ChatSessions(join(f.root,'store'),new NativeClaudeRunner(f.executable));await recovered.ready;
  const restored=await recovered.detail(id);expect(restored.session.state).toBe('idle');expect(restored.turns.at(-1)!.state).toBe('interrupted');
  expect(restored.messages.at(-1)!.text).toBe('Partial reply');
  expect((await recovered.send(id,{requestID:'interrupted',text:'partial'})).duplicate).toBe(true);
  const next=await send(recovered,id,'Recall after crash');expect(next.messages.at(-1)!.text).toContain('Remember cedar');
  expect(next.session.providerSessionID).toBe(restored.session.providerSessionID!);
 }finally{child?.kill('SIGKILL');await recovered?.close();await f.close();}
});
