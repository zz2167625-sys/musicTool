// zephyr 登录校验接口（Edge Function）
//
// POST /functions/v1/app/auth   body: {"username": "...", "password": "..."}
//   200 {"ok": true}                     校验通过
//   401 {"ok": false, ...}               账号或密码错误
//   429 {"ok": false, ...}               尝试次数过多（每 IP 10 分钟内 8 次失败封锁 15 分钟）
//   503 {"ok": false, ...}               服务端未配置凭据（Secret 缺失）
//
// 凭据存放在站点 Secret（APP_LOGIN_USER / APP_LOGIN_PASS），
// 不进入源码、构建产物或任何客户端文件。

const MAX_FAILS = 8;
const WINDOW_MS = 10 * 60 * 1000;
const BLOCK_MS = 15 * 60 * 1000;
const MAX_BODY = 4096;
const MAX_ENTRIES = 2000;

interface Attempt {
  fails: number;
  windowStart: number;
  blockedUntil: number;
}

const attempts = new Map<string, Attempt>();

async function sha256Hex(text: string): Promise<string> {
  const bytes = new TextEncoder().encode(text);
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(hash)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function clientIp(request: Request): string {
  const fwd = request.headers.get("x-forwarded-for") ?? "";
  const first = fwd.split(",")[0]?.trim();
  return first && first !== "unknown" ? first : "unknown";
}

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function rateCheck(ip: string): Response | null {
  const now = Date.now();
  const entry = attempts.get(ip);
  if (entry && entry.blockedUntil > now) {
    return json(429, { ok: false, error: "too_many_attempts" });
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

function recordFail(ip: string): void {
  const entry = attempts.get(ip);
  if (!entry) return;
  entry.fails += 1;
  if (entry.fails >= MAX_FAILS) {
    entry.blockedUntil = Date.now() + BLOCK_MS;
  }
}

async function handleAuth(request: Request): Promise<Response> {
  if (request.method !== "POST") {
    return new Response(null, { status: 405, headers: { allow: "POST" } });
  }
  const ip = clientIp(request);
  const blocked = rateCheck(ip);
  if (blocked) return blocked;

  const expectUser = Deno.env.get("APP_LOGIN_USER");
  const expectPass = Deno.env.get("APP_LOGIN_PASS");
  if (!expectUser || !expectPass) {
    return json(503, { ok: false, error: "service_not_configured" });
  }

  const contentLength = Number(request.headers.get("content-length") ?? 0);
  if (!Number.isFinite(contentLength) || contentLength > MAX_BODY) {
    return json(413, { ok: false, error: "payload_too_large" });
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return json(400, { ok: false, error: "invalid_request" });
  }
  const record = body as { username?: unknown; password?: unknown };
  const user = typeof record?.username === "string" ? record.username : "";
  const pass = typeof record?.password === "string" ? record.password : "";
  if (
    !user || !pass || user.length > 64 || pass.length > 128
  ) {
    recordFail(ip);
    return json(401, { ok: false, error: "invalid_credentials" });
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
    return json(401, { ok: false, error: "invalid_credentials" });
  }

  attempts.delete(ip);
  return json(200, { ok: true });
}

function handle(request: Request): Response | Promise<Response> {
  const url = new URL(request.url);
  if (url.pathname.endsWith("/auth")) {
    return handleAuth(request);
  }
  return json(404, { ok: false, error: "not_found" });
}

Deno.serve(handle);
