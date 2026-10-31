import {
  admin, codeHash, getAuthorizedSession, makeCode, preflight, respond,
} from "../_shared/otp.ts";

Deno.serve(async (req: Request) => {
  const gate = preflight(req);
  if (gate) return gate;

  try {
    const identity = await getAuthorizedSession(req);
    if (!identity) return respond(req, { error: "unauthorized" }, 403);

    const code = makeCode();
    const hash = await codeHash(identity.userId, identity.sessionId, code);
    const { data: created, error: beginError } = await admin.rpc(
      "secure_begin_email_otp",
      { p_user_id: identity.userId, p_session_id: identity.sessionId, p_code_hash: hash }
    );
    if (beginError) return respond(req, { error: "otp_unavailable" }, 503);
    if (created !== true) return respond(req, { error: "retry_after_60_seconds" }, 429);

    const apiKey = Deno.env.get("RESEND_API_KEY");
    const from = Deno.env.get("OTP_FROM_EMAIL");
    if (!apiKey || !from) return respond(req, { error: "email_delivery_not_configured" }, 503);

    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": "Bearer " + apiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from,
        to: [identity.email],
        subject: "GBD Research Hub · 登录验证码",
        text: "您的科研数据管理平台验证码是：" + code
          + "\n该验证码 5 分钟内有效。若非本人操作，请忽略此邮件。",
      }),
    });

    if (!response.ok) {
      console.error("Email delivery service failed with status", response.status);
      return respond(req, { error: "email_send_failed" }, 502);
    }
    return respond(req, { ok: true, expires_in: 300 });
  } catch (error) {
    console.error("OTP issuance error", error instanceof Error ? error.name : "Unknown");
    return respond(req, { error: "server_error" }, 500);
  }
});
