/*
 * Interface-only login gate for a public static website.
 * THIS IS NOT SECURITY AUTHENTICATION OR TRUE MFA.
 * The public CSV, all JS code and the password verifier remain accessible
 * to anyone without logging in. Do not host sensitive information here.
 */
(function () {
  "use strict";

  const ROLE = "project";
  const USER = "sdmb";
  const SESSION_KEY = "gbd-research-hub-demo-session";
  const FAIL_KEY = "gbd-research-hub-auth-failures";
  const SALT_HEX = "bb42e84da7eb9f071697f2ee736c2eee";
  const EXPECTED_HEX = "5d25c6fc75e3f410fb4d06dcebf517ed772eef03542772c06909a4ddea957ddb";
  const ITERATIONS = 210000;

  const CHALLENGE_VALID_MS = 2 * 60 * 1000;
  const IDLE_TIMEOUT_MS = 15 * 60 * 1000;
  const MAX_SESSION_MS = 8 * 60 * 60 * 1000;
  const MAX_FAILURES = 5;
  const COOLDOWN_MS = 60 * 1000;
  const CAPTCHA_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";

  const input = (id) => document.getElementById(id);
  let loading = false;
  let loggedIn = false;
  let challenge = "";
  let challengeCreatedAt = 0;
  let loggedInAt = 0;
  let lastActiveAt = 0;
  let lastPersistAt = 0;
  let persistInSession = false;

  function fromHex(hex) {
    return new Uint8Array(hex.match(/.{2}/g).map((s) => parseInt(s, 16)));
  }

  async function verifyPassword(password) {
    if (!window.crypto || !window.crypto.subtle) {
      throw new Error("当前浏览器不支持安全加密接口，请使用 HTTPS 打开网站");
    }
    const key = await crypto.subtle.importKey(
      "raw", new TextEncoder().encode(password), "PBKDF2", false, ["deriveBits"]
    );
    const result = new Uint8Array(await crypto.subtle.deriveBits(
      { name: "PBKDF2", hash: "SHA-256", salt: fromHex(SALT_HEX), iterations: ITERATIONS },
      key, 256
    ));
    const expected = fromHex(EXPECTED_HEX);
    let mismatch = 0;
    for (let i = 0; i < expected.length; i++) mismatch |= expected[i] ^ result[i];
    return mismatch === 0;
  }

  function storageRead(key) {
    try { return sessionStorage.getItem(key); }
    catch (_) { return null; }
  }

  function storageWrite(key, value) {
    try { sessionStorage.setItem(key, value); }
    catch (_) { /* private storage may not be available */ }
  }

  function storageRemove(key) {
    try { sessionStorage.removeItem(key); }
    catch (_) { /* private storage may not be available */ }
  }

  function setError(id, message) {
    input(id).textContent = message;
  }

  function failureInfo() {
    try {
      const raw = JSON.parse(storageRead(FAIL_KEY) || "{}");
      return { count: Number(raw.count) || 0, until: Number(raw.until) || 0 };
    } catch (_) {
      return { count: 0, until: 0 };
    }
  }

  function lockedForSeconds() {
    return Math.max(0, Math.ceil((failureInfo().until - Date.now()) / 1000));
  }

  function failedAttempt() {
    const record = failureInfo();
    if (record.until && Date.now() >= record.until) {
      record.count = 0;
      record.until = 0;
    }
    record.count++;
    if (record.count >= MAX_FAILURES) {
      record.count = 0;
      record.until = Date.now() + COOLDOWN_MS;
    }
    storageWrite(FAIL_KEY, JSON.stringify(record));
    return lockedForSeconds();
  }

  function resetFailures() {
    storageRemove(FAIL_KEY);
  }

  function issueChallenge() {
    if (!crypto || typeof crypto.getRandomValues !== "function") {
      throw new Error("当前浏览器不支持验证码所需的加密随机数接口");
    }
    const bytes = new Uint8Array(6);
    crypto.getRandomValues(bytes);
    challenge = Array.from(bytes, (x) => CAPTCHA_ALPHABET[x % CAPTCHA_ALPHABET.length]).join("");
    challengeCreatedAt = Date.now();
    input("challengeDisplay").textContent = challenge;
    input("challengeInput").value = "";
    setError("challengeError", "");
  }

  function startChallenge() {
    issueChallenge();
    input("loginPassword").value = "";
    input("loginForm").hidden = true;
    input("secondFactorForm").hidden = false;
    input("challengeInput").focus();
  }

  function returnToLogin() {
    challenge = "";
    challengeCreatedAt = 0;
    input("secondFactorForm").hidden = true;
    input("loginForm").hidden = false;
    input("loginPassword").value = "";
    setError("challengeError", "");
    input("loginPassword").focus();
  }

  function validSession(obj) {
    if (!obj || obj.role !== ROLE || obj.user !== USER) return false;
    const started = Number(obj.started);
    const last = Number(obj.last);
    const now = Date.now();
    return Number.isFinite(started) && Number.isFinite(last)
      && started <= now && last <= now
      && now - started < MAX_SESSION_MS && now - last < IDLE_TIMEOUT_MS;
  }

  function restoreSession() {
    try {
      const parsed = JSON.parse(storageRead(SESSION_KEY) || "null");
      if (!validSession(parsed)) {
        storageRemove(SESSION_KEY);
        return false;
      }
      loggedInAt = Number(parsed.started);
      lastActiveAt = Number(parsed.last);
      persistInSession = true;
      return true;
    } catch (_) {
      storageRemove(SESSION_KEY);
      return false;
    }
  }

  function saveSession() {
    if (!persistInSession) return;
    storageWrite(SESSION_KEY, JSON.stringify({
      role: ROLE, user: USER, started: loggedInAt, last: lastActiveAt
    }));
  }

  function clearSession() {
    storageRemove(SESSION_KEY);
  }

  function expireAndReload() {
    clearSession();
    window.location.reload();
  }

  function isExpired() {
    const now = Date.now();
    return loggedIn && (now - lastActiveAt >= IDLE_TIMEOUT_MS
      || now - loggedInAt >= MAX_SESSION_MS
      || now < lastActiveAt || now < loggedInAt);
  }

  function onActivity() {
    if (!loggedIn) return;
    if (isExpired()) {
      expireAndReload();
      return;
    }
    const now = Date.now();
    lastActiveAt = now;
    if (persistInSession && now - lastPersistAt > 20000) {
      saveSession();
      lastPersistAt = now;
    }
  }

  function startSessionWatch() {
    document.addEventListener("pointerdown", onActivity, { passive: true });
    document.addEventListener("keydown", onActivity);
    document.addEventListener("scroll", onActivity, { passive: true });
    window.addEventListener("focus", function () {
      if (isExpired()) expireAndReload();
    });
    window.setInterval(function () {
      if (isExpired()) expireAndReload();
    }, 30000);
  }

  function openPortal() {
    if (loading) return;
    loading = true;
    loggedIn = true;
    document.documentElement.classList.add("authenticated");
    input("loginPassword").value = "";
    input("challengeInput").value = "";
    const script = document.createElement("script");
    script.src = "app.js?v=20261031-2";
    script.onerror = function () {
      loggedIn = false;
      loading = false;
      clearSession();
      document.documentElement.classList.remove("authenticated");
      returnToLogin();
      setError("loginError", "管理系统文件加载失败，请刷新网页再试。");
    };
    document.body.appendChild(script);
  }

  input("loginForm").addEventListener("submit", async function (event) {
    event.preventDefault();
    if (loading) return;
    const lock = lockedForSeconds();
    if (lock) {
      setError("loginError", "尝试次数过多，请 " + lock + " 秒后重试。");
      return;
    }
    const role = input("loginRole").value;
    const user = input("loginUsername").value.trim();
    const password = input("loginPassword").value;
    if (!role || !user || !password) {
      setError("loginError", "请选择登录角色，并填写账号和密码。");
      return;
    }

    const submit = input("loginSubmit");
    submit.disabled = true;
    submit.textContent = "正在校验…";
    setError("loginError", "");
    try {
      const passwordOK = await verifyPassword(password);
      if (role !== ROLE || user !== USER || !passwordOK) {
        const wait = failedAttempt();
        setError("loginError", wait
          ? "尝试次数过多，请 " + wait + " 秒后重试。"
          : "登录角色、账号或密码不正确，请重试。");
        input("loginPassword").value = "";
      } else {
        startChallenge();
      }
    } catch (error) {
      setError("loginError", error.message || "登录校验不可用，请刷新重试。");
    } finally {
      submit.disabled = false;
      submit.innerHTML = '下一步 <span>→</span>';
    }
  });

  input("secondFactorForm").addEventListener("submit", function (event) {
    event.preventDefault();
    if (loading) return;
    const lock = lockedForSeconds();
    if (lock) {
      returnToLogin();
      setError("loginError", "尝试次数过多，请 " + lock + " 秒后重新登录。");
      return;
    }
    if (!challenge || Date.now() - challengeCreatedAt > CHALLENGE_VALID_MS) {
      issueChallenge();
      setError("challengeError", "验证码已过期，请输入新验证码。");
      return;
    }
    const value = input("challengeInput").value.trim().toUpperCase();
    if (value !== challenge) {
      const wait = failedAttempt();
      if (wait) {
        returnToLogin();
        setError("loginError", "尝试次数过多，请 " + wait + " 秒后重新登录。");
      } else {
        issueChallenge();
        setError("challengeError", "验证码不正确，已自动刷新，请重新输入。");
        input("challengeInput").focus();
      }
      return;
    }
    challenge = "";
    resetFailures();
    loggedInAt = Date.now();
    lastActiveAt = loggedInAt;
    persistInSession = input("rememberSession").checked;
    if (persistInSession) saveSession();
    else clearSession();
    openPortal();
  });

  input("refreshChallenge").addEventListener("click", function () {
    issueChallenge();
    input("challengeInput").focus();
  });

  input("returnToLogin").addEventListener("click", returnToLogin);

  input("togglePassword").addEventListener("click", function () {
    const password = input("loginPassword");
    const visible = password.type === "password";
    password.type = visible ? "text" : "password";
    this.textContent = visible ? "隐藏" : "显示";
    this.setAttribute("aria-label", visible ? "隐藏密码" : "显示密码");
    this.setAttribute("aria-pressed", String(visible));
  });

  input("logoutBtn").addEventListener("click", expireAndReload);

  if (restoreSession()) openPortal();
  startSessionWatch();
})();
