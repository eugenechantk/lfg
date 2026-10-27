import { describe, test, expect } from 'bun:test';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { ChatSessions, type ChatRunner, type ChatRunInput } from './chat-sessions';

async function fixture(runner: ChatRunner = {run: async () => 'Hello'}, options = {}) {
  const root = await mkdtemp(join(tmpdir(), 'lfg-chat-'));
  const events: {id:string;type:string;payload:any}[] = [];
  const chats = new ChatSessions(root, runner, { ...options, emit:(id:string,type:any,payload:any)=>events.push({id,type,payload}) });
  await chats.ready;
  return {root,chats,events,close:async()=>{await chats.close();await rm(root,{recursive:true,force:true});}};
}
const create = (chats:ChatSessions,name='Scout',memory='I prefer short answers') => chats.create({name,instructions:'Be precise',memory});

describe('durable chat sessions',()=>{
  test('creating an empty chat announces shared Session membership after persistence',async()=>{
    const f=await fixture();
    try {
      const s=await create(f.chats);
      expect(f.events).toEqual([{id:s.id,type:'busy',payload:{sid:s.id,busy:false}}]);
      const rows=await f.chats.sessions();
      expect(rows.map(row=>row.sessionId)).toEqual([s.id]);
      expect(rows[0]!.busy).toBe(false);
      expect((await f.chats.detail(s.id)).messages).toEqual([]);
    }finally{await f.close();}
  });
  test('create, edit, send and reload retain identity and private context without a desktop',async()=>{
    const calls:ChatRunInput[]=[];
    const f=await fixture({run:async input=>{calls.push(input);await input.onText('Hello');return 'Hello';}});
    try {
      const chat=await create(f.chats);
      expect(chat.kind).toBe('chat');
      await f.chats.update(chat.id,{revision:chat.revision,instructions:'Use two sentences',memory:'My dog is Pip'});
      await f.chats.send(chat.id,{requestID:'one',text:'Remember my dog'});
      await f.chats.settled(chat.id);
      await f.chats.close();const reloaded=new ChatSessions(f.root,{run:async()=>''});await reloaded.ready;
      const detail=await reloaded.detail(chat.id);
      expect(detail.session.instructions).toBe('Use two sentences');expect(detail.session.memory).toBe('My dog is Pip');
      expect(detail.messages.map(m=>m.text)).toEqual(['Remember my dog','Hello']);
      expect(JSON.parse(calls[0]!.prompt).privateMemory).toBe('My dog is Pip');expect(calls[0]!.system).toContain('Use two sentences');
      expect(JSON.stringify(detail)).not.toContain('spaceID');
      await reloaded.close();
    }finally{await f.close();}
  });
  test('private instructions, memory and summaries never enter another chat',async()=>{
    const calls:ChatRunInput[]=[];const f=await fixture({run:async input=>{calls.push(input);return 'OK';}});
    try {const a=await create(f.chats,'A','SECRET_MEMORY');const b=await create(f.chats,'B','Other memory');
      await f.chats.send(a.id,{requestID:'a',text:'SECRET_TURN'});await f.chats.settled(a.id);
      await f.chats.send(b.id,{requestID:'b',text:'Hi'});await f.chats.settled(b.id);
      expect(JSON.stringify(calls[1])).not.toContain('SECRET_');
    }finally{await f.close();}
  });
  test('same request is idempotent and a second active turn is rejected',async()=>{
    let release!:(s:string)=>void;let calls=0;
    const f=await fixture({run:async()=>{calls++;return new Promise<string>(resolve=>{release=resolve;});}});
    try {const s=await create(f.chats);await f.chats.send(s.id,{requestID:'same',text:'Hi'});
      await f.chats.send(s.id,{requestID:'same',text:'Hi'});
      await expect(f.chats.send(s.id,{requestID:'other',text:'Next'})).rejects.toThrow('already');
      await expect(f.chats.send(s.id,{requestID:'same',text:'Changed'})).rejects.toThrow('different');
      await Bun.sleep(10);release('Done');await f.chats.settled(s.id);
      await f.chats.send(s.id,{requestID:'same',text:'Hi'});expect(calls).toBe(1);
      expect((await f.chats.detail(s.id)).messages).toHaveLength(2);
    }finally{await f.close();}
  });
  test('stop retains partial output and permits the next turn',async()=>{
    const f=await fixture({run:async input=>{await input.onText('Partial');return await new Promise<string>((_,reject)=>input.signal.addEventListener('abort',()=>reject(new Error('Stopped')),{once:true}));}});
    try {const s=await create(f.chats);await f.chats.send(s.id,{requestID:'one',text:'Hi'});await Bun.sleep(10);
      await f.chats.interrupt(s.id);await f.chats.settled(s.id);
      const detail=await f.chats.detail(s.id);expect(detail.session.state).toBe('idle');expect(detail.turns[0]!.state).toBe('interrupted');
      expect(detail.messages.at(-1)!.text).toBe('Partial');
    }finally{await f.close();}
  });
  test('summaries compact context without deleting paginated original history',async()=>{
    const inputs:ChatRunInput[]=[];
    const f=await fixture({run:async input=>{inputs.push(input);return input.purpose==='summary'?'Older decision: use blue':'A'.repeat(60);}}, {contextLimit:350,keepRecentTurns:1});
    try {const s=await create(f.chats);
      for(let n=0;n<5;n++){await f.chats.send(s.id,{requestID:String(n),text:`Turn ${n} `+'X'.repeat(70)});await f.chats.settled(s.id);}
      const d=await f.chats.detail(s.id,{limit:4});expect(d.messages).toHaveLength(4);expect(d.hasMore).toBe(true);
      const older=await f.chats.detail(s.id,{before:d.messages[0]!.sequence,limit:4});expect(older.messages).toHaveLength(4);
      expect(d.session.summary).toContain('use blue');expect(inputs.filter(i=>i.purpose==='summary').length).toBeGreaterThan(0);
      expect(JSON.parse(inputs.filter(i=>i.purpose==='reply').at(-1)!.prompt).conversationMemory).toContain('Older decision');
    }finally{await f.close();}
  });
  test('summary failure blocks the turn without silently losing earlier context',async()=>{
    let replies=0;const f=await fixture({run:async input=>{if(input.purpose==='summary')throw Error('Summary unavailable');replies++;return 'A'.repeat(90);}}, {contextLimit:200,keepRecentTurns:1});
    try {const s=await create(f.chats);for(let n=0;n<3;n++){await f.chats.send(s.id,{requestID:String(n),text:'X'.repeat(90)});await f.chats.settled(s.id);}
      const d=await f.chats.detail(s.id);expect(d.session.state).toBe('blocked');expect(d.session.error).toContain('Summary unavailable');expect(replies).toBeLessThan(3);
    }finally{await f.close();}
  });
  test('snapshot and shared events use durable identity and explicit working state',async()=>{
    const f=await fixture();try{const s=await create(f.chats);await f.chats.send(s.id,{requestID:'one',text:'Hi'});await f.chats.settled(s.id);
      const snap=(await f.chats.sessions())[0]!;expect(snap.kind).toBe('chat');expect(snap.sessionId).toBe(s.id);expect(snap.busy).toBe(false);expect(snap.tmuxTarget).toBeNull();
      expect(f.events.filter(e=>e.type==='busy').map(e=>e.payload.busy)).toEqual([false,true,false]);
      expect(f.events.filter(e=>e.type==='msg').every(e=>e.id===s.id)).toBe(true);
    }finally{await f.close();}
  });
  test('settings use revision checks and invalid identifiers cannot escape the store',async()=>{
    const f=await fixture();try{const s=await create(f.chats);await f.chats.update(s.id,{revision:s.revision,memory:'Updated'});
      await expect(f.chats.update(s.id,{revision:s.revision,memory:'Stale'})).rejects.toThrow('changed');
      await expect(f.chats.detail('../escape')).rejects.toThrow('not found');
      await expect(f.chats.create({name:'',instructions:'',memory:''})).rejects.toThrow();
    }finally{await f.close();}
  });
  test('another service cannot recover or run turns in a live owners store',async()=>{
    const f=await fixture();const other=new ChatSessions(f.root,{run:async()=>''});
    try{await expect(other.ready).rejects.toThrow('already open');expect(await f.chats.list()).toEqual([]);}
    finally{await other.close();await f.close();}
  });
});
