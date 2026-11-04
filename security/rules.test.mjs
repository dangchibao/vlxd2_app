import {readFile} from 'node:fs/promises';
import {before,after,beforeEach,test} from 'node:test';
import {initializeTestEnvironment,assertSucceeds,assertFails} from '@firebase/rules-unit-testing';
import {doc,setDoc,getDoc,updateDoc,serverTimestamp} from 'firebase/firestore';
if(!process.env.FIRESTORE_EMULATOR_HOST) throw Error('Only run through Firebase Emulator; production is prohibited');
let env;
before(async()=>{env=await initializeTestEnvironment({projectId:'demo-vlxd-bayhai',firestore:{rules:await readFile(new URL('./firestore.rules',import.meta.url),'utf8')}});});
after(async()=>{await env?.cleanup();});
beforeEach(async()=>{await env.clearFirestore();await env.withSecurityRulesDisabled(async context=>{
 for(const [uid,role,active,mustChangePassword] of [['seller','sales',true,false],['boss','manager',true,false],['station','station',true,false],['disabled','sales',false,false],['first','admin',true,true],['driver','driver',true,false]]) {
  await setDoc(doc(context.firestore(),`stores/shop/members/${uid}`),{role,active,mustChangePassword});
 }
});});
const db=uid=>env.authenticatedContext(uid).firestore();
const command=(uid,operation='sale')=>({commandId:'cmd1',actorUid:uid,operation,entityId:'sale1',expectedVersion:0,payload:{},createdAt:serverTimestamp()});
test('Unauthenticated access is denied',async()=>{await assertFails(setDoc(doc(env.unauthenticatedContext().firestore(),'stores/shop/commands/cmd1'),command('seller')));});
test('Seller may create immutable own command, cannot forge actor or role',async()=>{
 const s=db('seller');await assertSucceeds(setDoc(doc(s,'stores/shop/commands/cmd1'),command('seller')));
 await assertFails(updateDoc(doc(s,'stores/shop/commands/cmd1'),{payload:{price:1}}));
 await assertFails(setDoc(doc(s,'stores/shop/commands/forged'),{...command('boss'),commandId:'forged'}));
 await assertFails(updateDoc(doc(s,'stores/shop/members/seller'),{role:'manager'}));
});
test('Seller cannot approve release or directly alter stock, receipts and audit',async()=>{
 const s=db('seller');await assertFails(setDoc(doc(s,'stores/shop/commands/cmd1'),command('seller','release')));
 for(const collection of ['balances','receipts','audits','events']) await assertFails(setDoc(doc(s,`stores/shop/${collection}/x`),{quantity:999}));
});
test('Disabled accounts and first-password accounts are blocked',async()=>{
 for(const uid of ['disabled','first']) await assertFails(setDoc(doc(db(uid),'stores/shop/commands/cmd1'),command(uid)));
});
test('Cross-store reads and commands are denied',async()=>{
 await assertFails(getDoc(doc(db('seller'),'stores/other/balances/x')));
 await assertFails(setDoc(doc(db('seller'),'stores/other/commands/cmd1'),command('seller')));
});
test('Only station can persist canonical result; receipts immutable',async()=>{
 const s=db('station');await assertSucceeds(setDoc(doc(s,'stores/shop/receipts/r1'),{result:'confirmed'}));
 await assertFails(updateDoc(doc(s,'stores/shop/receipts/r1'),{result:'changed'}));
 await assertFails(setDoc(doc(db('boss'),'stores/shop/balances/x'),{quantity:1}));
});
test('Driver cannot read all sales or submit payment command',async()=>{
 await assertFails(getDoc(doc(db('driver'),'stores/shop/documents/sale1')));
 await assertFails(setDoc(doc(db('driver'),'stores/shop/commands/cmd1'),command('driver','payment')));
});
