import {createHash} from 'node:crypto';
import {ChatSessions,ChatError} from './chat-sessions';
import {TaskStore,TaskScheduler,TaskError,activeRun,taskAction,type ScheduledTask,type TaskRun,type TaskInput,type TaskExecutor,type RunSnapshot,type TaskNotification} from './scheduled-tasks';
import type {ApnsPayload,ApnsResult} from './push/apns';
import type {JobDecision} from './chat-job-result';
import {alertTitle} from './alert-title';

type Device={token:string;env:'sandbox'|'production';owner?:string|null};
export type JobPush={devices:()=>Promise<Device[]>;send:(device:Device,payload:ApnsPayload)=>Promise<ApnsResult>;hostId:()=>string;retire?:(token:string)=>Promise<void>};
// Compatibility DTOs only. All persistence and scheduling belong to TaskStore.
export type ChatJob={id:string;chatId:string;name:string;instructions:string;action:'notify'|'run';schedule:ScheduledTask['schedule'];notification:'always'|'requested';stopOnNotify:boolean;enabled:boolean;pausedAt?:number;cancelledAt?:number;nextRunAt:number|null;createdAt:number;updatedAt:number;revision:number;scheduledRunCount:number;requestID:string;requestFingerprint:string};
export type JobRun={id:string;jobId:string;chatId:string;scheduledFor:number;state:'queued'|'running'|'completed'|'failed'|'interrupted'|'cancelled';snapshot:ChatJob;createdAt:number;finishedAt?:number;summary?:string;error?:string;decision?:JobDecision};
export type JobNotification=Omit<TaskNotification,'taskId'>&{jobId:string};
type Options={now?:()=>number;push?:JobPush;scheduler?:TaskScheduler;migrateFrom?:string};
const requestFor=(r:TaskRun)=>r.chatRequestID??'job:'+r.id;
const tokenKey=(token:string)=>createHash('sha256').update(token).digest('hex');
const pushText=(text:string,limit:number)=>{let out='',bytes=0;for(const char of text){bytes+=Buffer.byteLength(JSON.stringify(char))-2;if(bytes>limit)break;out+=char;}return out;};
const jobView=(t:ScheduledTask):ChatJob=>({id:t.id,chatId:t.chatId!,name:t.name,instructions:t.prompt,action:t.action==='notify'?'notify':'run',schedule:t.schedule,notification:t.notification??'requested',stopOnNotify:t.stopOnNotify??false,enabled:t.enabled,pausedAt:t.pausedAt,cancelledAt:t.cancelledAt,nextRunAt:t.nextRunAt,createdAt:t.createdAt,updatedAt:t.updatedAt,revision:t.revision??1,scheduledRunCount:t.scheduledRunCount??0,requestID:t.requestID!,requestFingerprint:t.requestFingerprint!});
const runView=(r:TaskRun,t:ScheduledTask):JobRun=>({id:r.id,jobId:r.taskId,chatId:t.chatId!,scheduledFor:r.scheduledFor,state:r.status==='succeeded'?'completed':r.status==='starting'||r.status==='needs_input'?'running':r.status==='incomplete'?'failed':r.status,snapshot:jobView(r.snapshot??t),createdAt:r.startedAt,finishedAt:r.finishedAt,summary:r.summary,error:r.error,decision:r.decision});
const notificationView=(n:TaskNotification):JobNotification=>{const {taskId,...rest}=n;return {...rest,jobId:taskId};};

