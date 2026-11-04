import {ChatJobs} from './chat-jobs';
import {ChatError,type ChatSessions} from './chat-sessions';
import {chatProfileTools} from './chat-profile-tools';
import {TaskError} from './scheduled-tasks';
import {createMcpHandler,text,type McpTool} from './mcp-server';
import {scheduledTaskTools} from './scheduled-task-tools';

export function chatJobTools(jobs:ChatJobs,chatId:string):McpTool[]{
 const jobId={type:'string' as const,description:'The saved job id.'};
 const schedule={type:'object' as const,properties:{kind:{type:'string' as const,enum:['once','interval','repeat','cron']},timezone:{type:'string' as const,description:'IANA timezone. Resolve relative times using the current clock.'},at:{type:'string' as const,description:'ISO 8601 first start with timezone offset; required for once/repeat.'},everyMinutes:{type:'integer' as const,minimum:1},occurrences:{type:'integer' as const,minimum:1},expression:{type:'string' as const},maxRuns:{type:'integer' as const},endsAt:{type:'string' as const}} as any,required:['kind','timezone']};
 const properties={name:{type:'string' as const},instructions:{type:'string' as const,description:'Saved reminder text, or self-contained work/check instructions. State when to notify and when to stop.'},action:{type:'string' as const,enum:['notify','run'],description:'notify sends saved text without a model; run resumes this durable chat with the saved instructions.'},schedule,notification:{type:'string' as const,enum:['requested','always'],description:'requested only alerts when the job result asks; always alerts after each completed execution.'},stopOnNotify:{type:'boolean' as const},requestID:{type:'string' as const,description:'Stable unique identifier for this creation request. Reuse it when retrying the same save.'}};
 const scoped=async(id:unknown)=>{if(typeof id!=='string')throw new ChatError('Choose a job.');const d=await jobs.detail(id);if(d.job.chatId!==chatId)throw new ChatError('Job not found.',404);return id;};
 const result=(v:unknown)=>text(JSON.stringify(v));
 const {action:_action,requestID:_requestID,...editable}=properties;
 return [
 {name:'create_job',description:'Save a user-requested reminder or recurring instruction job for this durable chat. The host must be awake to execute. Do not claim it exists before this tool succeeds.',inputSchema:{type:'object',properties,required:['name','instructions','action','schedule','requestID']},run:async a=>result({job:await jobs.create({...a,chatId})})},
 {name:'list_jobs',description:'Read jobs, next run, last result and notification state for this chat.',inputSchema:{type:'object',properties:{}},annotations:{readOnlyHint:true},run:async()=>result({jobs:await jobs.list(chatId)})},
 {name:'update_job',description:'Edit or pause/resume a job. Read its current revision first. Supply only requested changes. Running work keeps its accepted instructions.',inputSchema:{type:'object',properties:{...editable,jobId,revision:{type:'integer'},enabled:{type:'boolean'}},required:['jobId','revision']},run:async a=>result({job:await jobs.update(await scoped(a.jobId),a)})},
 {name:'cancel_job',description:'Cancel future runs and unsent notifications. Does not undo actions already completed or interrupt a currently running turn.',inputSchema:{type:'object',properties:{jobId},required:['jobId']},run:async a=>result({job:await jobs.cancel(await scoped(a.jobId))})},
 {name:'job_history',description:'Read recent runs, errors and per-device notification delivery state.',inputSchema:{type:'object',properties:{jobId},required:['jobId']},annotations:{readOnlyHint:true},run:async a=>result(await jobs.detail(await scoped(a.jobId)))},
 ];
}
export function chatJobRoutes(jobs:ChatJobs,canonical?: (req:Request)=>Promise<Response|null>,chats?:ChatSessions){
 return async(req:Request):Promise<Response|undefined>=>{
  const u=new URL(req.url),base='/api/chat-jobs';if(!u.pathname.startsWith(base)&&!u.pathname.startsWith('/api/scheduled-tasks/mcp/'))return;
  const json=(v:unknown,status=200)=>Response.json(v,{status,headers:{'Cache-Control':'no-store'}});
  try{
   const origin=req.headers.get('origin');if(req.method!=='GET'&&origin&&origin!==u.origin)throw new ChatError('Cross-origin request refused.',403);
   const mcp=u.pathname.match(/^\/api\/(?:chat-jobs|scheduled-tasks)\/mcp\/(chat-[a-f0-9-]{36})$/);
   if(mcp){
    const chatId=mcp[1]!;await jobs.list(chatId);if(chats)await chats.detail(chatId);
    let tools=chatJobTools(jobs,chatId);
    if(u.pathname.startsWith('/api/scheduled-tasks/')){
     if(!canonical)throw new TaskError('Scheduled task tools are unavailable on this host.',503);
     const relay=async<T>(path:string,body?:unknown):Promise<T>=>{
      if(path==='/api/scheduled-tasks'&&body===undefined)path+='?chatId='+chatId;
      const id=path.match(/^\/api\/scheduled-tasks\/([a-f0-9-]{36})/)?.[1];
      if(id&&!(await jobs.store.read()).tasks.some(t=>t.id===id&&t.chatId===chatId))throw new TaskError('Task not found.',404);
      if(path==='/api/scheduled-tasks'&&body!==undefined){if((body as any).chatId!=null&&(body as any).chatId!==chatId)throw new TaskError('Task not found.',404);body={...(body as object),chatId,action:(body as any).action??'chat'};}
      const response=await canonical(new Request(new URL(path,u.origin).toString(),body===undefined?{}:{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}));
      if(!response)throw new TaskError('Task endpoint unavailable.',404);const data=await response.json() as any;if(!response.ok)throw new TaskError(data.error??'Task request failed.',response.status);return data as T;
     };
     tools=scheduledTaskTools({get:path=>relay(path),post:(path,body)=>relay(path,body)});
     for(const tool of tools){if(tool.name==='create_scheduled_task'){const {chatId:_owner,...properties}=tool.inputSchema.properties??{};tool.inputSchema={...tool.inputSchema,properties};tool.description+=' The owning chat is supplied by this server.';}}
    }
    if(chats)tools.push(...chatProfileTools(chats,chatId));
    return createMcpHandler({name:'lfg-durable-jobs',version:'2.1.0',instructions:'Tools are scoped to this durable chat. Profile changes require an explicit user request and apply to subsequent turns. For scheduled chat or notify actions use a stable requestID and omit cwd/agent/model. Never use OS cron or provider-native loops.',tools})(req);
   }
   const body=async()=>{const s=await req.text();if(s.length>50000)throw new ChatError('Request too large.',413);try{const b=JSON.parse(s);if(!b||typeof b!=='object'||Array.isArray(b))throw Error();return b;}catch{throw new ChatError('Expected a JSON object.');}};
   if(u.pathname===base){if(req.method==='GET')return json({jobs:await jobs.list(u.searchParams.get('chatId')??undefined)});if(req.method==='POST')return json({job:await jobs.create(await body())},201);}
   const match=u.pathname.match(/^\/api\/chat-jobs\/([a-f0-9-]{36})(?:\/(cancel|run))?$/);if(!match)return json({error:'Job not found.'},404);
   const [,id,action]=match;
   if(req.method==='GET'&&!action)return json(await jobs.detail(id!));
   if(req.method==='POST'){if(action==='cancel')return json({job:await jobs.cancel(id!)});if(action==='run'){await jobs.runNow(id!);return json({ok:true},202);}return json({job:await jobs.update(id!,await body())});}
   return json({error:'Method not allowed.'},405);
  }catch(e){return json({error:e instanceof Error?e.message:'Jobs are unavailable.'},e instanceof ChatError||e instanceof TaskError?e.status:400);}
 };
}
