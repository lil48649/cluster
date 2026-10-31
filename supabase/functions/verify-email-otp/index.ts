import {
  admin, codeHash, getAuthorizedSession, preflight, respond,
} from "../_shared/otp.ts";

Deno.serve(async (req: Request) => {
  const gate = preflight(req);
  if (gate) return gate;

  try {
    const identity = await getAuthorizedSession(req);
    if (!identity) return respond(req, { error: "unauthorized" }, 403);

    const body = await req.json().catch(() => ({}));
    const code = String(body.code ?? "").trim();
    if (!/^[0-9]{6}$/.test(code)) {
      return respond(req, { error: "invalid_otp_format" }, 400);
    }
    const hash = await codeHash(identity.userId, identity.sessionId, code);
    const { data: verified, error } = await admin.rpc(
      "secure_verify_email_otp",
      { p_user_id: identity.userId, p_session_id: identity.sessionId, p_code_hash: hash }
    );
    if (error) return respond(req, { error: "otp_verification_unavailable" }, 503);
    if (verified !== true) return respond(req, { error: "otp_invalid_or_expired" }, 403);
    return respond(req, { ok: true, authorized_for_seconds: 1800 });
  } catch (error) {
    console.error("OTP verification error", error instanceof Error ? error.name : "Unknown");
    return respond(req, { error: "server_error" }, 500);
  }
});
