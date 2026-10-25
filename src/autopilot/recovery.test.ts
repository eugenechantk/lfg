import { expect, test } from 'bun:test';
import { mkdtemp, readFile, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { recoveryError, runRecovery, RECOVERY_PREFIX, type RecoveryDeps } from './recovery.ts';

const now = 2_000_000;
function transcript(extra: object = {}) {
 return JSON.stringify({ type:'user', uuid:'user1', message:{content:'Do the work'} })+'\n'+JSON.stringify({type:'assistant',uuid:'error1',sessionId:'s1',timestamp:new Date(now).toISOString(),isApiErrorMessage:true,error:'server_error',message:{content:[{type:'text',text:'API Error: Connection lost mid-response. The response above may be incomplete.'}]},...extra});
}
test('only terminal structured connection errors qualify, including fork provenance', () => {
 expect(recoveryError(transcript(),'s1')?.id).toBe('error1');
 expect(recoveryError(transcript(),'fork')).toBeNull();
 for(const extra of [{isApiErrorMessage:false},{error:'rate_limit'},{message:{content:[{type:'text',text:'API Error: 500 internal server error'}]}}]) expect(recoveryError(transcript(extra),'s1')).toBeNull();
 for(const row of [{type:'user',message:{content:'Stop'}},{type:'assistant',message:{content:[{type:'text',text:'Done'}]}},{type:'system',subtype:'continued-in'}]) expect(recoveryError(transcript()+'\n'+JSON.stringify(row),'s1')).toBeNull();
});

test('claims survive reload, concurrent ticks and uncertain delivery; dry runs do not write', async () => {
 const dir=await mkdtemp(join(tmpdir(),'lfg-recovery-'));
 try {
 let at=now-1000, sends=0;
 const candidate={sessionId:'s1'} as any;
 const deps:RecoveryDeps={dir,list:async()=>[candidate],inspect:async()=>({id:'error1',at:now,taskId:'user1'}),send:()=>{sends++}};
 const ctx=()=>({now:at,dryRun:false,log:()=>{}});
 await runRecovery(ctx(),deps); // activation; error is not yet settled
 at=now+120_000;
 const dry=await runRecovery({...ctx(),dryRun:true},deps);
 expect(dry.changed).toBe(0); expect(sends).toBe(0);
 await Promise.all([runRecovery(ctx(),deps),runRecovery(ctx(),deps)]);
 expect(sends).toBe(1);
 await runRecovery(ctx(),deps); expect(sends).toBe(1);
 expect((await readdir(dir)).filter(x=>x.startsWith('claim-')).length).toBe(1);
 const blank=join(dir,'dry');
 await runRecovery({...ctx(),dryRun:true},{...deps,dir:blank});
 expect(await Bun.file(join(blank,'activation.json')).exists()).toBe(false);
 }finally{await rm(dir,{recursive:true,force:true})}
});

test('historical errors, backoff and three-attempt budget; human instruction resets budget',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'lfg-recovery-'));
 try{
 let at=now, errorAt=now-1000,id='old',taskId='task',sends=0;
 const deps:RecoveryDeps={dir,list:async()=>[{sessionId:'s1'} as any],inspect:async()=>({id,at:errorAt,taskId}),send:()=>{sends++}};
 const tick=()=>runRecovery({now:at,dryRun:false,log:()=>{}},deps);
 await tick();expect(sends).toBe(0);
 for(let i=1;i<=3;i++){
  id='e'+i;errorAt=at+1;at+=120_000;
  await tick();
  if(i>1){expect(sends).toBe(i-1);at+=40*60_000;await tick()}
  expect(sends).toBe(i);
 }
 id='e4';errorAt=at+1;at+=60*60_000;await tick();expect(sends).toBe(3);
 taskId='human2';await tick();expect(sends).toBe(4);
 }finally{await rm(dir,{recursive:true,force:true})}
});

