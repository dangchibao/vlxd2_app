/* Owner-only setup. Uses the Firebase CLI's existing Google login; never ships
 * IAM credentials, passwords or service-account keys inside the application. */
'use strict';
const path = require('node:path');
const {randomUUID} = require('node:crypto');
const PROJECT = 'vlxd-bayhai-v1-261105';
const STORE = 'shop';
const roles = new Set(['admin','manager','sales','warehouse','driver','station']);
const command = process.argv[2] || 'status';
const username = (process.argv[3] || '').trim().toLowerCase();
const role = process.argv[4];
function email() {
  if (!/^[a-z0-9._-]{3,64}$/.test(username)) throw Error('Tên đăng nhập dùng 3–64 ký tự ASCII hợp lệ.');
  return `${username}+${STORE}@bayhai.invalid`;
}
async function secret() {
  if (!process.stdin.isTTY) {
    let value = process.env.BAYHAI_INITIAL_PASSWORD;
    delete process.env.BAYHAI_INITIAL_PASSWORD;
    if (!value) throw Error('Mở terminal tương tác để nhập mật khẩu ẩn.');
    return value;
  }
  process.stdout.write('Mật khẩu khởi tạo (không hiển thị): ');
  process.stdin.setRawMode(true); process.stdin.resume();
  return new Promise((resolve, reject) => {
    let value = '';
    const handler = chunk => {
      for (const char of chunk.toString('utf8')) {
        if (char === '\u0003') { finish(); reject(Error('Đã hủy.')); return; }
        if (char === '\r' || char === '\n') { finish(); resolve(value); return; }
        if (char === '\u007f' || char === '\b') value = value.slice(0,-1);
        else if (char >= ' ') value += char;
      }
    };
    const finish = () => { process.stdin.removeListener('data',handler); process.stdin.setRawMode(false); process.stdin.pause(); process.stdout.write('\n'); };
    process.stdin.on('data',handler);
  });
}
function fields(data) {
  return Object.fromEntries(Object.entries(data).map(([key, value]) => [key, typeof value === 'boolean' ? {booleanValue:value} : Number.isSafeInteger(value) ? {integerValue:String(value)} : {stringValue:String(value)}]));
}
function decode(data) {
  return Object.fromEntries(Object.entries(data || {}).map(([key,v]) => [key, 'booleanValue' in v ? v.booleanValue : 'integerValue' in v ? Number(v.integerValue) : v.stringValue]));
}
async function main() {
  if (!['status','create','activate','set-role','disable'].includes(command)) throw Error('Lệnh: status | create USER ROLE | activate USER | set-role USER ROLE | disable USER');
  let root;
  try { root = path.dirname(require.resolve('firebase-tools/package.json')); }
  catch { root = path.join(process.env.APPDATA || '', 'npm/node_modules/firebase-tools'); }
  const auth = require(path.join(root,'lib/auth'));
  const options = {project:PROJECT,nonInteractive:true};
  auth.setActiveAccount(options,auth.getGlobalDefaultAccount());
  await require(path.join(root,'lib/requireAuth')).requireAuth(options);
  const token = await require(path.join(root,'lib/apiv2')).getAccessToken();
  // Native fetch deliberately avoids Firebase CLI HTTP body logging for Auth.
  async function api(origin, route, {method='GET',body}={}) {
    const response = await fetch(`https://${origin}/${route}`, {method, headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'}, body:body === undefined ? undefined : JSON.stringify(body), signal:AbortSignal.timeout(30000)});
    if (response.status === 404 && method === 'GET') return null;
    const result = await response.json();
    if (!response.ok) throw Error(`Dịch vụ từ chối (${response.status}). Kiểm tra Auth đã bật và quyền chủ project. Không có thay đổi Billing.`);
    return result;
  }
  const firestoreRoot = `v1/projects/${PROJECT}/databases/(default)/documents`;
  if (command === 'status') {
    const config = await api('identitytoolkit.googleapis.com', `admin/v2/projects/${PROJECT}/config`);
    console.log(JSON.stringify({project:PROJECT,store:STORE,authInitialized:!!config,emailPassword:config?.signIn?.email?.enabled === true})); return;
  }
  const address = email();
  const identity = body => api('identitytoolkit.googleapis.com',`v1/projects/${PROJECT}/accounts:lookup`,{method:'POST',body});
  let user = (await identity({email:[address]})).users?.[0];
  if (command === 'create') {
    if (!roles.has(role)) throw Error('Vai trò không hợp lệ.');
    if (user) throw Error('Tài khoản đã tồn tại; không ghi đè mật khẩu.');
    let password = await secret();
    if (password.length < (role === 'station' ? 20 : 10)) throw Error('Mật khẩu cần ít nhất 10 ký tự, tài khoản trạm ít nhất 20.');
    await api('identitytoolkit.googleapis.com',`v1/projects/${PROJECT}/accounts`,{method:'POST',body:{email:address,password,displayName:username}});
    password = undefined;
    user = (await identity({email:[address]})).users?.[0];
    if (!user?.localId || !Number.isFinite(user.passwordUpdatedAt)) throw Error('Chưa xác minh được tài khoản mới; chạy lại đối chiếu Auth trước khi cấp quyền.');
  } else if (!user?.localId) throw Error('Chưa có tài khoản.');
  const memberPath = `${firestoreRoot}/stores/${STORE}/members/${user.localId}`;
  const previous = await api('firestore.googleapis.com',memberPath);
  const old = decode(previous?.fields);
  let next;
  if (command === 'create') {
    if (previous) throw Error('Membership đã có; không ghi đè.');
    next = {displayName:username,username,role,active:true,mustChangePassword:role !== 'station',bootstrapPasswordUpdatedAt:String(user.passwordUpdatedAt)};
  } else if (command === 'activate') {
    if (!previous || user.disabled || !Number.isFinite(Number(old.bootstrapPasswordUpdatedAt)) || !(Number(user.passwordUpdatedAt) > Number(old.bootstrapPasswordUpdatedAt))) throw Error('Chưa có bằng chứng đổi mật khẩu sau khởi tạo. Không kích hoạt.');
    next = {...old,mustChangePassword:false,activatedAt:new Date().toISOString()};
  } else if (command === 'set-role') {
    if (!previous || !roles.has(role) || role === 'station' || old.role === 'station') throw Error('Không đổi loại tài khoản trạm. Cần membership và vai trò nhân viên hợp lệ.');
    next = {...old,role};
  } else {
    if (!previous) throw Error('Chưa có membership.');
    next = {...old,active:false};
  }
  const auditPath = `${firestoreRoot}/stores/${STORE}/audits/owner-${randomUUID()}`;
  await api('firestore.googleapis.com', `${firestoreRoot}:commit`,{method:'POST',body:{writes:[
    {update:{name:memberPath.replace(/^v1\//,''),fields:fields(next)},currentDocument:previous ? {updateTime:previous.updateTime} : {exists:false}},
    {update:{name:auditPath.replace(/^v1\//,''),fields:fields({action:command,uid:user.localId,occurredAt:new Date().toISOString(),source:'owner-cli'})},currentDocument:{exists:false}},
  ]}});
  console.log(JSON.stringify({project:PROJECT,username,action:command,success:true}));
}
main().catch(() => { console.error('Chưa hoàn tất thao tác. Kiểm tra tên lệnh, quyền Google, Auth và mật khẩu; không ghi log thông tin bí mật.'); process.exitCode=1; });
