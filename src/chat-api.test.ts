import {test,expect} from 'bun:test';
import {mkdtemp,rm,readFile,writeFile,readdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {ChatSessions} from './chat-sessions';
import {chatRoutes} from './chat-api';
import {observeSession,runPushTick,type TickDeps,type PriorState} from './push/watcher';

test('chat HTTP flow creates, streams, edits and reloads without Cua routes',async()=>{
  const root=await mkdtemp(join(tmpdir(),'chat-api-'));
  const chats=new ChatSessions(root,{run:async i=>{await i.onText('Saved reply');return 'Saved reply';}});
  const route=chatRoutes(chats);
  const req=(path:string,body?:unknown)=>route(new Request('http://test/api/sessions'+path,{method:body?'POST':'GET',...(body?{body:JSON.stringify(body)}:{})}));
  try{
    const created=await req('/chats',{name:'Scout',instructions:'Short answers',memory:'My dog is Pip'});expect(created!.status).toBe(201);
    const {session}=await created!.json() as any;
    const sent=await req('/'+session.id+'/send',{text:'Hi',requestID:'one'});expect(sent!.status).toBe(202);await chats.settled(session.id);
    const detail=await (await req('/'+session.id))!.json() as any;expect(detail.messages.at(-1).text).toBe('Saved reply');
    expect((await req('/'+session.id+'/close',{}))!.status).toBe(409);
    const edit=await req('/'+session.id+'/settings',{revision:session.revision,memory:'Updated memory'});expect(edit!.status).toBe(200);
    expect((await req('/chats',{name:'Other',agent:'openai-codex'}))!.status).toBe(400);
    expect((await route(new Request('http://test/api/sessions/chats',{method:'POST',headers:{origin:'http://evil'},body:'{}'})))!.status).toBe(403);
    expect(await route(new Request('http://test/api/message/spaces'))).toBeUndefined();
    expect((await req('/'+session.id+'?limit=1000'))!.status).toBe(400);
  }finally{await chats.close();await rm(root,{recursive:true,force:true});}
});

test('recovery marks an unfinished receipt interrupted and never replays it',async()=>{
  const root=await mkdtemp(join(tmpdir(),'chat-recovery-'));let calls=0;
  const runner={run:async()=>{calls++;return 'Done';}};
  const chats=new ChatSessions(root,runner);
  try{
    const s=await chats.create({name:'Scout'});await chats.send(s.id,{text:'Hi',requestID:'same'});await chats.settled(s.id);await chats.close();
    const path=join(root,s.id),sessionFile=join(path,'session.json');
    const saved=JSON.parse(await readFile(sessionFile,'utf8'));saved.state='working';saved.activeRequestID='same';await writeFile(sessionFile,JSON.stringify(saved));
    const turnFile=join(path,'turns',(await readdir(join(path,'turns')))[0]!);
    const turn=JSON.parse(await readFile(turnFile,'utf8'));turn.state='running';await writeFile(turnFile,JSON.stringify(turn));
    const events:unknown[]=[];
    const restarted=new ChatSessions(root,runner,{emit:(_id,type,payload)=>{if(type==='busy')events.push(payload);}});await restarted.ready;
    const detail=await restarted.detail(s.id);expect(detail.session.state).toBe('idle');expect(detail.turns[0]!.state).toBe('interrupted');
    expect((await restarted.send(s.id,{text:'Hi',requestID:'same'})).duplicate).toBe(true);expect(calls).toBe(1);
    expect(events).toEqual([{sid:s.id,busy:false}]);
    await restarted.close();
  }finally{await chats.close();await rm(root,{recursive:true,force:true});}
});

test('shared push observation uses explicit chat status and never announces a failed turn as finished',async()=>{
  expect(await observeSession({kind:'chat',busy:true,sessionId:'chat-one'})).toEqual({busy:true,promptPresent:false});
  let outcome:'completed'|'failed'='failed';let sent=0;
  const prior=new Map<string,PriorState>([['chat-one',{busy:true,promptPresent:false,lastNotifiedAt:-Infinity}]]);
  const deps:TickDeps={sessions:async()=>[{kind:'chat',sessionId:'chat-one',title:'Scout',busy:false,turnOutcome:outcome}],observe:s=>observeSession(s),devices:async()=>[{token:'fixture',env:'sandbox'}],cfg:{key:'',keyId:'',teamId:'',topic:''},send:async()=>{sent++;return {ok:true,status:200};}};
  await runPushTick(prior,deps);expect(sent).toBe(0);
  prior.set('chat-one',{busy:true,promptPresent:false,lastNotifiedAt:-Infinity});outcome='completed';
  await runPushTick(prior,deps);expect(sent).toBe(1);
});
