import { test, expect, afterAll } from "bun:test";
import { mkdtempSync, writeFileSync, chmodSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { configuredCodexModel } from "./model-catalog.ts";
const root = mkdtempSync(join(tmpdir(), "cli-default-protocol-"));
afterAll(() => rmSync(root, { recursive: true, force: true }));
test('Codex in-place Default requests project config and follows each directory rather than catalog suggestion',async()=>{
 const fake=join(root,'codex');const log=join(root,'protocol.jsonl');
 writeFileSync(fake,`#!/usr/bin/env python3
import sys,json
if '--version' in sys.argv:
 print('codex-cli 0.163.0');sys.exit(0)
for line in sys.stdin:
 r=json.loads(line)
 with open(${JSON.stringify(log)},'a') as f:f.write(json.dumps(r)+'\\n')
 method=r.get('method'); result={}
 if method=='config/read':result={'config':{'model':'project-a' if r['params'].get('cwd')=='/repo A' else 'project-b'}}
 if method=='model/list':result={'data':[{'model':'provider-model','isDefault':True},{'model':'project-a'},{'model':'project-b'}]}
 if 'id' in r:print(json.dumps({'id':r['id'],'result':result}),flush=True)
`);chmodSync(fake,0o755);
 const old=process.env.LFG_CODEX_BIN;process.env.LFG_CODEX_BIN=fake;
 try{
  expect(await configuredCodexModel('/repo A')).toBe('project-a');
  expect(await configuredCodexModel('/repo B')).toBe('project-b');
 }finally{if(old===undefined)delete process.env.LFG_CODEX_BIN;else process.env.LFG_CODEX_BIN=old;}
 const records=readFileSync(log,'utf8').trim().split('\n').map(line => JSON.parse(line));
 expect(records.filter(r=>r.method==='config/read').map(r=>r.params.cwd)).toEqual(['/repo A','/repo B']);
 expect(records.some(r=>r.method==='config/write')).toBe(false);
});
test('a config/read protocol failure cannot guess a Default model from provider recommendations',async()=>{
 const fake=join(root,'codex-config-error');
 writeFileSync(fake,`#!/usr/bin/env python3
import sys,json
if '--version' in sys.argv:
 print('codex-cli 0.163.0');sys.exit(0)
for line in sys.stdin:
 r=json.loads(line)
 if 'id' not in r:continue
 if r.get('method')=='config/read':
  print(json.dumps({'id':r['id'],'error':{'code':-32603,'message':'Unable to read project configuration'}}),flush=True);continue
 result={'data':[{'model':'provider-suggestion','isDefault':True}]} if r.get('method')=='model/list' else {}
 print(json.dumps({'id':r['id'],'result':result}),flush=True)
`);chmodSync(fake,0o755);
 const old=process.env.LFG_CODEX_BIN;process.env.LFG_CODEX_BIN=fake;
 try{expect(await configuredCodexModel('/unreadable-project')).toBeNull();}
 finally{if(old===undefined)delete process.env.LFG_CODEX_BIN;else process.env.LFG_CODEX_BIN=old;}
});