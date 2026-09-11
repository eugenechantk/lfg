import { describe, expect, test } from "bun:test";
import { parseStreamCommand, StreamProtocol, BrowserStreamBridge } from "./browser-stream";

describe("browser stream input boundary", () => {
  test("rejects malformed, oversized, non-finite and unbounded input", () => {
    for (const value of ["{", '[]', JSON.stringify({type:"text",text:"x".repeat(5000),seq:1}),
      JSON.stringify({type:"pointer",x:-1,y:0.2,action:"down",seq:1,frameId:1}),
      JSON.stringify({type:"key",key:"shell",seq:1,frameId:1}),
      JSON.stringify({type:"select",windowId:1.5})]) expect(parseStreamCommand(value)).toBeNull();
  });
  test("accepts Unicode text and mouse input without a shell", () => {
    expect(parseStreamCommand(JSON.stringify({type:"text",text:"密碼'$`🙂",seq:1,frameId:3}))).toEqual({type:"text",text:"密碼'$`🙂",seq:1,frameId:3});
    expect(parseStreamCommand(JSON.stringify({type:"pointer",action:"down",button:"left",x:.5,y:.5,seq:2,frameId:3}))).not.toBeNull();
  });
  test("input requires control, a delivered frame and increasing sequence", () => {
    const protocol = new StreamProtocol();
    const input = {type:"text",text:"a",seq:1,frameId:1};
    expect(protocol.accept(input)).toBe(false);
    protocol.frame(1); protocol.accept({type:"control",enabled:true});
    expect(protocol.accept(input)).toBe(true);
    expect(protocol.accept(input)).toBe(false);
    protocol.accept({type:"control",enabled:false});
    expect(protocol.accept({...input,seq:2})).toBe(false);
  });
  test("old frames and selections invalidate control", () => {
    const p = new StreamProtocol(); p.frame(2); p.accept({type:"control",enabled:true});
    expect(p.accept({type:"key",key:"enter",frameId:1,seq:1})).toBe(false);
    p.accept({type:"select",windowId:9});
    expect(p.accept({type:"key",key:"enter",frameId:2,seq:2})).toBe(false);
  });
});

test("bridge holds exclusive owner and releases child on disconnect", () => {
  let stopped = 0;
  const bridge = new BrowserStreamBridge(() => ({write() {}, stop(){stopped++;}}));
  const a = {send(){return 1;},close(){}};
  const b = {send(){return 1;},close(){}};
  expect(bridge.open(a)).toBe(true);
  expect(bridge.open(b)).toBe(false);
  bridge.close(a);
  expect(stopped).toBe(1);
  expect(bridge.open(b)).toBe(true);
  bridge.close(b);
});

test("bridge forwards sanitized input only after control and clears on helper errors", () => {
  const commands: any[] = []; const messages: any[] = [];
  let emit: (line:string)=>void = () => {};
  const bridge = new BrowserStreamBridge((output) => {emit=output;return {write(c){commands.push(c)},stop(){}}});
  const socket = {send(raw:string){messages.push(JSON.parse(raw));return 1},close(){}};
  bridge.open(socket);
  const send = (c:any) => bridge.message(socket,JSON.stringify(c));
  send({type:"text",text:"hidden",seq:1,frameId:1});
  expect(commands).toHaveLength(0);
  emit(JSON.stringify({type:"frame",frameId:1,jpeg:"AA=="}));
  send({type:"control",enabled:true});
  send({type:"text",text:"test",seq:2,frameId:1,ignored:"drop"});
  expect(commands.at(-1)).toEqual({type:"text",text:"test",seq:2,frameId:1});
  emit(JSON.stringify({type:"control",enabled:false}));
  send({type:"text",text:"blocked",seq:3,frameId:1});
  expect(commands).toHaveLength(2);
  bridge.close(socket);
});

test("overspeed input closes the lease instead of accumulating subprocess work", () => {
  let stopped=0, closed=0;
  const bridge = new BrowserStreamBridge(()=>({write(){},stop(){stopped++}}));
  const socket={send(){return 1},close(){closed++}};
  bridge.open(socket);
  for(let i=0;i<130;i++) bridge.message(socket,'{"type":"ping"}');
  expect(stopped).toBe(1); expect(closed).toBe(1);
});
