// Dependency-free PoC relay. Node 20+. Put behind HTTPS for field testing.
import http from 'node:http';
import http2 from 'node:http2';
import { randomBytes, randomInt, createPrivateKey, sign } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const SWIFT_EPOCH = 978307200;
const sessions = new Map();
const attempts = new Map();
const ttl = 12 * 60 * 60 * 1000;
let pushJWT;
function jwt() {
  if (pushJWT && Date.now() - pushJWT.created < 45 * 60 * 1000) return pushJWT.value;
  const { APNS_KEY_ID, APNS_TEAM_ID, APNS_KEY_PATH } = process.env;
  if (!APNS_KEY_ID || !APNS_TEAM_ID || !APNS_KEY_PATH) return null;
  const encode = v => Buffer.from(JSON.stringify(v)).toString('base64url');
  const unsigned = `${encode({ alg: 'ES256', kid: APNS_KEY_ID })}.${encode({ iss: APNS_TEAM_ID, iat: Math.floor(Date.now() / 1000) })}`;
  const signature = sign('sha256', Buffer.from(unsigned), { key: createPrivateKey(readFileSync(APNS_KEY_PATH)), dsaEncoding: 'ieee-p1363' }).toString('base64url');
  pushJWT = { value: `${unsigned}.${signature}`, created: Date.now() }; return pushJWT.value;
}
async function push(token, payload, live = false) {
  const auth = jwt();
  if (!auth || !token) return;
  const topic = (process.env.APNS_BUNDLE_ID || 'com.reunion.poc') + (live ? '.push-type.liveactivity' : '');
  const host = process.env.APNS_ENV === 'production' ? 'https://api.push.apple.com' : 'https://api.sandbox.push.apple.com';
  await new Promise((resolve, reject) => {
    const client = http2.connect(host);
    client.on('error', reject);
    const req = client.request({ ':method': 'POST', ':path': `/3/device/${token}`, authorization: `bearer ${auth}`, 'apns-topic': topic, 'apns-push-type': live ? 'liveactivity' : 'alert', 'apns-priority': '10' });
    req.on('response', headers => { if (headers[':status'] !== 200) console.error('APNs status:', headers[':status']); });
    req.on('data', () => {});
    req.on('end', () => { client.close(); resolve(); });
    req.on('error', error => { client.close(); reject(error); });
    req.setTimeout(10000, () => { req.close(); client.close(); reject(new Error('APNs timeout')); });
    req.end(JSON.stringify(payload));
  });
}
function fail(status, message) { const error = new Error(message); error.status = status; throw error; }
function cleanName(name) { if (typeof name !== 'string' || !name.trim() || name.length > 30) fail(400, '이름은 1~30자로 입력해 주세요.'); return name.trim(); }
function validCoordinate(c) { return c && Number.isFinite(c.latitude) && Number.isFinite(c.longitude) && Math.abs(c.latitude) <= 90 && Math.abs(c.longitude) <= 180; }
function validateMeeting(m) {
  if (!m || typeof m.place !== 'string' || !m.place.trim() || m.place.length > 100 || typeof m.note !== 'string' || m.note.length > 300 || !validCoordinate(m.coordinate) || !validCoordinate(m.origin) || !['WALK','DRIVE','TRANSIT'].includes(m.mode) || !Number.isInteger(m.bufferMinutes) || m.bufferMinutes < 0 || m.bufferMinutes > 60 || !Number.isFinite(m.target) || m.target + SWIFT_EPOCH <= Date.now()/1000 || m.target + SWIFT_EPOCH > Date.now()/1000 + 86400) fail(400, '24시간 이내의 재합류 시간과 유효한 장소를 설정해 주세요.');
}
function participant(name) { return { id: randomBytes(12).toString('hex'), token: randomBytes(32).toString('hex'), name: cleanName(name), phase: 'free', sharingEnabled: false, updatedAt: Date.now()/1000, coordinate: null, coordinateUpdatedAt: null, eta: null }; }
function publicSession(s) { return { code: s.code, meeting: s.meeting, ended: s.ended, participants: s.participants.map(({ id, name, phase, sharingEnabled, coordinate, coordinateUpdatedAt, updatedAt, eta }) => ({ id, name, phase, sharingEnabled, coordinate, coordinateUpdatedAt, updatedAt, eta })) }; }
async function readBody(req) { let body = ''; for await (const chunk of req) { body += chunk; if (body.length > 16384) fail(413, '요청이 너무 큽니다.'); } try { return JSON.parse(body || '{}'); } catch { fail(400, '잘못된 요청입니다.'); } }
function reply(res, status, data) { res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' }); res.end(JSON.stringify(data)); }
export function createServer() {
  return http.createServer(async (req, res) => {
    try {
      const now = Date.now();
      for (const [code,s] of sessions) if (now - s.createdAt > ttl) sessions.delete(code);
      const ip = req.socket.remoteAddress;
      for (const [key,value] of attempts) if (now > value.reset) attempts.delete(key);
      const limit = attempts.get(ip) || { count: 0, reset: now + 60000 }; attempts.set(ip, limit);
      if (++limit.count > 180) fail(429, '요청이 많아요. 잠시 후 다시 시도해 주세요.');
      const path = new URL(req.url, 'http://localhost').pathname;
      if (req.method === 'GET' && path === '/health') return reply(res, 200, { ok: true, pushConfigured: !!(process.env.APNS_KEY_ID && process.env.APNS_TEAM_ID && process.env.APNS_KEY_PATH) });
      if (req.method === 'POST' && path === '/sessions') {
        if (sessions.size >= 1000) fail(503, '현재 테스트 모임이 많아요. 잠시 후 다시 시도해 주세요.');
        const body = await readBody(req); validateMeeting(body.meeting);
        const p = participant(body.name);
        let code; do { code = String(randomInt(100000,1000000)); } while (sessions.has(code));
        const s = { code, meeting: body.meeting, participants: [p], createdAt: now, ended: false }; sessions.set(code,s);
        return reply(res, 201, { session: publicSession(s), participantID: p.id, token: p.token });
      }
      if (req.method === 'POST' && path === '/sessions/join') {
        const body = await readBody(req); const s = sessions.get(body.code);
        if (!s || s.ended) fail(404, '모임 코드가 없거나 종료됐어요.');
        if (s.participants.length >= 2) fail(409, '이미 두 명이 참여한 모임이에요.');
        const p = participant(body.name); s.participants.push(p);
        return reply(res, 200, { session: publicSession(s), participantID: p.id, token: p.token });
      }
      const match = path.match(/^\/sessions\/(\d{6})(?:\/(update|end))?$/);
      if (!match) fail(404, '주소를 찾을 수 없어요.');
      const s = sessions.get(match[1]); if (!s) fail(404, '모임이 만료됐어요. 새 모임을 만들어 주세요.');
      const bearer = req.headers.authorization?.replace(/^Bearer /, '');
      const p = s.participants.find(p => p.token === bearer); if (!p) fail(401, '모임 인증에 실패했어요.');
      if (req.method === 'GET' && !match[2]) return reply(res, 200, publicSession(s));
      if (req.method !== 'POST') fail(405, '지원하지 않는 요청이에요.');
      if (match[2] === 'end') {
        s.ended = true;
        for (const peer of s.participants) {
          if (peer.activityToken) push(peer.activityToken, { aps: { timestamp: Math.floor(now/1000), event: 'end', 'content-state': { status: '재합류 완료', friendStatus: '위치 공유 종료', arrival: now/1000-SWIFT_EPOCH, progress: 1 }, 'dismissal-date': Math.floor(now/1000) } }, true).catch(error=>console.error('End push failed:',error.message));
          peer.coordinate = null; peer.coordinateUpdatedAt = null; peer.sharingEnabled = false; peer.phase = 'complete'; peer.eta = null; peer.deviceToken = null; peer.activityToken = null;
        }
        return reply(res,200,publicSession(s));
      }
      if (match[2] !== 'update') fail(404, '주소를 찾을 수 없어요.');
      if (s.ended) fail(409, '종료된 모임이에요.');
      const body = await readBody(req);
      if (!['free','moving','arrived'].includes(body.phase)) fail(400, '잘못된 이동 상태예요.');
      if (body.sharingEnabled != null && typeof body.sharingEnabled !== 'boolean') fail(400, '잘못된 공유 설정이에요.');
      if (body.coordinate && !validCoordinate(body.coordinate)) fail(400, '잘못된 위치예요.');
      if (body.eta != null && (!Number.isFinite(body.eta) || body.eta < 0)) fail(400, '잘못된 도착시간이에요.');
      for (const field of ['deviceToken','activityToken']) if (body[field] != null && (typeof body[field] !== 'string' || !/^[a-f0-9]{32,512}$/.test(body[field]))) fail(400, '잘못된 알림 토큰이에요.');
      if (body.coordinateUpdatedAt != null && (!Number.isFinite(body.coordinateUpdatedAt) || body.coordinateUpdatedAt < 0 || body.coordinateUpdatedAt > now/1000 + 60)) fail(400, '잘못된 위치 갱신 시각이에요.');
      const departed = p.phase === 'free' && body.phase === 'moving';
      const phaseChanged = p.phase !== body.phase;
      p.phase = body.phase; p.sharingEnabled = body.sharingEnabled === true;
      p.coordinate = p.sharingEnabled ? (body.coordinate || null) : null;
      p.coordinateUpdatedAt = p.coordinate ? (body.coordinateUpdatedAt ?? now/1000) : null;
      p.eta = body.eta ?? null; p.updatedAt = now/1000;
      if (body.deviceToken) p.deviceToken = body.deviceToken;
      if (body.activityToken) p.activityToken = body.activityToken;
      for (const peer of s.participants.filter(peer => peer.id !== p.id)) {
        if (departed) push(peer.deviceToken, { aps: { alert: { title: `${p.name}님이 출발했어요`, body: `${s.meeting.place}에서 다시 만나요. 앱에서 이동 상태를 확인해 주세요.` }, sound: 'default' } }).catch(error => console.error('Push failed:',error.message));
        if (peer.activityToken && (phaseChanged || now - (peer.lastLivePush || 0) >= 20000)) { peer.lastLivePush = now; push(peer.activityToken, { aps: { timestamp: Math.floor(now/1000), event: 'update', 'content-state': { status: peer.phase === 'arrived' ? '도착했어요' : '이동 중', friendStatus: `${p.name} · ${p.phase === 'moving' ? '이동 중' : p.phase === 'arrived' ? '도착' : '자유시간'}`, arrival: (peer.eta || now/1000 + 600) - SWIFT_EPOCH, progress: 0.5 }, 'stale-date': Math.floor(now/1000 + 60) } }, true).catch(error => console.error('Live Activity push failed:',error.message)); }
      }
      return reply(res,200,publicSession(s));
    } catch(error) { reply(res,error.status || 500,{ error: error.status ? error.message : '서버 오류가 발생했어요.' }); }
  });
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const port = Number(process.env.PORT || 8787);
  createServer().listen(port,'0.0.0.0',() => console.log(`Reunion relay on :${port}. Sessions expire after 12h. HTTPS proxy required for field use.`));
}
