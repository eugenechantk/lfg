import { afterEach, expect, test } from 'bun:test';
import { Database } from 'bun:sqlite';
import { SendqStore } from '../sendq-store.ts';
import { setSendqStore, listQueue, __resetSendqForTests } from '../sendq.ts';
import { recoveryClientId } from './recovery.ts';
let store: SendqStore | null = null;
afterEach(()=>{__resetSendqForTests();store?.close();store=null});
test('restart never re-arms a sending recovery, while ordinary pending delivery remains unchanged',()=>{
 __resetSendqForTests();
 store=new SendqStore(new Database(':memory:'));
 const row={sessionId:'fixture',text:'continue',status:'sending' as const,attempts:1,createdAt:100,updatedAt:200};
 store.upsert({...row,id:'recovery',clientId:recoveryClientId('error')});
 store.upsert({...row,id:'ordinary',clientId:'user-client'});
 setSendqStore(store);
 const rows=listQueue('fixture');
 expect(rows.find(r=>r.id==='recovery')?.status).toBe('queued');
 expect(rows.find(r=>r.id==='ordinary')?.status).toBe('pending');
 expect(store.findById('recovery')?.status).toBe('queued');
});
