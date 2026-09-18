import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from './server.mjs';
let server, base;
before(async()=>{ server=createServer(); await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve)); base=`http://127.0.0.1:${server.address().port}`; });
after(async()=>{ await new Promise(resolve=>server.close(resolve)); });
const meeting=()=>({place:'다리',note:'입구',coordinate:{latitude:35,longitude:135},origin:{latitude:35,longitude:135},target:Date.now()/1000-978307200+3600,mode:'WALK',bufferMinutes:5,friendName:'친구'});
async function request(path,body,token) { const response=await fetch(base+path,{method:body===undefined?'GET':'POST',headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},body:body===undefined?undefined:JSON.stringify(body)}); return {status:response.status,body:await response.json()}; }
async function create(){ return (await request('/sessions',{name:'민지',meeting:meeting()})).body; }
test('two phones exchange confirmed departure and coordinates; end clears both',async()=>{
 const first=await create(); const code=first.session.code;
 const second=(await request('/sessions/join',{name:'지우',code})).body;
 assert.equal(second.session.participants.length,2);
 assert.equal(second.session.participants[0].coordinate,null);
 assert.ok(!JSON.stringify(second.session).includes(first.token));
 let sent=await request(`/sessions/${code}/update`,{phase:'moving',sharingEnabled:true,coordinate:{latitude:35.1,longitude:135.1},eta:Date.now()/1000+600},first.token);
 assert.equal(sent.status,200);
 let state=await request(`/sessions/${code}`,undefined,second.token);
 assert.equal(state.body.participants[0].phase,'moving');
 assert.equal(state.body.participants[0].coordinate.latitude,35.1);
 const ended=await request(`/sessions/${code}/end`,{},second.token);
 assert.equal(ended.body.ended,true); assert.ok(ended.body.participants.every(p=>p.coordinate===null));
 assert.equal((await request(`/sessions/${code}/update`,{phase:'moving'},first.token)).status,409);
});
test('unauthenticated reads and writes are denied',async()=>{ const s=await create(); assert.equal((await request(`/sessions/${s.session.code}`)).status,401); assert.equal((await request(`/sessions/${s.session.code}/end`,{},'wrong')).status,401); });
test('no sharing before departure; arriving removes coordinate',async()=>{ const s=await create(); const path=`/sessions/${s.session.code}/update`; const c={latitude:35,longitude:135}; let r=await request(path,{phase:'free',coordinate:c},s.token); assert.equal(r.body.participants[0].coordinate,null); await request(path,{phase:'moving',sharingEnabled:true,coordinate:c},s.token); r=await request(path,{phase:'arrived',coordinate:c},s.token); assert.equal(r.body.participants[0].coordinate,null); });
test('third participant is rejected',async()=>{ const s=await create(); await request('/sessions/join',{name:'B',code:s.session.code}); assert.equal((await request('/sessions/join',{name:'C',code:s.session.code})).status,409); });
test('reject invalid coordinates, states, meeting dates, and APNs tokens',async()=>{ const m=meeting(); m.target=0; assert.equal((await request('/sessions',{name:'A',meeting:m})).status,400); const s=await create(); const path=`/sessions/${s.session.code}/update`; for (const body of [{phase:'flying'},{phase:'moving',sharingEnabled:true,coordinate:{latitude:100,longitude:0}},{phase:'moving',deviceToken:'injection'},{phase:'moving',eta:'bad'}]) assert.equal((await request(path,body,s.token)).status,400); });
test('unknown code returns useful error',async()=>{ assert.equal((await request('/sessions/join',{name:'B',code:'000000'})).status,404); });
test('a new heartbeat does not refresh an old GPS measurement',async()=>{ const s=await create(); const coordinateUpdatedAt=Date.now()/1000-90; const path=`/sessions/${s.session.code}/update`; await request(path,{phase:'moving',sharingEnabled:true,coordinate:{latitude:35,longitude:135},coordinateUpdatedAt},s.token); const state=await request(`/sessions/${s.session.code}`,undefined,s.token); assert.equal(state.body.participants[0].coordinateUpdatedAt,coordinateUpdatedAt); assert.ok(state.body.participants[0].updatedAt > coordinateUpdatedAt); });

test('free time location sharing is opt-in and can stop without changing status',async()=>{
 const a=await create(); const code=a.session.code; const b=(await request('/sessions/join',{name:'B',code})).body;
 const path=`/sessions/${code}/update`; const coordinate={latitude:37.5,longitude:127.1};
 await request(path,{phase:'free',sharingEnabled:true,coordinate,coordinateUpdatedAt:Date.now()/1000},a.token);
 let received=(await request(`/sessions/${code}`,undefined,b.token)).body.participants[0];
 assert.equal(received.phase,'free'); assert.equal(received.sharingEnabled,true); assert.deepEqual(received.coordinate,coordinate);
 await request(path,{phase:'free',sharingEnabled:false,coordinate},a.token);
 received=(await request(`/sessions/${code}`,undefined,b.token)).body.participants[0];
 assert.equal(received.phase,'free'); assert.equal(received.sharingEnabled,false); assert.equal(received.coordinate,null); assert.equal(received.coordinateUpdatedAt,null);
});
test('arrival can keep explicitly enabled sharing; completion always stops it',async()=>{
 const a=await create(); const path=`/sessions/${a.session.code}`;
 let response=await request(path+'/update',{phase:'arrived',sharingEnabled:true,coordinate:{latitude:37,longitude:127}},a.token);
 assert.equal(response.body.participants[0].sharingEnabled,true); assert.ok(response.body.participants[0].coordinate);
 response=await request(path+'/end',{},a.token);
 assert.ok(response.body.participants.every(p=>!p.sharingEnabled&&p.coordinate===null));
});
