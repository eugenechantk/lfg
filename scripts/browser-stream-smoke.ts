/** Native acceptance test. Uses only its own disposable window and synthetic text.
 * Run after building the Debug helper: bun scripts/browser-stream-smoke.ts
 */
import { streamHelperPath } from "../src/browser-stream";

const helper = streamHelperPath();
const statusProcess = Bun.spawn([helper,"--status"], {stdout:"pipe",stderr:"ignore"});
const status = JSON.parse(await new Response(statusProcess.stdout).text());
await statusProcess.exited;
if (!status.desktopAllowsInput || !status.screenRecording || !status.accessibility) {
  console.log(JSON.stringify({result:"BLOCKED",reason:"Unlock and wake the Mac and grant helper permissions before native acceptance.",...status}));
  process.exit(2);
}
const wait = (ms:number) => new Promise(r => setTimeout(r,ms));
async function until(predicate:()=>boolean, timeout=20000) {
  const deadline=Date.now()+timeout;
  while (!predicate() && Date.now()<deadline) await wait(100);
  if (!predicate()) throw Error("Timed out waiting for native acceptance state");
}
async function lines(stream:ReadableStream<Uint8Array>,receive:(message:any)=>void) {
  const reader=stream.getReader(); const decoder=new TextDecoder(); let pending="";
  while(true) {
    const {value,done}=await reader.read(); if(done) return;
    pending+=decoder.decode(value,{stream:true});
    let newline:number;
    while((newline=pending.indexOf("\n"))>=0) {
      const line=pending.slice(0,newline);pending=pending.slice(newline+1);
      receive(JSON.parse(line));
    }
  }
}
const fixture=Bun.spawn([helper,"--test-window"],{stdout:"pipe",stderr:"ignore"});
let target=0,clicked=false,typed=false,password=false,frames=0,frameId=0,enabled=false,sequence=0;
void lines(fixture.stdout,m=>{
  if(m.event==="testWindow") target=m.windowId;
  if(m.event==="click") clicked=true;
  if(m.event==="testText"&&m.value==="Hello密碼🙂") typed=true;
  if(m.event==="testPassword"&&m.value==="Ab!23") password=true;
}).catch(()=>{});
let worker:Bun.Subprocess<"pipe","pipe","ignore"> | undefined;
try {
  await until(()=>target>0);
  worker=Bun.spawn([helper,"--stdio"],{stdin:"pipe",stdout:"pipe",stderr:"ignore"});
  const send=(c:any)=>worker!.stdin.write(JSON.stringify(c)+"\n");
  void lines(worker.stdout,m=>{
    if(m.type==="windows") {
      if(!m.windows.some((w:any)=>w.id===target)) throw Error("Fixture missing from capture list");
      send({type:"select",windowId:target});
    }
    if(m.type==="frame"&&m.windowId===target) {frames++;frameId=m.frameId;send({type:"ack",frameId});}
    if(m.type==="control") enabled=m.enabled;
    if(m.type==="error") console.log(JSON.stringify({helperError:m.message}));
  }).catch(e=>console.error(String(e)));
  await until(()=>frames>=3);
  send({type:"control",enabled:true});await until(()=>enabled,5000);
  const input=(c:any)=>send({...c,seq:++sequence,frameId});
  const click=async(x:number,y:number)=>{
    input({type:"pointer",action:"down",button:"left",x,y});
    input({type:"pointer",action:"up",button:"left",x,y});await wait(200);
  };
  // Coordinates are normalized to the fixture's full 800×628 window.
  await click(.18,.664);await until(()=>clicked,3000);
  await click(.3,.371);input({type:"text",text:"Hello密碼🙂"});await until(()=>typed,3000);
  await click(.3,.505);input({type:"text",text:"Ab!23"});await until(()=>password,3000);
  send({type:"control",enabled:false});await until(()=>!enabled,3000);
  console.log(JSON.stringify({result:"PASS",frames,clicked,unicodeText:typed,secureText:password,controlReleased:!enabled}));
} catch(error) {console.error(String(error));process.exitCode=1;}
finally {
  worker?.stdin.end();await wait(300);worker?.kill();fixture.kill();
}
