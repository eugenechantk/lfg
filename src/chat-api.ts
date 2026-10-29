import { ChatSessions, ChatError } from './chat-sessions';

export function chatRoutes(chats:ChatSessions){
  return async(req:Request):Promise<Response|undefined>=>{
    const url=new URL(req.url),path=url.pathname;
    const list=path==='/api/sessions/chats';
    if(path==='/api/sessions/chats/capabilities'&&req.method==='GET')return Response.json({clientChatIDs:true},{headers:{'Cache-Control':'no-store'}});
    const match=path.match(/^\/api\/sessions\/(chat-[^/]+)(?:\/(.*))?$/);
    if(!list&&!match)return;
    const json=(value:unknown,status=200)=>Response.json(value,{status,headers:{'Cache-Control':'no-store'}});
    try{
      const origin=req.headers.get('origin');
      if(req.method!=='GET'&&origin&&origin!==url.origin)throw new ChatError('Cross-origin request refused',403);
      async function body(){
        if(Number(req.headers.get('content-length')??0)>100000)throw new ChatError('Request too large',413);
        const text=await req.text();if(text.length>100000)throw new ChatError('Request too large',413);
        try{const b=JSON.parse(text);if(!b||typeof b!=='object'||Array.isArray(b))throw Error();return b;}
        catch{throw new ChatError('Expected a JSON object');}
      }
      if(list){
        if(req.method==='GET')return json({sessions:await chats.list()});
        if(req.method==='POST'){
          const input=await body();if(input.agent!==undefined&&input.agent!=='claude')throw new ChatError('This chat runner supports Claude.');
          return json({session:await chats.create(input)},201);
        }
        return json({error:'Method not allowed'},405);
      }
      const [,id,action]=match!;
      if(req.method==='GET'&&(!action||action==='messages')){
        return json(await chats.detail(id!,{...(url.searchParams.has('before')?{before:Number(url.searchParams.get('before'))}:{}),...(url.searchParams.has('limit')?{limit:Number(url.searchParams.get('limit'))}:{})}));
      }
      if(req.method==='POST'&&action==='send')return json(await chats.send(id!,await body()),202);
      if(req.method==='POST'&&action==='settings')return json({session:await chats.update(id!,await body())});
      if(req.method==='POST'&&action==='interrupt')return json(await chats.interrupt(id!));
      // A durable chat must never fall through to a terminal kill/resume path.
      return json({error:'This action is not available for a chat session.'},409);
    }catch(error){return json({error:error instanceof ChatError?error.message:'Chat is temporarily unavailable. Your saved conversation has not been removed.'},error instanceof ChatError?error.status:503);}
  };
}
