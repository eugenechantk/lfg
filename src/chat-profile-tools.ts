import {ChatSessions,ChatError} from './chat-sessions';
import {text,type McpTool} from './mcp-server';

/** The server binds these tools to one chat; callers cannot supply another id. */
export function chatProfileTools(chats:ChatSessions,id:string):McpTool[]{
 const profile=(session:Awaited<ReturnType<ChatSessions['create']>>)=>({id:session.id,name:session.name,
  instructions:session.instructions,memory:session.memory,model:session.model??'',revision:session.revision});
 return [
  {name:'get_chat_profile',description:'Read this chat’s saved name, standing instructions, memory, model and revision. Empty instructions are normal; never require setup before answering.',
   inputSchema:{type:'object',properties:{}},annotations:{readOnlyHint:true},run:async()=>text(JSON.stringify({profile:profile((await chats.detail(id)).session)}))},
  {name:'update_chat_profile',description:'Save an explicitly user-requested change to this chat’s name, standing instructions, memory or model. Read the current revision first. Supply only requested fields. Never invent instructions or save inferred personal facts. Changes apply to subsequent turns. Confirm only after a saved receipt.',
   inputSchema:{type:'object',properties:{revision:{type:'integer'},name:{type:'string'},
    instructions:{type:'string',description:'Complete standing instructions after applying the requested edit. Preserve unrelated saved instructions; clear them only when explicitly asked.'},
    memory:{type:'string',description:'Complete saved memory after applying the requested edit. Preserve unrelated facts and preferences; remove them only when explicitly asked.'},
    model:{type:'string',description:'Empty uses Claude Default.'}},required:['revision']},run:async args=>{
    const allowed=new Set(['revision','name','instructions','memory','model']);
    if(!args||typeof args!=='object'||Array.isArray(args)||Object.keys(args).some(key=>!allowed.has(key)))throw new ChatError('Supply only this chat’s requested profile fields.');
    if(!Object.keys(args).some(key=>key!=='revision'))throw new ChatError('Choose a profile field to change.');
    return text(JSON.stringify({profile:profile(await chats.updateFromConversation(id,args as {revision:unknown}))}));
   }},
 ];
}
