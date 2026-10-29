import {test,expect} from 'bun:test';
import {mkdtemp,rm,cp,readFile,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {ChatSessions,type ChatRunInput} from '../../../src/chat-sessions';

const runner=(inputs:ChatRunInput[])=>({nativeConversations:true,run:async(input:ChatRunInput)=>{inputs.push(input);await input.native!.onReady();return 'Saved first reply';}});

test('routing the same chat ID to an empty host does not transfer history',async()=>{
 const root=await mkdtemp(join(tmpdir(),'lfg-chat-failover-probe-'));
 const inputsA:ChatRunInput[]=[],inputsB:ChatRunInput[]=[];
 const a=new ChatSessions(join(root,'a'),runner(inputsA)),b=new ChatSessions(join(root,'b'),runner(inputsB));
 try {
  const chat=await a.create({name:'Portable',instructions:'Use short replies',memory:'Favorite color: indigo'});
  await a.send(chat.id,{requestID:'first',text:'Remember the launch date is Friday'});await a.settled(chat.id);
  await b.create({id:chat.id,name:chat.name,instructions:chat.instructions,memory:chat.memory});
  await b.send(chat.id,{requestID:'second',text:'What did we decide?'});await b.settled(chat.id);
  expect(JSON.parse(inputsB[0].prompt).importedHistory).toBeUndefined();
  expect((await b.detail(chat.id)).messages.some(m=>m.requestID==='first')).toBe(false);
 }finally{await a.close();await b.close();await rm(root,{recursive:true,force:true});}
});

test('a complete LFG checkpoint can seed context on a fresh provider binding',async()=>{
 const root=await mkdtemp(join(tmpdir(),'lfg-chat-portable-checkpoint-'));
 const inputsA:ChatRunInput[]=[],inputsB:ChatRunInput[]=[];
 const a=new ChatSessions(join(root,'a'),runner(inputsA));let b:ChatSessions|undefined;
 try {
  const chat=await a.create({name:'Portable',instructions:'Use short replies',memory:'Favorite color: indigo'});
  await a.send(chat.id,{requestID:'first',text:'Remember the launch date is Friday'});await a.settled(chat.id);
  const original=(await a.detail(chat.id)).session;await a.close();
  await cp(join(root,'a',chat.id),join(root,'b',chat.id),{recursive:true});
  const path=join(root,'b',chat.id,'session.json'),checkpoint=JSON.parse(await readFile(path,'utf8'));
  checkpoint.providerSessionID=randomUUID();checkpoint.providerStarted=false;delete checkpoint.providerRevision;
  await writeFile(path,JSON.stringify(checkpoint));
  b=new ChatSessions(join(root,'b'),runner(inputsB));
  await b.send(chat.id,{requestID:'second',text:'What did we decide?'});await b.settled(chat.id);
  const prompt=JSON.parse(inputsB[0].prompt),result=await b.detail(chat.id);
  expect(result.session.id).toBe(chat.id);expect(result.session.providerSessionID).not.toBe(original.providerSessionID);
  expect(inputsB[0].native!.resume).toBe(false);expect(inputsB[0].system).toContain('Use short replies');
  expect(prompt.privateMemory).toBe('Favorite color: indigo');
  expect(prompt.importedHistory).toEqual([{user:'Remember the launch date is Friday',assistant:'Saved first reply',state:'completed'}]);
  expect(result.messages.filter(m=>m.role==='user').map(m=>m.requestID)).toEqual(['first','second']);
 }finally{await a.close();await b?.close();await rm(root,{recursive:true,force:true});}
});
