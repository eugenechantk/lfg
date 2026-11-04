import {normalizeLineMessages,type SessionMsg} from './sessions';
import type {SubagentSession} from './subagents';

/** The scheduler's terminal decision is protocol data, not transcript prose. */
export function publicJobText(text:string):string{
 const marker='<lfg_job_result>';
 const complete=text.indexOf('<lfg_job_result');
 if(complete>=0)text=text.slice(0,complete);
 else {const partial=text.lastIndexOf('<');if(partial>=0&&marker.startsWith(text.slice(partial)))text=text.slice(0,partial);}
 return text.trimEnd();
}
export function publicJobTranscript(messages:SessionMsg[]):SessionMsg[]{
 return messages.flatMap(message=>{const text=publicJobText(message.text);return text.trim()?[{...message,text}]:[];});
}

/** Provider output projected through the same normalizer as coding Sessions.
 * The user's request is owned by LFG; never expose the provider's JSON envelope. */
export class ChatTranscript {
 messages:SessionMsg[]=[];
 private children=new Map<string,{agent:SubagentSession;transcript:ChatTranscript}>();
 private serial=0;
 private active='';
 private blocks:any[]=[];
 private committed=false;
 private inputJSON=new Map<number,string>();
 private tasks=new Map<string,{toolID:string;runID?:string}>();
 constructor(private namespace:string,private now=Date.now){}
 get agents(){return [...this.children.values()].map(c=>c.agent);}
 get childTranscripts(){return Object.fromEntries([...this.children].map(([id,c])=>[id,c.transcript.messages]));}
 childMessages(id:string){return this.children.get(id)?.transcript.messages??[];}
 private child(id:string,description='Child agent',agentType='Agent'){
  let child=this.children.get(id);
  if(!child){const ts=this.now();child={agent:{id,description,agentType,spawnDepth:1,status:'running',startedAt:ts,lastActivityAt:ts,finishedAt:null,result:null},transcript:new ChatTranscript(`${this.namespace}:child:${id}`,this.now)};this.children.set(id,child);}
  return child;
 }
 private finishChild(id:string,status:SubagentSession['status'],result?:string){
  const child=this.child(id),ts=this.now();
  child.agent={...child.agent,status,lastActivityAt:ts,finishedAt:status==='running'?null:ts,result:result?.trim().split('\n')[0]?.slice(0,1000)||null};
 }
 private upsert(rows:SessionMsg[]){
  for(const row of rows){
   // A provider can give the final snapshot a different event uuid. Tool ids
   // remain canonical, as do the assistant message/block ids below.
   const i=this.messages.findIndex(m=>m.id===row.id || (row.kind==='tool_use'&&m.kind==='tool_use'&&row.toolUseId&&m.toolUseId===row.toolUseId));
   if(i>=0)this.messages[i]={...row,id:this.messages[i]!.id};else this.messages.push(row);
  }
 }
 private render(){
  const content=this.blocks.map(b=>b??{type:'text',text:''});
  this.upsert(normalizeLineMessages(JSON.stringify({type:'assistant',uuid:this.active,timestamp:new Date(this.now()).toISOString(),message:{role:'assistant',content}})));
 }
 accept(event:any){
  if(event.parent_tool_use_id){
   const id=String(event.parent_tool_use_id),child=this.child(id);
   child.transcript.accept({...event,parent_tool_use_id:null});child.agent.lastActivityAt=this.now();
   if(event.type==='result')this.finishChild(id,event.is_error||event.subtype!=='success'?'failed':'completed',event.result);
   return;
  }
  if(event.type==='system'&&['task_started','task_notification','task_progress','task_updated'].includes(event.subtype)){
   if(event.ambient===true)return;
   const known=this.tasks.get(event.task_id);
   if(known?.runID&&event.run_id&&event.run_id<known.runID)return;
   const id=known?.toolID??event.tool_use_id??event.task_id;if(typeof id!=='string')return;
   if(!this.children.has(id)&&!['Agent','Task','local_agent','remote_agent'].includes(event.task_type))return;
   if(typeof event.task_id==='string')this.tasks.set(event.task_id,{toolID:id,runID:event.run_id??known?.runID});
   const child=this.child(id,event.description??'Child agent',event.task_type??'Agent');
   child.agent.lastActivityAt=this.now();
   if(event.subtype==='task_started'){child.agent.status='running';child.agent.finishedAt=null;child.agent.result=null;}
   if(event.subtype==='task_notification')this.finishChild(id,event.status==='completed'?'completed':event.status==='failed'?'failed':event.status==='stopped'?'stopped':'unknown',event.summary);
   if(event.subtype==='task_updated'&&event.patch?.status){
    const status=event.patch.status;
    if(status==='running'||status==='pending')this.finishChild(id,'running');
    else this.finishChild(id,status==='completed'?'completed':status==='failed'?'failed':'stopped',event.patch.error);
   }
   return;
  }
  if(event.type==='stream_event'){
   const e=event.event;if(!e)return;
   if(e.type==='message_start'){
    this.active=`${this.namespace}:${e.message?.id??++this.serial}`;this.blocks=[];this.inputJSON.clear();this.committed=false;return;
   }
   if(e.type==='content_block_start'||e.type==='content_block_delta'){
    if(!this.active||this.committed){this.active=`${this.namespace}:${++this.serial}`;this.blocks=[];this.inputJSON.clear();this.committed=false;}
    const index=Number.isSafeInteger(e.index)&&e.index>=0?e.index:0;if(index>200)return;
    if(e.type==='content_block_start')this.blocks[index]={...e.content_block};
    else if(e.delta?.type==='text_delta'){
     const block=this.blocks[index]??{type:'text',text:''};block.text=(block.text??'')+(e.delta.text??'');this.blocks[index]=block;
    }else if(e.delta?.type==='input_json_delta'){
     const json=(this.inputJSON.get(index)??'')+(e.delta.partial_json??'');this.inputJSON.set(index,json);
     try{if(this.blocks[index])this.blocks[index].input=JSON.parse(json);}catch{}
    }
    this.render();return;
   }
   return;
  }
  if(event.type==='assistant'&&Array.isArray(event.message?.content)){
   const key=event.message.id?`${this.namespace}:${event.message.id}`:(!this.committed&&this.active?this.active:`${this.namespace}:${event.uuid??++this.serial}`);
   this.active=key;this.blocks=event.message.content;this.render();this.committed=true;
   for(const block of this.blocks)if(block.type==='tool_use'&&block.name==='Agent'&&typeof block.id==='string'){
    const child=this.child(block.id,block.input?.description??'Child agent',block.input?.subagent_type??'Agent');
    child.agent.description=block.input?.description??child.agent.description;
   }
   return;
  }
  if(event.type==='user'&&Array.isArray(event.message?.content)){
   const content=event.message.content.filter((b:any)=>b.type==='tool_result');
   if(!content.length)return;
   const id=event.uuid??`results:${content.map((b:any)=>b.tool_use_id).join(':')}`;
   this.upsert(normalizeLineMessages(JSON.stringify({...event,uuid:`${this.namespace}:${id}`,timestamp:event.timestamp??new Date(this.now()).toISOString(),message:{role:'user',content}})));
   for(const block of content){
    if(!this.children.has(block.tool_use_id))continue;
    const text=typeof block.content==='string'?block.content:JSON.stringify(block.content);
    if(!text.startsWith('Async agent launched successfully.'))this.finishChild(block.tool_use_id,block.is_error?'failed':'completed',text);
   }
   return;
  }
  if(event.type==='result'&&event.subtype==='success'&&typeof event.result==='string'&&event.result.trim()){
   const last=this.messages.findLast(m=>m.role==='assistant'&&m.kind==='text');
   if(last?.text!==event.result)this.upsert([{id:`${this.namespace}:final`,role:'assistant',kind:'text',text:event.result,ts:this.now()}]);
  }
 }
 stop(){for(const [id,{agent}] of this.children)if(agent.status==='running')this.finishChild(id,'stopped');}
}
