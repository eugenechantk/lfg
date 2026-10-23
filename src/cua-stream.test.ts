import { test,expect } from 'bun:test';
import { CuaStream,CuaStreams } from './cua-stream';

test('relay carries video, blocks observer input, and closes both connections',async()=>{
 const received:string[]=[];
 let guestClosed=false;
 const guest=Bun.serve({port:0,hostname:'127.0.0.1',fetch(req,server){return server.upgrade(req)?undefined:new Response('',{status:400});},websocket:{open(ws){ws.send('hello');ws.send(Buffer.from([1,2,3]));},message(_ws,m){received.push(String(m));},close(){guestClosed=true;}}});
 const outbound:any[]=[];let closed=0;let clientClosed=0;
 const stream=new CuaStream(`ws://127.0.0.1:${guest.port}`,()=>closed++);
 const client={getBufferedAmount:()=>0,send:(m:any)=>outbound.push(m),close:()=>clientClosed++} as any;
 try{
  stream.open(client);
  for(let n=0;n<100&&outbound.length<2;n++)await Bun.sleep(5);
  expect(outbound[0]).toBe('hello');expect(outbound[1].byteLength).toBe(3);
  stream.message('{"type":"interactive_input","payload":{"text":"forbidden"}}');
  stream.message('{"type":"frame_ack","payload":{"sequence":9}}');
  for(let n=0;n<100&&received.length<1;n++)await Bun.sleep(5);
  expect(received).toHaveLength(1);expect(JSON.parse(received[0]).type).toBe('frame_ack');
  stream.close();stream.close();
  for(let n=0;n<100&&!guestClosed;n++)await Bun.sleep(5);
  expect(closed).toBe(1);expect(clientClosed).toBe(1);expect(guestClosed).toBe(true);
 }finally{stream.close();guest.stop(true);}
});

test('viewer reservations are bounded and reused tickets never reach the client',async()=>{
 let calls=0;
 const streams=new CuaStreams({call:async()=>{calls++;return {wire_version:2,ws_url:'ws://127.0.0.1:1234/media?ticket=private',ticket_expires_at:new Date(Date.now()+60000).toISOString()};}});
 const a=await streams.prepare('local:owned'),b=await streams.prepare('local:owned');
 await expect(streams.prepare('local:owned')).rejects.toThrow('two viewers');
 expect(calls).toBe(1);
 a.close();const c=await streams.prepare('local:owned');expect(calls).toBe(1);
 b.close();c.close();
});
