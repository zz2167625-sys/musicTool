// zephyr 登录校验接口（Cloudflare Workers 版）
//
// 部署步骤（免费）：
// 1. 注册 https://dash.cloudflare.com 并进入 Workers & Pages → 创建 Worker
// 2. 把本文件内容粘贴到代码编辑器，点击「部署」
// 3. Worker 设置 → 变量和机密 → 添加两个「机密」（Secret）：
//    LOGIN_USER = 你的账号名
//    LOGIN_PASS = 你的密码
// 4. 复制 Worker 地址（如 https://zephyr-auth.你的子域.workers.dev），
//    填入 App 的 AppInfo.authUrl（后面拼 /auth，最终形如
//    https://xxx.workers.dev/auth），重新构建 APK 即可
//
// 接口：POST /auth  {"username": "...", "password": "..."}
//   200 通过 / 401 凭据错误 / 429 尝试过多 / 503 未配置机密

const MAX_FAILS = 8;
const WINDOW_MS = 10 * 60 * 1000;
const BLOCK_MS = 15 * 60 * 1000;
const MAX_BODY = 4096;
const MAX_ENTRIES = 2000;

const attempts = new Map();

function json(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

async function sha256Hex(text) {
  const bytes = new TextEncoder().encode(text);
  const hash = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(hash)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

function clientIp(request) {
  const fwd = request.headers.get('cf-connecting-ip') || '';
  return fwd || 'unknown';
}

function rateCheck(ip) {
  const now = Date.now();
  const entry = attempts.get(ip);
  if (entry && entry.blockedUntil > now) {
    return json(429, { ok: false, error: 'too_many_attempts' });
  }
  if (!entry || now - entry.windowStart > WINDOW_MS) {
    attempts.set(ip, { fails: 0, windowStart: now, blockedUntil: 0 });
  }
  if (attempts.size > MAX_ENTRIES) {
    for (const [key, value] of attempts) {
      if (now - value.windowStart > WINDOW_MS + BLOCK_MS) attempts.delete(key);
    }
  }
  return null;
}

function recordFail(ip) {
  const entry = attempts.get(ip);
  if (!entry) return;
  entry.fails += 1;
  if (entry.fails >= MAX_FAILS) {
    entry.blockedUntil = Date.now() + BLOCK_MS;
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname.endsWith('/update.json')) {
      const upstream =
        'https://raw.githubusercontent.com/zz2167625-sys/musicTool/main/update.json';
      try {
        const resp = await fetch(upstream, { cf: { cacheTtl: 300 } });
        return new Response(resp.body, {
          status: resp.status,
          headers: {
            'content-type': 'application/json',
            'cache-control': 'public, max-age=300',
          },
        });
      } catch {
        return json(502, { ok: false, error: 'upstream_unavailable' });
      }
    }
    if (!url.pathname.endsWith('/auth')) {
      return json(404, { ok: false, error: 'not_found' });
    }
    if (request.method !== 'POST') {
      return new Response(null, { status: 405, headers: { allow: 'POST' } });
    }
    const ip = clientIp(request);
    const blocked = rateCheck(ip);
    if (blocked) return blocked;

    const expectUser = env.LOGIN_USER || '';
    const expectPass = env.LOGIN_PASS || '';
    if (!expectUser || !expectPass) {
      return json(503, { ok: false, error: 'service_not_configured' });
    }

    const contentLength = Number(request.headers.get('content-length') || 0);
    if (!Number.isFinite(contentLength) || contentLength > MAX_BODY) {
      return json(413, { ok: false, error: 'payload_too_large' });
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return json(400, { ok: false, error: 'invalid_request' });
    }
    const user = typeof body?.username === 'string' ? body.username : '';
    const pass = typeof body?.password === 'string' ? body.password : '';
    if (!user || !pass || user.length > 64 || pass.length > 128) {
      recordFail(ip);
      return json(401, { ok: false, error: 'invalid_credentials' });
    }

    const [userHash, passHash, expectUserHash, expectPassHash] =
      await Promise.all([
        sha256Hex(user),
        sha256Hex(pass),
        sha256Hex(expectUser),
        sha256Hex(expectPass),
      ]);
    if (userHash !== expectUserHash || passHash !== expectPassHash) {
      recordFail(ip);
      return json(401, { ok: false, error: 'invalid_credentials' });
    }

    attempts.delete(ip);
    return json(200, { ok: true });
  },
};
