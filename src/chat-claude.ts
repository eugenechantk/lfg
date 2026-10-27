import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { ChatRunner, ChatRunInput } from './chat-sessions';

const runtimePids = new Set<number>();
const providerSessions = new Set<string>();
export const isChatRuntimePid = (pid:number) => runtimePids.has(pid);
export const registerChatRuntimePid = (pid:number) => runtimePids.add(pid);
export const unregisterChatRuntimePid = (pid:number) => runtimePids.delete(pid);
export const registerChatProviderSession = (id:string) => providerSessions.add(id);
export const isChatProviderSession = (id:string) => providerSessions.has(id);
/** Recognize our private worker directory in real paths, argv, or Claude's encoded project name. */
export const isChatProviderDirectory = (path:string) => /[\/-]chat-sessions[\/-]chat-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}[\/-]provider(?:$|[\/\s"'])/i.test(path);
export const isChatProviderCommand = (command:string) => /--(?:append-)?system-prompt-file(?:\s|=)/.test(command) && command.includes('--input-format') && isChatProviderDirectory(command);

/** Share text decoding while keeping the legacy text-only policy explicit. */
export class ChatClaudeOutput {
  constructor(private capabilities:'text-only'|'coding'='text-only'){}
  initialized=false;
  result?:string;
  text='';
  accept(event:any):string|undefined {
    // Subagents have their own text and results. Only the main conversation
    // can append user-visible prose or complete the active chat turn.
    if(event.parent_tool_use_id)return;
    if(event.type==='system'&&event.subtype==='init'){
      if(!Array.isArray(event.tools))throw Error('Chat received invalid provider initialization.');
      if(this.capabilities==='text-only'){
        if(event.tools.length)throw Error('Chat requires a provider with all tools disabled.');
        if(event.mcp_servers?.length)throw Error('Chat cannot connect to MCP servers.');
      }
      this.initialized=true;
    }
    const content=event.type==='assistant'?event.message?.content:undefined;
    if(this.capabilities==='text-only'&&content?.some((b:any)=>b.type==='tool_use'||b.type==='server_tool_use'))throw Error('The provider attempted a tool call in text-only chat.');
    if(event.type==='stream_event'){
      const e=event.event;
      if(this.capabilities==='text-only'&&(e?.content_block?.type==='tool_use'||e?.content_block?.type==='server_tool_use'))throw Error('The provider attempted a tool call in text-only chat.');
      if(e?.type==='content_block_delta'&&e.delta?.type==='text_delta'){
        if(!this.initialized)throw Error('Chat received text before confirming provider initialization.');
        const delta=typeof e.delta.text==='string'?e.delta.text:'';
        this.text+=delta;if(this.text.length>128000)throw Error('The reply exceeded the chat size limit.');return delta;
      }
    }
    if(event.type==='result'){
      if(event.is_error||event.subtype!=='success')throw Error(typeof event.result==='string'?event.result.slice(0,1000):(event.errors??['The provider could not complete this reply.']).join(' ').slice(0,1000));
      if(!this.initialized)throw Error('Chat could not confirm provider initialization.');
      this.result=typeof event.result==='string'?event.result:this.text;
      if(this.result!.length>128000)throw Error('The reply exceeded the chat size limit.');
    }
  }
}

export function chatClaudeArgs(systemFile:string,model?:string){
  return ['-p','--safe-mode','--tools','','--strict-mcp-config','--mcp-config','{"mcpServers":{}}','--setting-sources','','--no-session-persistence','--no-chrome','--output-format','stream-json','--verbose','--include-partial-messages','--system-prompt-file',systemFile,...(model?['--model',model]:[])];
}

export class TextOnlyClaudeRunner implements ChatRunner {
  constructor(private executable=process.env.LFG_CLAUDE_BIN??Bun.which('claude')??'claude',private timeoutMs=300000){}
  async run(input:ChatRunInput):Promise<string>{
    if(input.signal.aborted)throw Error('Stopped');
    const dir=await mkdtemp(join(tmpdir(),'lfg-private-chat-'));
    let proc:ReturnType<typeof Bun.spawn>|undefined,timedOut=false;
    let timer:ReturnType<typeof setTimeout>|undefined;
    const abort=()=>proc?.kill('SIGKILL');
    try{
      const systemFile=join(dir,'instructions.txt');await writeFile(systemFile,input.system,{mode:0o600});
      const env:Record<string,string>={DO_NOT_TRACK:'1',CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:'1'};
      for(const key of ['HOME','PATH','USER','LANG','LC_ALL','TMPDIR','ANTHROPIC_API_KEY','ANTHROPIC_AUTH_TOKEN','CLAUDE_CODE_OAUTH_TOKEN','HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','NO_PROXY','SSL_CERT_FILE'])if(process.env[key])env[key]=process.env[key]!;
      proc=Bun.spawn([this.executable,...chatClaudeArgs(systemFile,input.model)],{cwd:dir,env,stdin:'pipe',stdout:'pipe',stderr:'pipe'});
      runtimePids.add(proc.pid);input.signal.addEventListener('abort',abort,{once:true});
      timer=setTimeout(()=>{timedOut=true;abort();},this.timeoutMs);timer.unref();
      if(input.signal.aborted)abort();
      const stderr=(async()=>{let out='';for await(const chunk of proc!.stderr as any){out=(out+new TextDecoder().decode(chunk)).slice(-4000);}return out;})();
      const parser=new ChatClaudeOutput(),decoder=new TextDecoder();let buffer='';
      (proc.stdin as any).write(input.prompt);(proc.stdin as any).end();
      for await(const chunk of proc.stdout as any){
        buffer+=decoder.decode(chunk,{stream:true});if(buffer.length>4*1024*1024)throw Error('The provider returned an oversized event.');
        let end:number;
        while((end=buffer.indexOf('\n'))>=0){
          const line=buffer.slice(0,end);buffer=buffer.slice(end+1);if(!line.trim())continue;
          const delta=parser.accept(JSON.parse(line));if(delta)await input.onText(delta);
        }
      }
      if(buffer.trim()){const delta=parser.accept(JSON.parse(buffer));if(delta)await input.onText(delta);}
      const code=await proc.exited,error=await stderr;
      if(input.signal.aborted)throw Error('Stopped');if(timedOut)throw Error('The provider timed out. Your conversation is saved.');
      if(code!==0)throw Error(error.trim().slice(-1000)||`Claude stopped before completing this reply (${code}).`);
      if(parser.result===undefined)throw Error('Claude stopped before confirming a complete reply.');
      return parser.result;
    }finally{
      clearTimeout(timer);input.signal.removeEventListener('abort',abort);
      if(proc){runtimePids.delete(proc.pid);proc.kill('SIGKILL');await proc.exited;}
      await rm(dir,{recursive:true,force:true});
    }
  }
}