test('uncertain send is never automatically retried',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'lfg-recovery-'));let sends=0;
 try{
 const deps:RecoveryDeps={dir,list:async()=>[{sessionId:'s1'} as any],inspect:async()=>({id:'e',at:now+1,taskId:'u'}),send:()=>{sends++;throw Error('uncertain')}};
 await runRecovery({now,dryRun:false,log:()=>{}},deps);
 await runRecovery({now:now+120000,dryRun:false,log:()=>{}},deps);
 await runRecovery({now:now+240000,dryRun:false,log:()=>{}},deps);
 expect(sends).toBe(1);
 }finally{await rm(dir,{recursive:true,force:true})}
});

test('registered recovery precedes model-backed retitling', async () => {
 const { STEPS } = await import('./tick.ts');
 expect(STEPS.map(s=>s.name)).toEqual(['recover-connections','retitle-sessions']);
});

test('live-session inspection protects ownership, busy work, prompts, drafts, queues and Stop', async () => {
 const { inspectRecoverySession, recoveryDeliverySafe, recoveryClientId } = await import('./recovery.ts');
 const dir = await mkdtemp(join(tmpdir(),'lfg-recovery-inspect-'));
 const path=join(dir,'s1.jsonl');
 try {
 await Bun.write(path,transcript());
 const pane='────────────────────────────────────────\n❯ \n────────────────────────────────────────\n  bypass permissions on';
 const s={sessionId:'s1',agent:'claude',control:'direct',pid:42,transcriptPath:path,tmuxTarget:'fixture:0.0',busy:false,last:{ts:now}} as any;
 const deps={lease:async()=>({hostId:'here',pid:42,acquiredAt:now,heartbeatAt:Date.now()}),hostId:()=> 'here',queue:()=>[],pane:async()=>pane,stopped:async()=>false};
 expect((await inspectRecoverySession(s,Date.now(),undefined,deps))?.id).toBe('error1');
 for (const extra of [{busy:true},{agent:'codex'},{control:'external'},{runningChildAgentCount:1},{runningChildSessionCount:1},{runningBackgroundProcessCount:1},{tmuxTarget:null},{lastUserAt:now+1}]) expect(await inspectRecoverySession({...s,...extra},Date.now(),undefined,deps)).toBeNull();
 for (const lease of [null,{hostId:'peer',pid:42,heartbeatAt:Date.now()},{hostId:'here',pid:7,heartbeatAt:Date.now()},{hostId:'here',pid:42,heartbeatAt:now},{hostId:'here',pid:42,heartbeatAt:Date.now(),state:'ended'}]) expect(await inspectRecoverySession(s,Date.now(),undefined,{...deps,lease:async()=>lease as any})).toBeNull();
 for(const p of [null,'unknown rendering',pane.replace('❯ ','❯ My unsent instruction')]) expect(await inspectRecoverySession(s,Date.now(),undefined,{...deps,pane:async()=>p})).toBeNull();
 expect(await inspectRecoverySession(s,Date.now(),undefined,{...deps,stopped:async()=>true})).toBeNull();
 expect(await inspectRecoverySession(s,Date.now(),undefined,{...deps,queue:()=>[{id:'other',status:'pending'} as any]})).toBeNull();
 const msg={id:'own',clientId:recoveryClientId('error1')} as any;
 expect(await recoveryDeliverySafe(s,msg,deps)).toBe(true);
 expect(await recoveryDeliverySafe(s,{...msg,clientId:recoveryClientId('different')},deps)).toBe(false);
 await Bun.write(path,transcript()+'\n'+JSON.stringify({type:'user',uuid:'new',message:{content:'Stop'}}));
 expect(await recoveryDeliverySafe(s,msg,deps)).toBe(false);
 } finally {await rm(dir,{recursive:true,force:true})}
});

test('finds the task boundary beyond a large tool result and ignores recovery prompts', async()=>{
 const {readRecoveryError}=await import('./recovery.ts');
 const dir=await mkdtemp(join(tmpdir(),'lfg-recovery-long-'));const path=join(dir,'session.jsonl');
 try{
 const [user,error]=transcript().split('\n');
 const tool=JSON.stringify({type:'user',message:{content:[{type:'tool_result',content:'x'.repeat(700000)}]}});
 const recovery=JSON.stringify({type:'user',uuid:'recovery',message:{content:RECOVERY_PREFIX+' Continue'}});
 await Bun.write(path,[user,tool,recovery,error].join('\n'));
 expect((await readRecoveryError(path,'s1'))?.taskId).toBe('user1');
 }finally{await rm(dir,{recursive:true,force:true})}
});

