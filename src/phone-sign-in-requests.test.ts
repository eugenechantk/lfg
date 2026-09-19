import {test, expect} from 'bun:test';
import {PhoneSignInRequests} from './phone-sign-in-requests.ts';
const sid='11111111-1111-4111-8111-111111111111';
const target={id:'exact-browser',name:'Chrome personal',kind:'chrome' as const};
const create={sessionId:sid,targetId:target.id,url:'https://portal.example.com/login'};
const cookies=[{name:'session',value:'synthetic',domain:'.example.com'}, {name:'sso',value:'synthetic',domain:'id.example.net'}];
test('request pins exact browser/url, deduplicates and reserves target across sessions',()=>{
 const h=new PhoneSignInRequests({targets:()=>[target],transfer:async()=>({state:'installed',installed:2,total:2})});
 const r=h.create(create);expect(h.create(create).id).toBe(r.id);
 expect(()=>h.create({...create,sessionId:'22222222-2222-4222-8222-222222222222'})).toThrow('already');
 expect(h.list(sid)).toHaveLength(1);expect(h.list('other')).toHaveLength(0);
 expect(()=>h.create({...create,targetId:'wrong'})).toThrow('offline');
});
test('Done transfers every session domain to pinned target once, then exposes only metadata',async()=>{
 const sent:any[]=[];
 const h=new PhoneSignInRequests({targets:()=>[target],transfer:async p=>{sent.push(p);return {state:'installed',installed:2,total:2}}});
 const r=h.create(create);const done=await h.complete(r.id,cookies);
 expect(done.state).toBe('installed');expect(sent[0]).toEqual({targetId:target.id,url:create.url,domains:['example.com','id.example.net'],cookies});
 await h.complete(r.id,cookies);expect(sent).toHaveLength(1);expect(JSON.stringify(h.get(r.id))).not.toContain('synthetic');
});
test('cancel, expiry, reconnect and concurrent Done cannot redirect or replay credentials',async()=>{
 let now=1000,online=true,finish:any;let calls=0;
 const h=new PhoneSignInRequests({targets:()=>online?[target]:[],transfer:()=>{calls++;return new Promise(r=>finish=r)}},()=>now,100);
 const a=h.create(create);h.cancel(a.id);expect((await h.complete(a.id,cookies)).state).toBe('cancelled');
 const b=h.create(create);now=1101;expect(h.get(b.id)?.state).toBe('expired');
 const c=h.create(create);online=false;expect(h.get(c.id)?.state).toBe('offline');online=true;
 const d=h.create(create);const waiting=h.complete(d.id,cookies);expect((await h.complete(d.id,cookies)).state).toBe('delivering');expect(()=>h.cancel(d.id)).toThrow('progress');
 finish({state:'unknown',installed:0,total:2});expect((await waiting).state).toBe('unknown');expect(calls).toBe(1);
});

test('HTTP create requires local agent token; requests survive only in host memory',async()=>{
 const {BrowserSignInHub,signInHTTP}=await import('./browser-sign-in.ts');
 const h=new BrowserSignInHub(()=> 'a'.repeat(64));
 const req=(headers:any={})=>new Request('http://localhost/api/browser-sign-in/requests',{method:'POST',headers:{'Content-Type':'application/json',...headers},body:JSON.stringify(create)});
 expect((await signInHTTP(req(),h)).status).toBe(403);
 expect((await signInHTTP(req({Authorization:'Bearer '+'a'.repeat(64),Origin:'https://evil.example'}),h)).status).toBe(403);
 expect((await signInHTTP(req({Authorization:'Bearer '+'a'.repeat(64),'cf-connecting-ip':'1.2.3.4'}),h)).status).toBe(403);
 expect((await signInHTTP(new Request('http://localhost/api/browser-sign-in/requests/11111111-1111-4111-8111-111111111111'),h)).status).toBe(404);
 h.dispose();
});

test('session history retains terminal requests newest first without replay',async()=>{
 let now=1000;
 const h=new PhoneSignInRequests({targets:()=>[target],transfer:async()=>({state:'installed',installed:2,total:2})},()=>now,100);
 const a=h.create(create);await h.complete(a.id,cookies);now=2000;
 const b=h.create(create);h.cancel(b.id);now=3000;
 const c=h.create({...create,sessionId:'22222222-2222-4222-8222-222222222222'});
 expect(h.list(sid).map(r=>r.id)).toEqual([b.id,a.id]);
 expect(h.list(sid).map(r=>r.state)).toEqual(['cancelled','installed']);
 expect(h.list(c.sessionId).map(r=>r.id)).toEqual([c.id]);
});