/** Executor for two actions of the existing scheduled-task primitive. */
class ChatTaskExecutor implements TaskExecutor {
 readonly immediate=true;
 private notificationCursor=0;
 constructor(private store:TaskStore,private chats:ChatSessions,private options:Options,private now:()=>number){}
 async validate(task:TaskInput){try{await this.chats.detail(task.chatId!);}catch(e){if(e instanceof ChatError)throw new TaskError(e.message,e.status);throw e;}}
 async recover(run:TaskRun){
  const receipt=await this.chats.jobReceipt(run.snapshot!.chatId!,requestFor(run));
  await this.store.transaction(s=>{const r=s.runs.find(x=>x.id===run.id)!;if(!activeRun(r))return;r.status=receipt?'running':'queued';if(receipt)r.sessionId=run.snapshot!.chatId;else delete r.sessionId;});
 }
 async launch(task:ScheduledTask,run:TaskRun){
  const saved=run.snapshot??task,chatId=saved.chatId!;
  let receipt=await this.chats.jobReceipt(chatId,requestFor(run));
  if(!receipt){
   if((await this.chats.detail(chatId)).session.state==='working')return null;
   const permitted=await this.store.transaction(s=>{const current=s.tasks.find(t=>t.id===task.id)!,r=s.runs.find(r=>r.id===run.id)!;
    if(current.cancelledAt!=null){r.status='cancelled';return false;}
    if(current.pausedAt!=null&&r.trigger!=='manual')return false;
    if(current.revision!==saved.revision||!activeRun(r)){if(activeRun(r))r.status='cancelled';return false;}
    r.status='starting';return true;
   });
   if(!permitted)return null;
   try{
    if(saved.action==='notify')receipt=await this.chats.appendReminder(chatId,{requestID:requestFor(run),name:saved.name,text:saved.prompt});
    else receipt=(await this.chats.send(chatId,{requestID:requestFor(run),text:saved.prompt},{runID:run.id,name:saved.name})).turn;
   }catch(error){if(error instanceof ChatError&&error.status===409){await this.store.transaction(s=>{const r=s.runs.find(x=>x.id===run.id)!;if(activeRun(r))r.status='queued';});return null;}throw error;}
  }
  return {sessionId:chatId};
 }
 async inspect(run:TaskRun):Promise<RunSnapshot>{
  const saved=run.snapshot!,receipt=await this.chats.jobReceipt(saved.chatId!,requestFor(run));
  if(!receipt)return {state:'missing',error:'The accepted chat receipt is missing. Inspect the conversation before running again.'};
  if(receipt.state==='running')return {state:'working'};
  if(receipt.state!=='completed')return {state:receipt.state==='interrupted'?'missing':'failed',error:receipt.error};
  if(saved.action==='chat'&&!receipt.jobDecision)return {state:'failed',error:'The task returned no verified notification decision.'};
  return {state:'idle',summary:receipt.assistant.text,decision:receipt.jobDecision,outcome:{status:'completed',summary:receipt.assistant.text}};
 }
 async afterTick(){
  const push=this.options.push;if(!push)return;
  let devices:Device[];try{devices=await push.devices();}catch{return;}
  const pending=(await this.store.read()).notifications.filter(n=>n.state==='pending');
  const ordered=[...pending.slice(this.notificationCursor),...pending.slice(0,this.notificationCursor)].slice(0,20);this.notificationCursor=pending.length?(this.notificationCursor+20)%pending.length:0;
  for(const n of ordered){
   if(!devices.length){await this.store.transaction(s=>{s.notifications.find(x=>x.id===n.id)!.error='No iOS device is registered.';});continue;}
   const currentKeys=new Set(devices.map(d=>tokenKey(d.token)));
   await this.store.transaction(s=>{const item=s.notifications.find(x=>x.id===n.id)!;for(const [key,d] of Object.entries(item.devices))if(d.state==='pending'&&!currentKeys.has(key)){d.state='retired';d.error='Device registration changed.';}});
   for(const d of devices){
    const key=tokenKey(d.token),current=(await this.store.read()).notifications.find(x=>x.id===n.id)!;
    if(current.state!=='pending')break;
    const prior=current.devices[key];if(prior&&prior.state!=='pending'||prior&&prior.nextAttemptAt>this.now())continue;
    const payload:ApnsPayload={title:alertTitle('job',pushText(n.title,160)),body:pushText(n.body,2000),sid:n.chatId,kind:'job',notificationId:n.id,hostId:push.hostId(),session:{id:n.chatId,title:pushText((await this.chats.detail(n.chatId)).session.name,160),kind:'chat'}};
    // Resolve asynchronous payload work first, then recheck immediately before
    // transport so a completed cancellation cannot be followed by a stale send.
    const permitted=await this.store.transaction(s=>s.notifications.find(x=>x.id===n.id)?.state==='pending'&&!s.tasks.find(j=>j.id===n.taskId)?.cancelledAt);
    if(!permitted)break;
    let result:ApnsResult;try{result=await push.send(d,payload);}catch{result={ok:false,status:0,reason:'Push transport unavailable'};}
    const retired=result.status===410||result.reason==='BadDeviceToken'||result.reason==='Unregistered';
    const attempts=(prior?.attempts??0)+1;
    await this.store.transaction(s=>{const item=s.notifications.find(x=>x.id===n.id)!;item.devices[key]={state:result.ok?'accepted':retired?'retired':'pending',attempts,nextAttemptAt:this.now()+Math.min(3600000,30000*2**Math.min(attempts,7)),error:result.ok?undefined:result.reason??`APNs ${result.status}`};item.error=result.ok?undefined:result.reason??`APNs ${result.status}`;});
    if(retired)await push.retire?.(d.token);
   }
   await this.store.transaction(s=>{const item=s.notifications.find(x=>x.id===n.id)!;if(item.state!=='pending')return;const states=Object.values(item.devices);if(states.length&&states.every(d=>d.state!=='pending')){item.state=states.some(d=>d.state==='accepted')&&!states.some(d=>d.state==='failed')?'accepted':'failed';if(!states.some(d=>d.state==='accepted'))item.error='No registered device accepted this notification.';}});
  }
 }
}