test('Stop intent from the durable operation log survives a host restart',async()=>{
 const {explicitlyStopped}=await import('./recovery.ts');
 const dir=await mkdtemp(join(tmpdir(),'lfg-recovery-stop-'));
 const previous=process.env.LFG_OPS_LOG;
 try{
 process.env.LFG_OPS_LOG=join(dir,'ops.log');
 await Bun.write(process.env.LFG_OPS_LOG,JSON.stringify({at:new Date(now+1000).toISOString(),op:'interrupt',sessionId:'s1',ok:false}));
 expect(await explicitlyStopped('s1','unused',null,now)).toBe(true);
 expect(await explicitlyStopped('other','unused',null,now)).toBe(false);
 expect(await explicitlyStopped('s1','unused',null,now+2000)).toBe(false);
 }finally{if(previous===undefined)delete process.env.LFG_OPS_LOG;else process.env.LFG_OPS_LOG=previous;await rm(dir,{recursive:true,force:true})}
});

test('partial transcript writes veto recovery, and activity during final recheck prevents enqueue',async()=>{
 expect(recoveryError(transcript()+'\n{"type":"user"','s1')).toBeNull();
 const dir=await mkdtemp(join(tmpdir(),'lfg-recovery-race-'));
 try{
 let reads=0,sends=0;
 const deps:RecoveryDeps={dir,list:async()=>[{sessionId:'s1'} as any],inspect:async()=> ++reads===2 ? null : ({id:'e',at:now+1,taskId:'u'}),send:()=>{sends++}};
 await runRecovery({now,dryRun:false,log:()=>{}},deps);
 reads=0;
 await runRecovery({now:now+120000,dryRun:false,log:()=>{}},deps);
 expect(sends).toBe(0);
 expect((await readdir(dir)).filter(n=>n.startsWith('claim-'))).toEqual([]);
 }finally{await rm(dir,{recursive:true,force:true})}
});

test('queue reconciliation never re-drives an uncertain recovery, but can acknowledge delivery',async()=>{
 const {reconcileQueuedCore}=await import('../sendq.ts');
 const {recoveryClientId}=await import('./recovery.ts');
 const msg={id:'m',clientId:recoveryClientId('e'),text:RECOVERY_PREFIX+' Continue',status:'queued',attempts:1,createdAt:0,updatedAt:0} as any;
 expect(reconcileQueuedCore([msg],[],{idleConfirmed:true,now:1000000})).toEqual({changed:true,kick:false});
 expect(msg.status).toBe('failed');
 const delivered={...msg,status:'queued'};
 expect(reconcileQueuedCore([delivered],[msg.text],{idleConfirmed:true,now:1000000})).toEqual({changed:true,kick:false});
 expect(delivered.status).toBe('delivered');
});

test('twenty concurrent ticks see complete activation and claim records', async()=>{
 const dir=await mkdtemp(join(tmpdir(),'lfg-recovery-stress-'));let sends=0;
 try{
 const deps:RecoveryDeps={dir,list:async()=>[{sessionId:'s1'} as any],inspect:async()=>({id:'e',at:now+1,taskId:'u'}),send:()=>{sends++}};
 await runRecovery({now,dryRun:false,log:()=>{}},deps);
 const results=await Promise.allSettled(Array.from({length:20},()=>runRecovery({now:now+120000,dryRun:false,log:()=>{}},deps)));
 expect(results.every(r=>r.status==='fulfilled')).toBe(true);
 expect(sends).toBe(1);
 }finally{await rm(dir,{recursive:true,force:true})}
});

test('all observed connection wordings qualify; a native queued message vetoes recovery',()=>{
 for(const text of ['API Error: Connection lost mid-response. The response above may be incomplete.','API Error: Connection dropped (ECONNRESET)','API Error: The response stopped arriving. The response above may be incomplete.']) {
  expect(recoveryError(transcript({message:{content:[{type:'text',text}]}}),'s1')?.id).toBe('error1');
 }
 expect(recoveryError(transcript()+'\n'+JSON.stringify({type:'queue-operation',operation:'enqueue',content:'new instruction'}),'s1')).toBeNull();
});
