/* 
 * Front-end login demonstration only. This is NOT access control.
 * A public GitHub Pages website cannot protect source code, data/*.csv,
 * or the authentication verifier. Do not use for private/sensitive data.
 * Password is not stored in plaintext: PBKDF2-SHA256 verifier below.
 */
(function () {
  "use strict";

  const ROLE = "project";
  const USER = "sdmb";
  const SESSION_KEY = "gbd-research-hub-demo-session";
  const SALT_HEX = "bb42e84da7eb9f071697f2ee736c2eee";
  const EXPECTED_HEX = "5d25c6fc75e3f410fb4d06dcebf517ed772eef03542772c06909a4ddea957ddb";
  const ITERATIONS = 210000;
  const input = (id) => document.getElementById(id);
  let loading = false;

  function fromHex(hex) {
    return new Uint8Array(hex.match(/.{2}/g).map((x) => parseInt(x, 16)));
  }
  async function verifyPassword(password) {
    if (!window.crypto || !window.crypto.subtle) {
      throw new Error("该浏览器不支持安全加密接口，请通过 HTTPS 打开网站");
    }
    const encoder = new TextEncoder();
    const key = await crypto.subtle.importKey(
      "raw", encoder.encode(password), "PBKDF2", false, ["deriveBits"]
    );
    const result = new Uint8Array(await crypto.subtle.deriveBits(
      { name: "PBKDF2", hash: "SHA-256", salt: fromHex(SALT_HEX), iterations: ITERATIONS },
      key, 256
    ));
    const target = fromHex(EXPECTED_HEX);
    let diff = 0;
    for (let i = 0; i < target.length; i++) diff |= target[i] ^ result[i];
    return diff === 0;
  }
  function showError(message) {
    input("loginError").textContent = message;
  }
  function sessionExists() {
    try { return sessionStorage.getItem(SESSION_KEY) === "project"; }
    catch (_) { return false; }
  }
  function setSession() {
    try { sessionStorage.setItem(SESSION_KEY, "project"); }
    catch (_) { /* session persistence is optional */ }
  }
  function clearSession() {
    try { sessionStorage.removeItem(SESSION_KEY); }
    catch (_) { /* storage might be unavailable */ }
  }
  function openPortal() {
    if (loading) return;
    loading = true;
    document.documentElement.classList.add("authenticated");
    input("loginPassword").value = "";
    const script = document.createElement("script");
    script.src = "app.js";
    script.onerror = function () {
      document.documentElement.classList.remove("authenticated");
      loading = false;
      clearSession();
      showError("管理系统脚本加载失败，请刷新页面重试。");
    };
    document.body.appendChild(script);
  }
  input("loginForm").addEventListener("submit", async function (event) {
    event.preventDefault();
    if (loading) return;
    const role = input("loginRole").value;
    const username = input("loginUsername").value.trim();
    const password = input("loginPassword").value;
    if (!role || !username || !password) {
      showError("请选择登录角色，并填写账号和密码。");
      return;
    }
    const submit = input("loginSubmit");
    submit.disabled = true;
    submit.textContent = "正在校验…";
    showError("");
    try {
      const passwordOK = await verifyPassword(password);
      if (role !== ROLE || username !== USER || !passwordOK) {
        showError("登录角色、账号或密码不正确，请重新输入。");
        input("loginPassword").value = "";
        input("loginPassword").focus();
      } else {
        if (input("rememberSession").checked) setSession();
        openPortal();
      }
    } catch (error) {
      showError(error.message || "校验暂时不可用，请刷新后重试。");
    } finally {
      submit.disabled = false;
      submit.innerHTML = '登 录 <span>→</span>';
    }
  });

  input("togglePassword").addEventListener("click", function () {
    const password = input("loginPassword");
    const visible = password.type === "password";
    password.type = visible ? "text" : "password";
    this.textContent = visible ? "隐藏" : "显示";
    this.setAttribute("aria-label", visible ? "隐藏密码" : "显示密码");
    this.setAttribute("aria-pressed", String(visible));
  });

  input("logoutBtn").addEventListener("click", function () {
    clearSession();
    location.reload();
  });

  if (sessionExists()) openPortal();
})();
