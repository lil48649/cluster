import { createClient } from "npm:@supabase/supabase-js@2.57.0";

const url = Deno.env.get("SUPABASE_URL") ?? "";
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const publicOrigin = Deno.env.get("FRONTEND_ORIGIN") ?? "https://lil48649.github.io";
const pepper = Deno.env.get("OTP_PEPPER") ?? "";

export const admin = createClient(url, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

function validOrigin(req: Request): boolean {
  const origin = req.headers.get("origin");
  return !origin || origin === publicOrigin;
}

function headers(req: Request): Headers {
  const h = new Headers({
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "Vary": "Origin",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  });
  const origin = req.headers.get("origin");
  if (origin === publicOrigin) h.set("Access-Control-Allow-Origin", origin);
  return h;
}

export function respond(req: Request, body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: headers(req) });
}

export function preflight(req: Request): Response | null {
  if (!validOrigin(req)) return respond(req, { error: "origin_not_allowed" }, 403);
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: headers(req) });
  if (req.method !== "POST") return respond(req, { error: "method_not_allowed" }, 405);
  return null;
}

// Supabase validates the JWT via Auth and we only read claims after validation.
// Never use an unverified decoded JWT as proof of identity.
export async function getAuthorizedSession(req: Request) {
  const bearer = req.headers.get("authorization") ?? "";
  if (!bearer.startsWith("Bearer ")) return null;
  const token = bearer.slice(7);
  const { data: { user }, error } = await admin.auth.getUser(token);
  if (error || !user || !user.email) return null;

  let sessionId: string;
  try {
    const jwtPart = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    const payload = JSON.parse(atob(jwtPart));
    sessionId = payload.session_id;
    if (payload.sub !== user.id || !/^[0-9a-f-]{36}$/i.test(sessionId)) return null;
  } catch {
    return null;
  }

  const { data: isMember, error: memberError } = await admin.rpc(
    "secure_member_is_active", { p_user_id: user.id }
  );
  if (memberError || isMember !== true) return null;

  return { userId: user.id, email: user.email, sessionId };
}

export async function codeHash(userId: string, sessionId: string, code: string) {
  if (pepper.length < 32) throw new Error("OTP_PEPPER must be set to a long random secret");
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw", encoder.encode(pepper), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]
  );
  const data = encoder.encode(userId + "|" + sessionId + "|" + code);
  const digest = new Uint8Array(await crypto.subtle.sign("HMAC", key, data));
  return Array.from(digest, b => b.toString(16).padStart(2, "0")).join("");
}

export function makeCode(): string {
  // Random six-digit code; use cryptographic randomness server side.
  const bytes = new Uint32Array(1);
  crypto.getRandomValues(bytes);
  return String(bytes[0] % 1_000_000).padStart(6, "0");
}
