import {readFileSync, writeFileSync, mkdtempSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import assert from 'node:assert/strict';
import {normalizeLineMessages, createCodexNormalizationState, recentMessages, messagePage, recentUserTurns, allUserTurns, lastUserPromptText} from '../../../../../src/sessions.ts';
import {reconcileQueuedCore} from '../../../../../src/sendq.ts';
const evidence = JSON.parse(readFileSync(new URL('../replay.json', import.meta.url), 'utf8'));
const raw = readFileSync(evidence.source, 'utf8').split('\n').filter(Boolean).filter(l => Date.parse(JSON.parse(l).timestamp) <= Date.parse(evidence.cutoff));
const records = raw.map(l=>JSON.parse(l));
const actualUsers = records.filter(r=>r.type==='response_item' && r.payload?.role==='user');
const expected = actualUsers.flatMap(r=>r.payload.content.filter((c,i)=>r.payload.internal_chat_message_metadata_passthrough?.content_item_kinds?.[i] === 'user.text').map(c=>({ts:Date.parse(r.timestamp), text:c.text})));
assert.equal(expected.length,4);
const dir=mkdtempSync(join(tmpdir(),'lfg-independent-audit-')); const path=join(dir,'replay.jsonl');
try {
writeFileSync(path,raw.join('\n')+'\n');
const state=createCodexNormalizationState(); const incremental=raw.flatMap(l=>normalizeLineMessages(l,state));
const full=await recentMessages(path,0,{maxBytes:null});
assert.deepEqual(full,incremental);
assert.deepEqual(await recentMessages(path,0,{maxBytes:Buffer.byteLength(raw.join('\n'))+1}),full);
let cursor=null; let paged=[]; do {const page=await messagePage(path,{limit:3,before:cursor}); paged=[...page.messages,...paged];cursor=page.nextBefore;} while(cursor!==null);
assert.deepEqual(paged,full);
assert.deepEqual(full.filter(m=>m.role==='user').map(({ts,text})=>({ts,text})),expected);
assert.deepEqual(await recentUserTurns(path), expected.map(m=>m.text));
assert.deepEqual((await allUserTurns(path)).turns,expected.map(m=>m.text));
assert.equal(await lastUserPromptText(path),expected.at(-1).text);
const queues=[false,true].map(idleConfirmed=>{const queued={id:'audit',clientId:'audit',text:expected[1].text,status:'queued' as const,attempts:1,createdAt:expected[1].ts-1000,updatedAt:expected[1].ts-1000};const result=reconcileQueuedCore([queued],full.filter(m=>m.role==='user').map(m=>m.text),{idleConfirmed,now:Date.parse(evidence.cutoff)});assert.equal(queued.status,'delivered');assert.deepEqual(result,{changed:true,kick:false});return {idleConfirmed,result,status:queued.status};});
console.log(JSON.stringify({source:evidence.source,cutoff:evidence.cutoff,recordCount:records.length,userResponseRecords:actualUsers.map(r=>({timestamp:r.timestamp,kinds:r.payload.internal_chat_message_metadata_passthrough?.content_item_kinds})),userEvents:records.filter(r=>r.type==='event_msg'&&r.payload?.type==='user_message').length,normalizedTimeline:full.map(m=>({role:m.role,ts:m.ts,text:m.text.slice(0,120)})),readerParity:true,queues},null,2));
} finally {rmSync(dir,{recursive:true,force:true});}