test('history persists only bounded metadata; restart expires pending and never replays',async()=>{
 const {mkdtempSync,readFileSync,statSync,rmSync}=await import('node:fs');
 const {tmpdir}=await import('node:os');const {join}=await import('node:path');
 const dir=mkdtempSync(join(tmpdir(),'lfg-history-test-'));const file=join(dir,'history.json');
 let now=1000;let calls=0;
 const backend={targets:()=>[target],transfer:async()=>{calls++;return {state:'installed' as const,installed:2,total:2}}};
 try {
  const h=new PhoneSignInRequests(backend,()=>now,100,file);
  const a=h.create({...create,url:'https://portal.example.com/secret-path?code=secret-query#secret-fragment'});
  await h.complete(a.id,cookies);now++;
  const b=h.create(create);
  const raw=readFileSync(file,'utf8');
  for(const secret of ['synthetic','secret-path','secret-query','secret-fragment','"cookies"']) expect(raw).not.toContain(secret);
  expect(statSync(file).mode & 0o777).toBe(0o600);
  const restored=new PhoneSignInRequests(backend,()=>now,100,file);
  expect(restored.list(sid).map(r=>r.state)).toEqual(['expired','installed']);
  expect((await restored.complete(b.id,cookies)).state).toBe('expired');expect(calls).toBe(1);
  for(let i=0;i<140;i++){now++;const r=restored.create(create);restored.cancel(r.id);}
  expect(restored.list(sid)).toHaveLength(128);
  expect(JSON.parse(readFileSync(file,'utf8'))).toHaveLength(128);
 } finally {rmSync(dir,{recursive:true,force:true});}
});

test('restart during delivery preserves unconfirmed history and does not resend',async()=>{
 const {mkdtempSync,rmSync}=await import('node:fs');const {tmpdir}=await import('node:os');const {join}=await import('node:path');
 const dir=mkdtempSync(join(tmpdir(),'lfg-delivery-history-'));const file=join(dir,'history.json');
 let finish:any;let calls=0;
 const backend={targets:()=>[target],transfer:()=>{calls++;return new Promise<any>(resolve=>finish=resolve)}};
 try {
  const h=new PhoneSignInRequests(backend,Date.now,1000,file);const r=h.create(create);
  const delivery=h.complete(r.id,cookies);
  const restarted=new PhoneSignInRequests(backend,Date.now,1000,file);
  expect(restarted.list(sid)[0]?.state).toBe('unknown');
  expect((await restarted.complete(r.id,cookies)).state).toBe('unknown');expect(calls).toBe(1);
  finish({state:'unknown',installed:0,total:2});await delivery;
 } finally {rmSync(dir,{recursive:true,force:true});}
});

test('phoneSignInPrompt surfaces only a waiting request as a needs-input prompt, newest first',()=>{
 const {phoneSignInPrompt}=require('./phone-sign-in-requests.ts');
 let now=1000;
 const h=new PhoneSignInRequests({targets:()=>[target],transfer:async()=>({state:'installed',installed:1,total:1})},()=>now,100);
 expect(phoneSignInPrompt(h,sid)).toBeNull();
 expect(phoneSignInPrompt(h,'not-a-uuid')).toBeNull();
 const r=h.create(create);
 const p=phoneSignInPrompt(h,sid);
 expect(p).toMatchObject({source:'phone-sign-in',question:'Sign in to portal.example.com on your iPhone',header:'Sign in',options:[],
  signIn:{requestId:r.id,url:create.url,website:'portal.example.com',targetName:target.name,expiresAt:r.expiresAt}});
 expect(JSON.stringify(p)).not.toContain('cookie');
 expect(phoneSignInPrompt(h,'22222222-2222-4222-8222-222222222222')).toBeNull();
 h.cancel(r.id);expect(phoneSignInPrompt(h,sid)).toBeNull();
 const b=h.create(create);now=1101;expect(h.get(b.id)?.state).toBe('expired');expect(phoneSignInPrompt(h,sid)).toBeNull();
 now=1200;const c=h.create(create);const done=h.complete(c.id,cookies);expect(phoneSignInPrompt(h,sid)).toBeNull();
 return done;
});

test('a transfer that never reaches the browser reports why', async () => {
 const h=new PhoneSignInRequests({targets:()=>[target],transfer:async()=>{throw Error('Browser is offline. Reconnect and select it again.')}});
 const create=h.create({sessionId:sid,targetId:target.id,url:'https://portal.example.com/login'});
 const done=await h.complete(create.id,cookies);
 expect(done.state).toBe('failed');
 expect(done.result).toEqual({state:'failed',installed:0,total:cookies.length,reason:'Browser is offline. Reconnect and select it again.'});
 expect(h.get(create.id)?.result?.reason).toBe('Browser is offline. Reconnect and select it again.');
});
