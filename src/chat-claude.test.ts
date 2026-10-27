import {test,expect} from 'bun:test';
import {ChatClaudeOutput,chatClaudeArgs,isChatProviderCommand,isChatProviderDirectory} from './chat-claude';

test('native discovery recognizes private workers without hiding ordinary terminal prompts about their files',()=>{
 const path='/data/chat-sessions/chat-12345678-1234-1234-1234-123456789abc/provider';
 expect(isChatProviderDirectory(path)).toBe(true);
 expect(isChatProviderDirectory(path.replaceAll('/','-'))).toBe(true);
 expect(isChatProviderCommand(`claude --input-format stream-json --system-prompt-file ${path}/instructions.txt`)).toBe(true);
 expect(isChatProviderCommand(`claude --input-format stream-json --append-system-prompt-file ${path}/instructions.txt`)).toBe(true);
 expect(isChatProviderCommand(`claude -- Please explain ${path}/instructions.txt`)).toBe(false);
});

test('coding output accepts tool and MCP cycles but streams only main-conversation prose',()=>{
 const p=new ChatClaudeOutput('coding');
 p.accept({type:'system',subtype:'init',tools:['Read','Bash','Skill','mcp__probe__echo'],mcp_servers:[{name:'probe',status:'connected'}]});
 expect(p.accept({type:'stream_event',event:{type:'content_block_start',content_block:{type:'tool_use',id:'t1',name:'Bash'}}})).toBeUndefined();
 expect(p.accept({type:'stream_event',event:{type:'content_block_delta',delta:{type:'input_json_delta',partial_json:'{"command":"pwd"}'}}})).toBeUndefined();
 expect(p.accept({type:'assistant',message:{content:[{type:'tool_use',id:'t1',name:'Bash',input:{command:'pwd'}}]}})).toBeUndefined();
 expect(p.accept({type:'user',message:{content:[{type:'tool_result',tool_use_id:'t1',content:'PRIVATE_TOOL_OUTPUT'}]}})).toBeUndefined();
 expect(p.accept({type:'stream_event',parent_tool_use_id:'subagent',event:{type:'content_block_delta',delta:{type:'text_delta',text:'Subagent detail'}}})).toBeUndefined();
 expect(p.accept({type:'stream_event',event:{type:'content_block_delta',delta:{type:'thinking_delta',thinking:'Private thought'}}})).toBeUndefined();
 expect(p.accept({type:'stream_event',event:{type:'content_block_delta',delta:{type:'text_delta',text:'Read the file.'}}})).toBe('Read the file.');
 p.accept({type:'result',subtype:'success',result:'Read the file.'});
 expect(p.result).toBe('Read the file.');expect(p.text).toBe('Read the file.');
});

test('coding output still requires initialization and successful bounded results',()=>{
 const p=new ChatClaudeOutput('coding');
 expect(()=>p.accept({type:'result',subtype:'success',result:'Unverified'})).toThrow('initializ');
 p.accept({type:'system',subtype:'init',tools:['Read']});
 expect(()=>p.accept({type:'result',subtype:'error',is_error:true,result:'Tool failed'})).toThrow('Tool failed');
 expect(()=>p.accept({type:'result',subtype:'success',result:'X'.repeat(128001)})).toThrow('size limit');
});

test('chat launch removes tools, customizations, MCP and persistence without putting memory on argv',()=>{
  const args=chatClaudeArgs('/private/context.txt');
  expect(args[args.indexOf('--tools')+1]).toBe('');expect(args).toContain('--safe-mode');
  expect(args).toContain('--strict-mcp-config');expect(args).toContain('--no-session-persistence');
  expect(args).toContain('--system-prompt-file');expect(args.join(' ')).not.toContain('--dangerously-skip-permissions');
});
test('provider must confirm an empty tool set and a successful completed reply',()=>{
  const p=new ChatClaudeOutput();expect(()=>p.accept({type:'system',subtype:'init',tools:['Read']})).toThrow('tools disabled');
  p.accept({type:'system',subtype:'init',tools:[],mcp_servers:[]});
  expect(p.accept({type:'stream_event',event:{type:'content_block_delta',delta:{type:'text_delta',text:'Hello'}}})).toBe('Hello');
  p.accept({type:'result',subtype:'success',result:'Hello'});expect(p.result).toBe('Hello');
  expect(()=>p.accept({type:'result',subtype:'error',is_error:true,result:'Authentication required'})).toThrow('Authentication');
});
test('unexpected tools and unverified text never become chat output',()=>{
  const p=new ChatClaudeOutput();
  expect(()=>p.accept({type:'stream_event',event:{type:'content_block_delta',delta:{type:'text_delta',text:'Hi'}}})).toThrow('before confirming');
  expect(()=>p.accept({type:'assistant',message:{content:[{type:'tool_use',name:'Bash'}]}})).toThrow('tool call');
  expect(()=>p.accept({type:'system',subtype:'init',tools:[],mcp_servers:[{}]})).toThrow('MCP');
});
