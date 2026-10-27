import {test,expect} from 'bun:test';
import {mkdtemp,rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {ChatSessions,type ChatRunInput,type ChatRunner} from './chat-sessions';
import {nativeClaudeArgs,nativeClaudeEnvironment} from './chat-native';

test('native durable launch uses coding tools and host configuration while appending chat instructions',()=>{
 const args=nativeClaudeArgs('/private/instructions.txt',{providerSessionID:'provider-id',resume:false} as any,'claude-sonnet-5');
 expect(args).toContain('--dangerously-skip-permissions');
 expect(args[args.indexOf('--permission-prompts')+1]).toBe('none');
 expect(args[args.indexOf('--tools')+1]).toBe('default');
 expect(args).toContain('--append-system-prompt-file');
 for(const flag of ['--safe-mode','--bare','--strict-mcp-config','--mcp-config','--setting-sources','--system-prompt-file','--no-chrome','--no-session-persistence'])expect(args).not.toContain(flag);
 expect(args[args.indexOf('--session-id')+1]).toBe('provider-id');
 expect(args[args.indexOf('--system-prompt-snapshot')+1]).toBe('off');
 expect(args[args.indexOf('--model')+1]).toBe('claude-sonnet-5');
 const resumed=nativeClaudeArgs('/private/instructions.txt',{providerSessionID:'provider-id',resume:true} as any);
 expect(resumed[resumed.indexOf('--resume')+1]).toBe('provider-id');
 const env=nativeClaudeEnvironment({HOME:'/host',PATH:'/bin',MCP_PROBE_TOKEN:'test-token',CLAUDECODE:'1'});
 expect(env.MCP_PROBE_TOKEN).toBe('test-token');expect(env.HOME).toBe('/host');expect(env.CLAUDECODE).toBeUndefined();
});

test('native conversations persist binding and send only new input after the first turn',async()=>{
 const root=await mkdtemp(join(tmpdir(),'lfg-native-'));const calls:ChatRunInput[]=[];
 const runner:ChatRunner={nativeConversations:true,run:async input=>{calls.push(input);await input.native!.onReady();return 'Native answer';}};
 let chats=new ChatSessions(root,runner);
 try{
  const s=await chats.create({name:'Scout',instructions:'Begin with Hello',memory:'My dog is Pip'});
  await chats.send(s.id,{requestID:'one',text:'Remember willow'});await chats.settled(s.id);
  const bound=(await chats.detail(s.id)).session;expect(bound.providerStarted).toBe(true);expect(bound.providerSessionID).toBeTruthy();
  await chats.send(s.id,{requestID:'two',text:'What word?'});await chats.settled(s.id);
  expect(calls[1]!.native!.providerSessionID).toBe(bound.providerSessionID!);expect(calls[1]!.native!.resume).toBe(true);
  expect(calls[1]!.prompt).not.toContain('Remember willow');expect(JSON.parse(calls[1]!.prompt).importedHistory).toBeUndefined();
  expect(calls[1]!.system).not.toContain('Exchange text only');expect(calls[1]!.system).not.toContain('You have no tools');
  expect(calls[1]!.system).toContain('selected LFG host');
  await chats.close();chats=new ChatSessions(root,runner);await chats.ready;
  await chats.update(s.id,{revision:bound.revision,instructions:'Begin with Updated',memory:'My dog is Miso'});
  await chats.send(s.id,{requestID:'three',text:'What is my dog named?'});await chats.settled(s.id);
  expect(calls[2]!.native!.providerSessionID).toBe(bound.providerSessionID!);expect(calls[2]!.system).toContain('Begin with Updated');
  expect(JSON.parse(calls[2]!.prompt).privateMemory).toBe('My dog is Miso');
  expect((await chats.detail(s.id)).messages).toHaveLength(6);
 }finally{await chats.close();await rm(root,{recursive:true,force:true});}
});

test('earlier LFG-only history imports once while native provider handles later compaction',async()=>{
 const root=await mkdtemp(join(tmpdir(),'lfg-native-import-'));let chats=new ChatSessions(root,{run:async()=> 'Earlier answer'});
 try{
  const s=await chats.create({name:'Legacy'});await chats.send(s.id,{requestID:'legacy',text:'Earlier fact'});await chats.settled(s.id);await chats.close();
  const calls:ChatRunInput[]=[];chats=new ChatSessions(root,{nativeConversations:true,run:async i=>{calls.push(i);await i.native!.onReady();return 'Next';}},{contextLimit:1});
  await chats.send(s.id,{requestID:'new',text:'Continue'});await chats.settled(s.id);
  expect(JSON.parse(calls[0]!.prompt).importedHistory).toEqual([{user:'Earlier fact',assistant:'Earlier answer',state:'completed'}]);
  await chats.send(s.id,{requestID:'last',text:'Again'});await chats.settled(s.id);
  expect(calls.map(c=>c.purpose)).toEqual(['reply','reply']);expect(calls[1]!.prompt).not.toContain('Earlier fact');
 }finally{await chats.close();await rm(root,{recursive:true,force:true});}
});