/** Old chat-job API adapter. It owns neither a store format nor a scheduler loop. */
export class ChatJobs {
 readonly store:TaskStore;
 readonly scheduler:TaskScheduler;
 readonly ready:Promise<void>;
 private ownsScheduler:boolean;
 private now:()=>number;
 constructor(store:TaskStore|string,private chats:ChatSessions,options:Options={}){
  this.now=options.now??Date.now;this.store=typeof store==='string'?new TaskStore(store):store;
  this.ownsScheduler=!options.scheduler;
  this.scheduler=options.scheduler??new TaskScheduler(this.store,{launch:async()=>{throw new TaskError('Session execution is unavailable in this test runtime.');},inspect:async()=>({state:'missing'})},this.now);
  const executor=new ChatTaskExecutor(this.store,chats,options,this.now);
  this.scheduler.register('chat',executor);this.scheduler.register('notify',executor);
  this.ready=chats.ready.then(async()=>{if(options.migrateFrom)await this.store.importChatJobs(options.migrateFrom);if(this.ownsScheduler)await this.scheduler.recover();});
 }
 async list(chatId?:string){await this.ready;const s=await this.store.read();return s.tasks.filter(t=>taskAction(t)!=='session'&&(!chatId||t.chatId===chatId)).map(t=>{const n=s.notifications.filter(n=>n.taskId===t.id).at(-1),r=s.runs.filter(r=>r.taskId===t.id).at(-1);return {...jobView(t),lastRun:r?runView(r,t):undefined,notificationState:n?.state,notificationError:n?.error};}).sort((a,b)=>b.createdAt-a.createdAt);}
 async detail(id:string){await this.ready;const s=await this.store.read(),task=s.tasks.find(t=>t.id===id&&taskAction(t)!=='session');if(!task)throw new TaskError('Job not found.',404);return {job:jobView(task),runs:s.runs.filter(r=>r.taskId===id).slice(-50).reverse().map(r=>runView(r,task)),notifications:s.notifications.filter(n=>n.taskId===id).slice(-20).reverse().map(notificationView)};}
 async create(input:any){await this.ready;await this.chats.detail(input.chatId);if(!['notify','run'].includes(input.action))throw new TaskError('Choose reminder or instructions.');return jobView(await this.scheduler.save({name:input.name,prompt:input.instructions,chatId:input.chatId,action:input.action==='run'?'chat':'notify',schedule:input.schedule,notification:input.notification,stopOnNotify:input.stopOnNotify,requestID:input.requestID}));}
 async update(id:string,input:any){await this.detail(id);const patch={...input};if(patch.instructions!==undefined){patch.prompt=patch.instructions;delete patch.instructions;}if(patch.action==='run')patch.action='chat';return jobView(await this.store.update(id,patch,this.now()));}
 async cancel(id:string){await this.detail(id);return jobView(await this.store.cancel(id,this.now()));}
 async runNow(id:string){await this.detail(id);await this.scheduler.runNow(id);await this.scheduler.tick();}
 async tick(){await this.ready;await this.scheduler.tick();}
 start(){void this.ready.then(()=>this.scheduler.start());return ()=>this.close();}
 async close(){await this.ready;if(this.ownsScheduler)await this.scheduler.close();}
}
