import {test,expect} from 'bun:test';
import {mkdtemp,mkdir,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {legacyChatTranscripts} from './chat-transcript-history';
import type {ChatTurn} from './chat-sessions';

test('legacy native history recovers tools without exposing memory, imported history or another turn',async()=>{
 const root=await mkdtemp(join(tmpdir(),'chat-history-'));try{
  const cwd='/private/chat/provider',provider=randomUUID(),project=join(root,cwd.replace(/\//g,'-'));
  await mkdir(project,{recursive:true});
  const turn:ChatTurn={requestID:'request',sequence:1,state:'completed',user:{id:'user',sequence:1,role:'user',text:'Check files',ts:1000,requestID:'request'},assistant:{id:'assistant',sequence:2,role:'assistant',text:'Done',ts:2000,requestID:'request'}};
  const rows=[
   {type:'assistant',message:{content:[{type:'text',text:'Unowned prior reply'}]}},
   {type:'user',timestamp:new Date(1000).toISOString(),message:{content:JSON.stringify({privateMemory:'PRIVATE MEMORY',importedHistory:'PRIVATE HISTORY',currentMessage:'Check files'})}},
   {type:'assistant',message:{id:'intermediate',content:[{type:'text',text:'Inspecting files.'},{type:'tool_use',id:'read',name:'Read',input:{file_path:'/tmp/a'}}]}},
   {type:'user',message:{content:[{type:'tool_result',tool_use_id:'read',content:'Found the file'}]}},
   {type:'assistant',message:{id:'final',content:[{type:'text',text:'Done'}]}},
   {type:'user',message:{content:'Unrecognized provider input'}},
   {type:'assistant',message:{id:'unowned',content:[{type:'text',text:'Unowned reply'}]}},
   {type:'user',timestamp:new Date(5000).toISOString(),message:{content:JSON.stringify({currentMessage:'Check files',privateMemory:'OTHER MEMORY'})}},
   {type:'assistant',message:{content:[{type:'text',text:'Different reply'}]}},
  ];
  await writeFile(join(project,provider+'.jsonl'),rows.map(r=>JSON.stringify(r)).join('\n')+'\n');
  const result=await legacyChatTranscripts(cwd,provider,[turn],root);
  expect(result[0]!.messages.map(m=>m.kind)).toEqual(['text','tool_use','tool_result','text']);
  expect(result[0]!.messages.at(-1)!.text).toBe('Done');
  expect(JSON.stringify(result)).not.toContain('PRIVATE');expect(JSON.stringify(result)).not.toContain('Different reply');expect(JSON.stringify(result)).not.toContain('Unowned reply');
  expect(await legacyChatTranscripts(cwd,'../escape',[turn],root)).toEqual([]);
 }finally{await rm(root,{recursive:true,force:true});}
});
