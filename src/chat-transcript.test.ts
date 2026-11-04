import {test,expect} from 'bun:test';
import {ChatTranscript,publicJobTranscript} from './chat-transcript';

test('native transcript replaces streamed blocks, retains intermediate prose and pairs tools using Session messages',()=>{
 const t=new ChatTranscript('request',()=>1000);
 t.accept({type:'stream_event',event:{type:'message_start',message:{id:'m1'}}});
 t.accept({type:'stream_event',event:{type:'content_block_start',index:0,content_block:{type:'text',text:''}}});
 t.accept({type:'stream_event',event:{type:'content_block_delta',index:0,delta:{type:'text_delta',text:'Checking'}}});
 const id=t.messages[0]!.id;
 t.accept({type:'assistant',uuid:'different-stream-uuid',message:{id:'m1',content:[{type:'text',text:'Checking files.'},{type:'tool_use',id:'read',name:'Read',input:{file_path:'/tmp/a.ts'}}]}});
 expect(t.messages[0]!.id).toBe(id);expect(t.messages[0]!.text).toBe('Checking files.');
 t.accept({type:'user',message:{content:[{type:'tool_result',tool_use_id:'read',content:'file contents'}]}});
 t.accept({type:'assistant',message:{id:'m2',content:[{type:'text',text:'Found the cause.'}]}});
 t.accept({type:'result',subtype:'success',result:'Found the cause.'});
 expect(t.messages.map(m=>m.kind)).toEqual(['text','tool_use','tool_result','text']);
 expect(t.messages[1]!.tool).toEqual({name:'Read',target:'/tmp/a.ts'});
 expect(t.messages[2]!.toolUseId).toBe('read');expect(t.messages[2]!.text).toBe('file contents');
});

test('child activity is separate from parent prose and supports completion, failure and stop',()=>{
 const t=new ChatTranscript('request',()=>1000);
 t.accept({type:'assistant',message:{content:[{type:'tool_use',id:'agent-1',name:'Agent',input:{description:'Find callers',subagent_type:'explorer',prompt:'PRIVATE DELEGATION'}}]}});
 expect(t.agents[0]!.status).toBe('running');expect(t.messages[0]!.text).not.toContain('PRIVATE DELEGATION');
 t.accept({type:'stream_event',parent_tool_use_id:'agent-1',event:{type:'content_block_delta',index:0,delta:{type:'text_delta',text:'Child progress'}}});
 t.accept({type:'result',parent_tool_use_id:'agent-1',subtype:'success',result:'Found three callers'});
 expect(t.agents[0]!.status).toBe('completed');expect(t.childMessages('agent-1').at(-1)!.text).toBe('Found three callers');
 expect(t.messages.some(m=>m.text.includes('Child progress'))).toBe(false);
 t.accept({type:'assistant',message:{content:[{type:'tool_use',id:'agent-2',name:'Agent',input:{description:'Check tests'}}]}});
 t.accept({type:'system',subtype:'task_notification',tool_use_id:'agent-2',status:'failed',summary:'Tests failed'});
 expect(t.agents[1]!.status).toBe('failed');
 t.accept({type:'assistant',message:{content:[{type:'tool_use',id:'agent-3',name:'Agent',input:{description:'Read docs'}}]}});
 t.stop();expect(t.agents[2]!.status).toBe('stopped');expect(t.agents[0]!.status).toBe('completed');
});

test('private input envelopes and duplicate provider snapshots never become transcript rows',()=>{
 const t=new ChatTranscript('request',()=>1000);
 t.accept({type:'user',message:{content:JSON.stringify({privateMemory:'PRIVATE MEMORY',currentMessage:'Hello'})}});
 const event={type:'assistant',uuid:'same',message:{id:'api-id',content:[{type:'text',text:'Hello'}]}};
 t.accept(event);t.accept(event);t.accept({type:'result',subtype:'success',result:'Hello'});
 expect(t.messages.map(m=>m.text)).toEqual(['Hello']);
});

test('task lifecycle accepts omitted tool ids, ignores stale runs and excludes shell tasks',()=>{
 const t=new ChatTranscript('request',()=>1000);
 t.accept({type:'system',subtype:'task_started',task_id:'child-task',task_type:'local_agent',run_id:'002',description:'Check callers'});
 t.accept({type:'system',subtype:'task_notification',task_id:'child-task',tool_use_id:'late-tool',run_id:'001',status:'completed',summary:'Stale'});
 expect(t.agents[0]!.status).toBe('running');
 t.accept({type:'system',subtype:'task_notification',task_id:'child-task',tool_use_id:'late-tool',run_id:'002',status:'completed',summary:'Found callers'});
 expect(t.agents).toHaveLength(1);expect(t.agents[0]!.status).toBe('completed');expect(t.agents[0]!.id).toBe('child-task');
 t.accept({type:'system',subtype:'task_started',task_id:'shell',tool_use_id:'bash',task_type:'local_bash',description:'Server'});
 t.accept({type:'system',subtype:'task_notification',task_id:'shell',tool_use_id:'bash',status:'completed',summary:'Done'});
 t.accept({type:'system',subtype:'task_started',task_id:'ambient',task_type:'local_agent',ambient:true});
 expect(t.agents).toHaveLength(1);
});

test('scheduled activity retains prose and tools while hiding partial and complete decision blocks',()=>{
 const rows:any[]=[{id:'call',role:'assistant',kind:'tool_use',text:'Read: /tmp/status',ts:1},
  {id:'report',role:'assistant',kind:'text',text:'Still waiting.\n\n<lfg_job_res',ts:2}];
 expect(publicJobTranscript(rows).map(m=>m.text)).toEqual(['Read: /tmp/status','Still waiting.']);
 rows[1].text='Approved.\n\n<lfg_job_result>{"notify":true,"stop":true}</lfg_job_result>';
 expect(publicJobTranscript(rows).map(m=>m.text)).toEqual(['Read: /tmp/status','Approved.']);
});
