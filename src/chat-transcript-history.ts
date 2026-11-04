import {join,dirname,basename} from 'node:path';
import {homedir} from 'node:os';
import {readFile} from 'node:fs/promises';
import {ChatTranscript} from './chat-transcript';
import {listSubagentSessions,resolveSubagentTranscript} from './subagents';
import {recentMessages} from './sessions';
import type {ChatTurn,ChatTranscriptTurn} from './chat-sessions';

/** Read-only compatibility for turns saved before rich activity capture.
 * Only a recognized LFG request envelope can associate provider rows with a turn.
 * Never return that envelope, imported history, standing instructions or memory. */
export async function legacyChatTranscripts(directory:string,providerID:string,turns:ChatTurn[],projects=process.env.LFG_CLAUDE_PROJECTS_DIR??join(process.env.HOME??homedir(),'.claude','projects')):Promise<ChatTranscriptTurn[]>{
 if(!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(providerID))return [];
 const eligible=turns.filter(t=>!t.transcript&&!t.job&&!t.notice);
 if(!eligible.length)return [];
 let path:string|undefined;
 for(const encoded of new Set([directory.replace(/\//g,'-'),directory.replace(/[/.]/g,'-')])){
  const candidate=join(projects,encoded,providerID+'.jsonl');if(await Bun.file(candidate).exists()){path=candidate;break;}
 }
 if(!path)return [];
 const file=Bun.file(path),start=Math.max(0,file.size-1024*1024);
 let text=await file.slice(start).text();if(start>0)text=text.slice(text.indexOf('\n')+1);
 const captures=new Map<string,{turn:ChatTurn;capture:ChatTranscript}>();
 let eventTime=0;
 let active:ChatTranscript|undefined;
 for(const line of text.split('\n')){
  let event:any;try{event=JSON.parse(line);}catch{continue;}
  const time=Date.parse(event.timestamp);if(Number.isFinite(time))eventTime=time;
  if(event.type==='user'){
   const content=event.message?.content;
   const raw=typeof content==='string'?content:Array.isArray(content)?content.filter((b:any)=>b.type==='text').map((b:any)=>b.text).join('\n'):'';
   if(raw){
    let prompt:any;try{prompt=JSON.parse(raw);}catch{}
    if(typeof prompt?.currentMessage==='string'){
     const timestamp=Date.parse(event.timestamp);
     const matches=Number.isFinite(timestamp)?eligible.filter(t=>t.user.text===prompt.currentMessage&&timestamp>=t.user.ts&&(t.state==='running'||timestamp<=t.assistant.ts)):[];
     const turn=matches.sort((a,b)=>Math.abs(a.user.ts-timestamp)-Math.abs(b.user.ts-timestamp))[0];
     if(turn){const existing=captures.get(turn.requestID);active=existing?.capture??new ChatTranscript(turn.requestID,()=>eventTime);captures.set(turn.requestID,{turn,capture:active});}
     else active=undefined;
     continue;
    }
    if(event.isMeta!==true)active=undefined;
   }
  }
  active?.accept(event);
 }
 const sidecars=await listSubagentSessions(path);
 const result:ChatTranscriptTurn[]=[];
 for(const {turn,capture} of captures.values()){
  if(!capture.messages.length)continue;
  const snapshot={requestID:turn.requestID,sequence:turn.sequence,messages:capture.messages,agents:capture.agents,childTranscripts:capture.childTranscripts};
  for(const child of sidecars){
   try{
    const meta=JSON.parse(await readFile(join(dirname(path),basename(path,'.jsonl'),'subagents',`agent-${child.id}.meta.json`),'utf8'));
    const index=snapshot.agents.findIndex(a=>a.id===meta.toolUseId);if(index<0)continue;
    const id=snapshot.agents[index]!.id;snapshot.agents[index]={...child,id};
    const childPath=resolveSubagentTranscript(path,child.id);if(childPath)snapshot.childTranscripts[id]=await recentMessages(childPath,200);
   }catch{/* An incomplete sidecar must not erase the saved parent transcript. */}
  }
  result.push(snapshot);
 }
 return result;
}
