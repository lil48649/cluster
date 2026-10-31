/*
 * Real server-side authorization flow:
 * 1) Supabase Auth verifies per-user EMAIL + PASSWORD.
 * 2) Edge Functions email a short-lived OTP and verify it on the server.
 * 3) Postgres RLS checks verified USER + SESSION before Storage allows reading.
 * This frontend never contains a shared password, email API secret or service key.
 */
(function () {
  "use strict";

  const cfg = window.GBD_SECURE_CONFIG || {};
  const storageKey = "gbd-secure-v1";
  const idleMs = 15 * 60 * 1000;
  const $ = (id) => document.getElementById(id);

  let session = null;
  let otpEmail = "";
  let lastActivity = Date.now();
  let appLoaded = false;
  let keepSession = false;

  const ready = /^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(cfg.url || "")
    && !!cfg.publishableKey
    && !String(cfg.publishableKey).startsWith("SET_");

  function errorMessage(err) {
    return err && (err.msg || err.error_description || err.message || err.error) || "网络或服务器错误";
  }

  function showError(id, value) {
    $(id).textContent = value;
  }

  function clearSession() {
    session = null;
    try { sessionStorage.removeItem(storageKey); } catch (_) {}
  }

  function saveSession() {
    if (!keepSession || !session) return;
    try {
      sessionStorage.setItem(storageKey, JSON.stringify({
        session, lastActivity, keepSession: true
      }));
    } catch (_) {}
  }

  function setSession(json) {
    session = {
      access_token: json.access_token,
      refresh_token: json.refresh_token,
      expires_at: Date.now() + (Number(json.expires_in) || 3600) * 1000,
    };
    lastActivity = Date.now();
    saveSession();
  }

  async function request(path, options = {}, token = null) {
    const headers = {
      "apikey": cfg.publishableKey,
      "Content-Type": "application/json",
      ...(token ? { "Authorization": "Bearer " + token } : {}),
      ...(options.headers || {}),
    };
    const response = await fetch(cfg.url + path, { ...options, headers, cache: "no-store" });
    if (options.raw) return response;
    const json = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(errorMessage(json));
    return json;
  }

  async function ensureAccessToken() {
    if (!session) throw new Error("登录状态已失效，请重新登录。");
    if (session.expires_at - Date.now() > 60000) return session.access_token;
    const json = await request("/auth/v1/token?grant_type=refresh_token", {
      method: "POST", body: JSON.stringify({ refresh_token: session.refresh_token }),
    });
    setSession(json);
    return session.access_token;
  }

  async function secureRequest(path, options = {}) {
    const token = await ensureAccessToken();
    return request(path, options, token);
  }

  async function isOtpVerified() {
    const approved = await secureRequest("/rest/v1/rpc/secure_has_verified_otp", {
      method: "POST", body: "{}",
    });
    return approved === true;
  }

  // Public app.js calls this function. Storage enforces RLS on EVERY request.
  window.GBD_SECURE_FETCH = async function () {
    if (!(await isOtpVerified())) {
      throw new Error("二次验证已过期，请重新登录。");
    }
    const token = await ensureAccessToken();
    const response = await request(
      "/storage/v1/object/authenticated/" +
        encodeURIComponent(cfg.bucket) + "/" + encodeURIComponent(cfg.objectPath),
      { method: "GET", raw: true }, token
    );
    if (response.status === 401 || response.status === 403) {
      throw new Error("私有数据访问被拒绝，请检查项目组授权或重新登录。");
    }
    return response;
  };

  function openPortal() {
    if (appLoaded) return;
    appLoaded = true;
    document.documentElement.classList.add("authenticated");
    $("loginPassword").value = "";
    $("challengeInput").value = "";
    const script = document.createElement("script");
    script.src = "app.js?v=secure-1";
    script.onerror = function () {
      appLoaded = false;
      document.documentElement.classList.remove("authenticated");
      showError("loginError", "科研数据界面载入失败，请检查文件。");
    };
    document.body.appendChild(script);
  }

  function showOtpForm() {
    $("loginForm").hidden = true;
    $("secondFactorForm").hidden = false;
    $("challengeInput").value = "";
    $("challengeInput").focus();
  }

  async function requestOtp() {
    await secureRequest("/functions/v1/send-email-otp", {
      method: "POST", body: "{}",
    });
  }

  function loginUIReset() {
    $("loginForm").hidden = false;
    $("secondFactorForm").hidden = true;
    $("loginPassword").value = "";
  }

  async function signOut() {
    try {
      if (session) {
        const token = await ensureAccessToken();
        await request("/rest/v1/rpc/secure_revoke_own_otp",
          { method: "POST", body: "{}" }, token);
        await request("/auth/v1/logout",
          { method: "POST", body: "{}" }, token);
      }
    } catch (_) {
      // Clear local access even if server is temporarily unreachable.
    } finally {
      clearSession();
      location.reload();
    }
  }

  $("loginForm").addEventListener("submit", async function (e) {
    e.preventDefault();
    if (!ready) {
      showError("loginError", "云端服务尚未配置。请先按照安全部署指南完成设置。");
      return;
    }
    if ($("loginRole").value !== "project") {
      showError("loginError", "请选择项目组角色。");
      return;
    }
    const email = $("loginUsername").value.trim().toLowerCase();
    const password = $("loginPassword").value;
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || !password) {
      showError("loginError", "请填写已授权邮箱和个人登录密码。");
      return;
    }
    const button = $("loginSubmit");
    button.disabled = true;
    showError("loginError", "");
    try {
      const result = await request("/auth/v1/token?grant_type=password", {
        method: "POST", body: JSON.stringify({ email, password }),
      });
      keepSession = $("rememberSession").checked;
      setSession(result);
      otpEmail = email;
      await requestOtp();
      showOtpForm();
    } catch (err) {
      showError("loginError", "身份验证或发送验证码失败：" + errorMessage(err));
      clearSession();
    } finally {
      button.disabled = false;
    }
  });

  $("secondFactorForm").addEventListener("submit", async function (e) {
    e.preventDefault();
    const code = $("challengeInput").value.trim();
    if (!/^\d{6}$/.test(code)) {
      showError("challengeError", "请输入邮件中的6位数字验证码。");
      return;
    }
    const button = $("secondFactorSubmit");
    button.disabled = true;
    showError("challengeError", "");
    try {
      const result = await secureRequest("/functions/v1/verify-email-otp", {
        method: "POST", body: JSON.stringify({ code }),
      });
      if (!result.ok || !(await isOtpVerified())) throw new Error("二次验证未获授权");
      saveSession();
      openPortal();
    } catch (err) {
      showError("challengeError", "验证码不正确、已过期或服务器拒绝授权。");
      $("challengeInput").value = "";
    } finally {
      button.disabled = false;
    }
  });

  $("refreshChallenge").addEventListener("click", async function () {
    try {
      await requestOtp();
      showError("challengeError", "已重新发送验证码，请查看邮箱（每60秒仅能申请一次）。");
    } catch (err) {
      showError("challengeError", "暂时无法重发，请间隔60秒后再试。");
    }
  });

  $("returnToLogin").addEventListener("click", async function () {
    await signOut();
  });

  $("togglePassword").addEventListener("click", function () {
    const control = $("loginPassword");
    const visible = control.type === "password";
    control.type = visible ? "text" : "password";
    this.textContent = visible ? "隐藏" : "显示";
    this.setAttribute("aria-pressed", String(visible));
  });

  $("logoutBtn").addEventListener("click", signOut);

  for (const event of ["pointerdown", "keydown", "scroll"]) {
    window.addEventListener(event, () => {
      if (session) {
        if (Date.now() - lastActivity > idleMs) {
          signOut();
        } else {
          lastActivity = Date.now();
          saveSession();
        }
      }
    }, { passive: true });
  }
  setInterval(() => {
    if (session && Date.now() - lastActivity > idleMs) signOut();
  }, 30000);

  (async function init() {
    if (!ready) {
      showError("loginError", "管理员尚未完成私有数据云端配置，此开发版本暂不能登录。");
      return;
    }
    try {
      const stored = JSON.parse(sessionStorage.getItem(storageKey) || "null");
      if (!stored || !stored.session || Date.now() - stored.lastActivity > idleMs) {
        clearSession();
        return;
      }
      session = stored.session;
      keepSession = true;
      lastActivity = stored.lastActivity;
      if (await isOtpVerified()) {
        openPortal();
      } else {
        clearSession();
        loginUIReset();
      }
    } catch (_) {
      clearSession();
      loginUIReset();
    }
  })();
})();
