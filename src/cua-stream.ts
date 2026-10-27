import type { ServerWebSocket } from 'bun';
import type { CuaTools } from './cua-mcp';

/** A view-only relay. Guest tickets stay on the host; input uses guarded HTTP routes. */
export class CuaStream {
 private upstream?: WebSocket;
 private ended = false;
 private client?:ServerWebSocket<any>;
 private timeout?:ReturnType<typeof setTimeout>;
 constructor(private endpoint:string, private didClose:()=>void) {}
 open(client:ServerWebSocket<any>) {
  if(this.ended){client.close(1000);return;}
  this.client=client;
  const source=this.upstream=new WebSocket(this.endpoint,['rcdp.v2']);
  source.binaryType='arraybuffer';
  const timeout=this.timeout=setTimeout(()=>this.close(client,4500,'Space stream did not connect'),15000);
  source.onopen=()=>clearTimeout(timeout);
  source.onmessage=event=>{
   if(this.ended)return;
   // H.264 frames cannot be silently dropped: reconnect from a fresh keyframe
   // if the client cannot keep up, rather than grow an unbounded queue.
   if(client.getBufferedAmount()>2*1024*1024){this.close(client,4500,'Viewer fell behind. Reconnect.');return;}
   try{client.send(event.data);}catch{this.close(client);}
  };
  source.onerror=()=>{clearTimeout(timeout);this.close(client,4500,'Space stream is unavailable');};
  source.onclose=()=>{clearTimeout(timeout);this.close(client,1000,'Space stream ended');};
 }
 message(message:string|Buffer) {
  // Never forward arbitrary remote-desktop actions from an observer socket.
  if(typeof message!=='string'||message.length>2048)return;
  try{
   const value=JSON.parse(message);
   if(['request_keyframe','frame_ack'].includes(value.type)&&this.upstream?.readyState===WebSocket.OPEN)this.upstream.send(message);
  }catch{}
 }
 close(client?:ServerWebSocket<any>,code=1000,reason='') {
  if(this.ended)return;this.ended=true;
  clearTimeout(this.timeout);this.upstream?.close();(client??this.client)?.close(code,reason);this.didClose();
 }
}

export class CuaStreams {
 private viewers=new Map<string,Set<CuaStream>>();
 private endpoints=new Map<string,{url:string;expires:number}>();
 constructor(private cua:CuaTools){}
 async prepare(space:string):Promise<CuaStream>{
  const group=this.viewers.get(space)??new Set<CuaStream>();
  if(group.size>=2)throw Error('This Space already has two viewers. Close another live view first.');
  let endpoint=this.endpoints.get(space);
  if(!endpoint||endpoint.expires<Date.now()+5000){
   const value=await this.cua.call('stream_endpoint',{space,max_fps:15,ticket_ttl:60});
   const result=value?.result??value;
   if(result.wire_version!==2||typeof result.ws_url!=='string')throw Error('Update Cua Spaces to enable live desktop streaming.');
   if(result.needs_gateway_headers)throw Error('This Space requires gateway authentication. Use a local Space for live viewing.');
   const url=new URL(result.ws_url);
   if(!['ws:','wss:'].includes(url.protocol))throw Error('Cua returned an invalid stream endpoint');
   endpoint={url:url.href,expires:Date.parse(result.ticket_expires_at)||Date.now()+55000};
   this.endpoints.set(space,endpoint);
  }
  // Count reservations after async preparation as well.
  const current=this.viewers.get(space)??group;
  if(current.size>=2)throw Error('This Space already has two viewers. Close another live view first.');
  const stream=new CuaStream(endpoint.url,()=>{current.delete(stream);if(!current.size)this.viewers.delete(space);});
  current.add(stream);this.viewers.set(space,current);return stream;
 }
 stop(space:string){for(const stream of this.viewers.get(space)??[])stream.close();this.endpoints.delete(space);}
 hasViewers(space:string){return (this.viewers.get(space)?.size??0)>0;}
}
