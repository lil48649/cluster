/*
 * GBD Research Hub: Supabase-managed MFA using native TOTP factors.
 * Password and 6-digit TOTP are verified by Supabase Auth, not browser code.
 * Private object Storage RLS requires project membership, current session,
 * and AAL2 with a verified TOTP factor. Never publish secret API keys.
 */
(function () {
  "use strict";

  const cfg = window.GBD_SECURE_CONFIG || {};
  const sessionKey = "gbd-native-totp-session-v2";
  const idleMs = 15 * 60 * 1000;
  const $ = (id) => document.getElementById(id);
  const ready = /^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(cfg.url || "") &&
    /^sb_publishable_/.test(cfg.publishableKey || "");
  let session = null;
  let keepSession = false;
  let lastActivity = Date.now();
  let lastSave = 0;
  let activeFactorId = "";
  let pendingEnrollment = false;
  let appLoaded = false;
  let busyLogout = false;

  function errText(value) {
    return String(value && (value.msg || value.error_description || value.message || value.error) || "网络或服务器错误");
  }

  function showError(id, value) {
    $(id).textContent = value;
  }

  function clearSession() {
    session = null;
    try { sessionStorage.removeItem(sessionKey); } catch (_) {}
  }

  function saveSession() {
    if (!keepSession || !session) return;
    try {
      sessionStorage.setItem(sessionKey, JSON.stringify({ session, lastActivity }));
      lastSave = Date.now();
    } catch (_) {}
  }

  function setSession(data) {
    const s = data && (data.session || data);
    if (!s || typeof s.access_token !== "string" || typeof s.refresh_token !== "string") {
      throw new Error("身份验证未返回完整会话，请重新登录。");
    }
    session = {
      access_token: s.access_token,
      refresh_token: s.refresh_token,
      expires_at: Date.now() + (Number(s.expires_in) || 3600) * 1000
    };
    lastActivity = Date.now();
    saveSession();
  }

  async function request(path, opts, token) {
    const options = opts || {};
    const headers = {
      "apikey": cfg.publishableKey,
      "Content-Type": "application/json",
      ...(token ? { Authorization: "Bearer " + token } : {}),
      ...(options.headers || {})
    };
    const response = await fetch(cfg.url + path, {
      method: options.method || "GET",
      headers,
      body: options.body,
      cache: "no-store"
    });
    if (options.raw) return response;
    const data = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(errText(data));
    return data;
  }

  async function getAccessToken() {
    if (!session) throw new Error("登录会话失效，请重新登录。");
    if (session.expires_at - Date.now() > 60000) return session.access_token;
    const refreshed = await request("/auth/v1/token?grant_type=refresh_token", {
      method: "POST", body: JSON.stringify({ refresh_token: session.refresh_token })
    });
    setSession(refreshed);
    return session.access_token;
  }

  async function secure(path, options) {
    const accessToken = await getAccessToken();
    return request(path, options, accessToken);
  }

  async function hasMembership() {
    return (await secure("/rest/v1/rpc/secure_my_membership", {
      method: "POST", body: "{}"
    })) === true;
  }

  async function hasVerifiedMFA() {
    return (await secure("/rest/v1/rpc/secure_has_verified_mfa", {
      method: "POST", body: "{}"
    })) === true;
  }

  window.GBD_SECURE_FETCH = async function () {
    if (!(await hasVerifiedMFA())) {
      throw new Error("此登录会话尚未完成双因素认证，无法读取私有科研数据。");
    }
    const token = await getAccessToken();
    const response = await request(
      "/storage/v1/object/authenticated/" + encodeURIComponent(cfg.bucket) +
        "/" + encodeURIComponent(cfg.objectPath),
      { method: "GET", raw: true }, token
    );
    if (response.status === 401 || response.status === 403) {
      throw new Error("服务器拒绝读取私有数据，请检查授权与TOTP验证状态。");
    }
    return response;
  };

  function openPortal() {
    if (appLoaded) return;
    appLoaded = true;
    document.documentElement.classList.add("authenticated");
    $("loginPassword").value = "";
    $("challengeInput").value = "";
    $("totpSecret").textContent = "";
    $("totpQr").removeAttribute("src");
    const script = document.createElement("script");
    script.src = "app.js?v=totp-2";
    script.onerror = function () {
      appLoaded = false;
      document.documentElement.classList.remove("authenticated");
      showError("challengeError", "管理系统脚本加载失败，请刷新重试。");
    };
    document.body.appendChild(script);
  }

  function showSecondStep(enroll) {
    pendingEnrollment = enroll;
    $("totpSetup").hidden = !enroll;
    $("loginPassword").value = "";
    $("loginForm").hidden = true;
    $("secondFactorForm").hidden = false;
    $("challengeInput").value = "";
    showError("challengeError", "");
    if (!enroll) $("challengeInput").focus();
  }

  function showEnrollment(data) {
    const raw = String(data && data.totp && data.totp.qr_code || "");
    const img = $("totpQr");
    let source = "";
    if (raw.startsWith("data:image/svg+xml")) source = raw;
    else if (raw.trim().startsWith("<svg")) {
      source = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(raw);
    }
    img.hidden = !source;
    if (source) img.src = source;
    $("totpSecret").textContent = String(data && data.totp && data.totp.secret || "");
    showSecondStep(true);
  }

  async function enrollOrChallenge() {
    const user = await secure("/auth/v1/user");
    if (!user || !user.id) throw new Error("无法确认当前登录用户。");
    if (!(await hasMembership())) throw new Error("该账号未加入项目组授权名单。");

    if (await hasVerifiedMFA()) {
      openPortal();
      return;
    }

    const all = Array.isArray(user.factors) ? user.factors : [];
    const verified = all.find(function (f) {
      return f.factor_type === "totp" && f.status === "verified";
    });

    if (verified) {
      activeFactorId = verified.id;
      showSecondStep(false);
      return;
    }

    // An earlier abandoned enrollment cannot reveal its secret again.
    // Discard only unverified TOTP factors owned by this authenticated user.
    for (const factor of all) {
      if (factor.factor_type === "totp" && factor.status === "unverified") {
        await secure("/auth/v1/factors/" + encodeURIComponent(factor.id), {
          method: "DELETE"
        });
      }
    }
    const enrolled = await secure("/auth/v1/factors", {
      method: "POST",
      body: JSON.stringify({ factor_type: "totp", friendly_name: "GBD Research Hub" })
    });
    if (!enrolled || !enrolled.id || !enrolled.totp) {
      throw new Error("服务器没有返回身份验证器绑定信息。");
    }
    activeFactorId = enrolled.id;
    showEnrollment(enrolled);
  }

  async function signOut() {
    if (busyLogout) return;
    busyLogout = true;
    try {
      if (session) {
        const token = await getAccessToken();
        await request("/auth/v1/logout", { method: "POST", body: "{}" }, token);
      }
    } catch (_) {
      // Always clear the browser session on logout, even when offline.
    } finally {
      clearSession();
      location.reload();
    }
  }

  $("loginForm").addEventListener("submit", async function (event) {
    event.preventDefault();
    if (!ready) {
      showError("loginError", "Supabase公开客户端配置无效，请联系管理员。");
      return;
    }
    if ($("loginRole").value !== "project") {
      showError("loginError", "请选择项目组角色。");
      return;
    }
    const email = $("loginUsername").value.trim();
    const password = $("loginPassword").value;
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || !password) {
      showError("loginError", "请输入已授权的邮箱与个人密码。");
      return;
    }
    const btn = $("loginSubmit");
    btn.disabled = true;
    showError("loginError", "");
    keepSession = $("rememberSession").checked;
    try {
      const auth = await request("/auth/v1/token?grant_type=password", {
        method: "POST", body: JSON.stringify({ email, password })
      });
      setSession(auth);
      await enrollOrChallenge();
    } catch (error) {
      showError("loginError", "登录失败：" + errText(error));
      clearSession();
    } finally {
      btn.disabled = false;
      $("loginPassword").value = "";
    }
  });

  $("secondFactorForm").addEventListener("submit", async function (event) {
    event.preventDefault();
    const code = $("challengeInput").value.trim();
    if (!/^[0-9]{6}$/.test(code)) {
      showError("challengeError", "请输入手机验证器中的6位数字。");
      return;
    }
    if (!activeFactorId) {
      showError("challengeError", "缺少验证器信息，请返回并重新登录。");
      return;
    }
    const btn = $("secondFactorSubmit");
    btn.disabled = true;
    showError("challengeError", "");
    try {
      const id = encodeURIComponent(activeFactorId);
      const challenge = await secure("/auth/v1/factors/" + id + "/challenge", {
        method: "POST", body: "{}"
      });
      if (!challenge || !challenge.id) throw new Error("未生成双因素验证挑战。");
      const verified = await secure("/auth/v1/factors/" + id + "/verify", {
        method: "POST",
        body: JSON.stringify({ challenge_id: challenge.id, code })
      });
      setSession(verified);
      if (!(await hasVerifiedMFA())) {
        throw new Error("第二步认证未通过项目组访问许可，请联系管理员。");
      }
      pendingEnrollment = false;
      activeFactorId = "";
      saveSession();
      openPortal();
    } catch (error) {
      showError("challengeError", "TOTP验证失败：" + errText(error));
      $("challengeInput").value = "";
    } finally {
      btn.disabled = false;
    }
  });

  $("returnToLogin").addEventListener("click", signOut);
  $("logoutBtn").addEventListener("click", signOut);
  $("togglePassword").addEventListener("click", function () {
    const password = $("loginPassword");
    const visible = password.type === "password";
    password.type = visible ? "text" : "password";
    this.textContent = visible ? "隐藏" : "显示";
    this.setAttribute("aria-pressed", String(visible));
    this.setAttribute("aria-label", visible ? "隐藏密码" : "显示密码");
  });

  function recordActivity() {
    if (!session || busyLogout) return;
    if (Date.now() - lastActivity >= idleMs) {
      signOut();
      return;
    }
    lastActivity = Date.now();
    if (keepSession && Date.now() - lastSave > 20000) saveSession();
  }
  ["pointerdown", "keydown", "scroll"].forEach(function (event) {
    window.addEventListener(event, recordActivity, { passive: true });
  });
  window.addEventListener("focus", function () {
    if (session && Date.now() - lastActivity >= idleMs) signOut();
  });
  setInterval(function () {
    if (session && Date.now() - lastActivity >= idleMs) signOut();
  }, 30000);

  (async function restore() {
    if (!ready) {
      showError("loginError", "尚未配置可用的Supabase客户端连接。");
      return;
    }
    try {
      const stored = JSON.parse(sessionStorage.getItem(sessionKey) || "null");
      if (!stored || !stored.session || Date.now() - Number(stored.lastActivity) >= idleMs) {
        clearSession();
        return;
      }
      session = stored.session;
      lastActivity = Number(stored.lastActivity);
      keepSession = true;
      if (await hasVerifiedMFA()) {
        openPortal();
      } else {
        clearSession();
      }
    } catch (_) {
      clearSession();
    }
  })();
})();
