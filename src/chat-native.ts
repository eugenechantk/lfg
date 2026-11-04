import {mkdir,readFile,writeFile,rename,unlink,rm} from 'node:fs/promises';
import {join} from 'node:path';
import {homedir} from 'node:os';
import {randomUUID} from 'node:crypto';
import type {ChatRunner,ChatRunInput,NativeChatContext} from './chat-sessions';
import {ChatClaudeOutput,registerChatRuntimePid,unregisterChatRuntimePid} from './chat-claude';

export function nativeClaudeArgs(systemFile:string,context:NativeChatContext,model?:string){
 // Match managed coding sessions. Keep Claude's coding prompt, skills and
 // host configuration; append the chat's instructions instead of replacing it.
 return ['-p','--dangerously-skip-permissions','--permission-prompts','none','--tools','default',
  '--input-format','stream-json','--output-format','stream-json',
  '--verbose','--include-partial-messages','--append-system-prompt-file',systemFile,'--system-prompt-snapshot','off',
  context.resume?'--resume':'--session-id',context.providerSessionID,...(model?['--model',model]:[]),...(context.jobMcpURL?['--mcp-config',join(context.directory,'job-tools.json')]:[])];
}
export function nativeClaudeEnvironment(source:NodeJS.ProcessEnv=process.env){
 // MCP configurations may reference arbitrary host environment variables.
 const env:Record<string,string|undefined>={...source,DO_NOT_TRACK:'1',CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:'1'};
 // A coding host may itself be launched from Claude. This is a separately
 // owned conversation, not a recursive invocation of that parent session.
 delete env.CLAUDECODE;
 return env;
}
function killWorker(pid:number){
 // Workers own a process group, including ordinary shell and MCP children.
 // Only call this for a worker launched here, or a verified recovery lease.
 try{process.kill(-pid,'SIGKILL');}catch(error:any){if(error.code!=='ESRCH')throw error;}
}
/** Remove only this provider identity, never a whole shared Claude project. */
export async function purgeChatProviderHistory(directory:string,providerID:string,
 projects=process.env.LFG_CLAUDE_PROJECTS_DIR??join(process.env.CLAUDE_CONFIG_DIR??join(process.env.HOME??homedir(),'.claude'),'projects')){
 if(!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(providerID))throw Error('Invalid provider conversation identity; provider files were preserved.');
 for(const encoded of new Set([directory.replace(/\//g,'-'),directory.replace(/[/.]/g,'-')])){
  await rm(join(projects,encoded,providerID+'.jsonl'),{force:true});
  await rm(join(projects,encoded,providerID),{recursive:true,force:true});
 }
}
function liveWorkerGroup(pid:number){
 try{process.kill(-pid,0);}catch(error:any){if(error.code==='ESRCH')return false;if(error.code!=='EPERM')throw error;}
 const check=Bun.spawnSync(['/bin/ps','-axo','pgid=,state=']);
 if(check.exitCode!==0)throw Error('A saved chat worker process group could not be inspected.');
 return new TextDecoder().decode(check.stdout).split('\n').some(line=>{
  const [group,state]=line.trim().split(/\s+/);return Number(group)===pid&&!!state&&!state.startsWith('Z');
 });
}
type Pending={input:ChatRunInput;parser:ChatClaudeOutput;resolve:(value:string)=>void;reject:(error:Error)=>void};

class ClaudeConversationWorker {
 private proc:ReturnType<typeof Bun.spawn>;
 private pending?:Pending;
 private initialized=false;
 private closed=false;
 private killed=false;
 private stderr='';
 private lastInput?:ChatRunInput;
 private childOwners=new Map<string,ChatRunInput>();
 private taskOwners=new Map<string,ChatRunInput>();
 private backgroundActive=false;
 private idleTimer?:ReturnType<typeof setTimeout>;
 readonly exited:Promise<void>;
 private constructor(readonly context:NativeChatContext,readonly signature:string,executable:string,private idleMs:number,systemFile:string){
  this.proc=Bun.spawn([executable,...nativeClaudeArgs(systemFile,context,JSON.parse(signature).model)],{cwd:context.directory,env:nativeClaudeEnvironment(),detached:true,stdin:'pipe',stdout:'pipe',stderr:'pipe'});
  registerChatRuntimePid(this.proc.pid);
  this.exited=Promise.resolve();
 }
 static async start(input:ChatRunInput,executable:string,idleMs:number){
  const context=input.native!;await mkdir(context.directory,{recursive:true,mode:0o700});
  const systemFile=join(context.directory,'instructions.txt');await writeFile(systemFile,input.system,{mode:0o600});
  if(context.jobMcpURL)await writeFile(join(context.directory,'job-tools.json'),JSON.stringify({mcpServers:{'lfg-durable-jobs':{type:'http',url:context.jobMcpURL}}}),{mode:0o600});
  const worker=new ClaudeConversationWorker(context,JSON.stringify({system:input.system,model:input.model,jobMcpURL:context.jobMcpURL}),executable,idleMs,systemFile);
  try{
   const lease=join(context.directory,'worker.json'),tmp=lease+'.'+randomUUID()+'.tmp';
   await writeFile(tmp,JSON.stringify({pid:worker.proc.pid,processGroup:true,sessionID:context.providerSessionID,systemFile}),{mode:0o600});await rename(tmp,lease);
   (worker as {exited:Promise<void>}).exited=worker.read();
   return worker;
  }catch(error){killWorker(worker.proc.pid);worker.proc.kill('SIGKILL');await worker.proc.exited;unregisterChatRuntimePid(worker.proc.pid);throw error;}
 }
 get alive(){return !this.closed&&this.proc.exitCode===null;}
 private async read(){
  const errors=(async()=>{for await(const chunk of this.proc.stderr as any)this.stderr=(this.stderr+new TextDecoder().decode(chunk)).slice(-4000);})();
  let buffer='';const decoder=new TextDecoder();
  try{
   for await(const chunk of this.proc.stdout as any){
    buffer+=decoder.decode(chunk,{stream:true});if(buffer.length>4*1024*1024)throw Error('The provider returned an oversized event.');
    let end:number;while((end=buffer.indexOf('\n'))>=0){const line=buffer.slice(0,end);buffer=buffer.slice(end+1);if(line.trim())await this.event(JSON.parse(line));}
   }
   if(buffer.trim())await this.event(JSON.parse(buffer));
   await this.proc.exited;await errors;
   if(this.pending)throw Error(this.stderr.trim().slice(-1000)||'The provider stopped before completing this reply. Your conversation is saved.');
  }catch(error){this.fail(error instanceof Error?error:Error(String(error)));}
  finally{
   this.closed=true;clearTimeout(this.idleTimer);this.terminate();await this.proc.exited;await errors;
   unregisterChatRuntimePid(this.proc.pid);
   for(const input of new Set([...this.childOwners.values(),...(this.lastInput?[this.lastInput]:[])])){
    try{await input.onWorkerStopped?.();}catch{console.warn('Chat child status could not be saved.');}
   }
   const lease=join(this.context.directory,'worker.json');
   try{const saved=JSON.parse(await readFile(lease,'utf8'));if(saved.pid===this.proc.pid)await unlink(lease);}catch(error:any){if(error.code!=='ENOENT')console.warn('Chat worker lease cleanup failed.');}
  }
 }
 private async event(event:any){
  const pending=this.pending;
  if(!event.parent_tool_use_id&&event.session_id&&event.session_id!==this.context.providerSessionID)throw Error('The provider returned a different conversation.');
  const owner=event.parent_tool_use_id??event.tool_use_id;
  const input=(owner?this.childOwners.get(owner):undefined)??this.taskOwners.get(event.task_id)??pending?.input??this.lastInput;
  if(event.type==='system'&&event.subtype==='task_started'&&event.task_id&&input)this.taskOwners.set(event.task_id,input);
  if(event.type==='assistant'&&!event.parent_tool_use_id)for(const block of event.message?.content??[]){
   if(block.type==='tool_use'&&block.name==='Agent'&&typeof block.id==='string'&&input)this.childOwners.set(block.id,input);
  }
  await input?.onEvent?.(event);
  if(event.parent_tool_use_id)return;
  if(!pending){
   if(!input&&(event.type==='result'||event.type==='assistant'||event.type==='stream_event'))throw Error('Unexpected provider output without an active chat turn.');
   if(event.type==='assistant'||event.type==='stream_event')this.backgroundActive=true;
   if(event.type==='result'){this.backgroundActive=false;this.scheduleIdle();}
   return;
  }
  if(event.type==='system'&&event.subtype==='init'){
   if(event.session_id!==this.context.providerSessionID)throw Error('The provider opened a different conversation.');
   pending.parser.accept(event);this.initialized=true;await pending.input.native!.onReady();return;
  }
  if(event.session_id&&event.session_id!==this.context.providerSessionID)throw Error('The provider returned a different conversation.');
  const text=pending.parser.accept(event);if(text)await pending.input.onText(text);
  if(event.type==='result'){
   const result=pending.parser.result!;this.pending=undefined;pending.resolve(result);
   this.scheduleIdle();
  }
 }
 private scheduleIdle(){
  clearTimeout(this.idleTimer);
  this.idleTimer=setTimeout(()=>{
   if(this.pending||this.backgroundActive||[...new Set([...this.childOwners.values(),...(this.lastInput?[this.lastInput]:[])])].some(i=>i.hasRunningChildren?.()))this.scheduleIdle();
   else void this.shutdown();
  },this.idleMs);this.idleTimer.unref();
 }
 private terminate(){if(this.killed)return;killWorker(this.proc.pid);this.killed=true;this.proc.kill('SIGKILL');}
 private fail(error:Error){const pending=this.pending;this.pending=undefined;this.closed=true;clearTimeout(this.idleTimer);pending?.reject(error);this.terminate();}
 async send(input:ChatRunInput){
  if(!this.alive)throw Error('The conversation worker stopped. Send a new message to resume.');
  if(this.pending)throw Error('A turn is already running.');
  if(input.signal.aborted)throw Error('Stopped');
  clearTimeout(this.idleTimer);
  const parser=new ChatClaudeOutput('coding');parser.initialized=this.initialized;
  this.lastInput=input;
  const result=new Promise<string>((resolve,reject)=>{this.pending={input,parser,resolve,reject};});
  const abort=()=>this.fail(Error('You stopped this reply.'));
  input.signal.addEventListener('abort',abort,{once:true});
  const timeout=setTimeout(()=>this.fail(Error('The provider timed out. Your conversation is saved.')),1800000);timeout.unref();
  try{
   (this.proc.stdin as any).write(JSON.stringify({type:'user',message:{role:'user',content:input.prompt},session_id:this.context.providerSessionID,parent_tool_use_id:null,uuid:randomUUID()})+'\n');
   return await result;
  }catch(error){this.fail(error instanceof Error?error:Error(String(error)));throw error;}
  finally{clearTimeout(timeout);input.signal.removeEventListener('abort',abort);}
 }
 async shutdown(){this.fail(Error('The conversation worker stopped.'));await this.exited;}
}

/** A saved provider conversation with an optional warm worker. No terminal or Space. */
export class NativeClaudeRunner implements ChatRunner {
 readonly nativeConversations=true;
 private workers=new Map<string,ClaudeConversationWorker>();
 constructor(private executable=process.env.LFG_CLAUDE_BIN??Bun.which('claude')??'claude',private idleMs=180000){}
 async run(input:ChatRunInput){
  if(!input.native||input.purpose!=='reply')throw Error('Native chat requires a conversation binding.');
  const key=input.native.id,signature=JSON.stringify({system:input.system,model:input.model,jobMcpURL:input.native.jobMcpURL});
  let worker=this.workers.get(key);
  if(worker&&(!worker.alive||worker.signature!==signature)){await worker.shutdown();this.workers.delete(key);worker=undefined;}
  if(!worker){worker=await ClaudeConversationWorker.start(input,this.executable,this.idleMs);this.workers.set(key,worker);}
  try{return await worker.send(input);}catch(error){await worker.shutdown();this.workers.delete(key);throw error;}
 }
 async recover(directory:string,providerSessionID:string){
  const lease=join(directory,'worker.json');let saved:any;
  try{saved=JSON.parse(await readFile(lease,'utf8'));}catch(error:any){if(error.code==='ENOENT')return;throw error;}
  if(saved.sessionID!==providerSessionID||!Number.isSafeInteger(saved.pid)||saved.pid<=1)throw Error('Chat worker recovery found an invalid ownership record.');
  let terminatedGroup=false;
  try{
   process.kill(saved.pid,0);
   const check=Bun.spawnSync(['/bin/ps','-ww','-p',String(saved.pid),'-o','state=','-o','command=']);const command=new TextDecoder().decode(check.stdout).trim();
   if(check.exitCode!==0||!command){
    // ps can lose a race with exit, but a failed inspection is not proof
    // that a worker is gone. ESRCH below is the only such proof.
    process.kill(saved.pid,0);
    throw Error('A saved chat worker is still alive but its identity could not be verified.');
   }
   // kill(pid, 0) also succeeds for an exited, unreaped child. It cannot
   // consume another turn and no longer has argv to validate.
   if(command&&!command.startsWith('Z')){
    if(!command.includes(providerSessionID)||!command.includes(join(directory,'instructions.txt'))){
     // An orphan may exit while ps is reading its argv. Only ESRCH permits
     // cleanup; a still-live process with unknown identity remains protected.
     process.kill(saved.pid,0);
     throw Error('A saved chat worker is still alive but its identity could not be verified.');
    }
    if(saved.processGroup===true){
     const group=Bun.spawnSync(['/bin/ps','-p',String(saved.pid),'-o','pgid=']);
     if(group.exitCode!==0||Number(new TextDecoder().decode(group.stdout).trim())!==saved.pid)throw Error('A saved chat worker process group could not be verified.');
     killWorker(saved.pid);terminatedGroup=true;
    }else process.kill(saved.pid,'SIGKILL');
   }
  }catch(error:any){if(error.code!=='ESRCH')throw error;}
  if(saved.processGroup===true){
   // ESRCH for the leader is not proof that its shell/MCP children exited.
   // A vanished or zombie leader no longer proves group ownership, so keep
   // the lease and refuse a new writer while any live group member remains.
   // Never kill an unverified group: its numeric id may have been reused.
   if(terminatedGroup)for(let n=0;n<50&&liveWorkerGroup(saved.pid);n++)await Bun.sleep(20);
   if(liveWorkerGroup(saved.pid))throw Error('A saved chat tool process group is still alive. Its owner could not be verified; recovery is blocked to prevent overlapping actions.');
  }
  await unlink(lease).catch((error:any)=>{if(error.code!=='ENOENT')throw error;});
 }
 async close(){await Promise.all([...this.workers.values()].map(w=>w.shutdown()));this.workers.clear();}
 async interrupt(id:string){const worker=this.workers.get(id);if(worker){await worker.shutdown();this.workers.delete(id);}}
 async purge(id:string,directory:string,providerSessionID?:string){
  await this.interrupt(id);
  if(providerSessionID){await this.recover(directory,providerSessionID);await purgeChatProviderHistory(directory,providerSessionID);}
 }
}
