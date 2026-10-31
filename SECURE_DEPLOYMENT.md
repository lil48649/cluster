# GBD Research Hub｜Supabase 原生 TOTP 双因素验证部署记录

**当前状态（2026-10-31）**：云端项目已配置私有文件和 TOTP 强制访问策略；前端代码已更新到 `secure-supabase` 开发分支。**尚未进行真实手机端 TOTP 登录的端到端验收，因此仍未替换原线上 `web` 站点。**

## 已完成

- Supabase 项目：`gbd-research-hub`，ID `orptyvtibzsijqcqyvee`，区域东京。
- 存储桶 `gbd-private` 已设为 private，目标文件 `gbd2023_low_physical_activity.csv` 已由项目管理员上传。
- 现有一个经邮箱确认的非匿名用户，已加入 `app_private.project_members` 白名单。请后续为各位项目组成员单独添加用户和白名单，不共用密码。
- 原生 Supabase TOTP MFA：初次登录显示二维码并绑定手机；之后使用6位动态码进行服务端验证，获得 `aal2`。
- `storage.objects` 的唯一目标读取规则 `project_member_totp_mfa_read_only`：必须为私有桶的指定文件、操作为受身份认证的文件读取、当前会话确实存在、JWT和会话具有 `aal2`、存在状态为 verified 的 TOTP 因子且用户在项目白名单中。
- 前端 `auth.js` 使用 Supabase Auth 的密码登录、因子注册、challenge 和 verify 接口；`app.js` 只通过携带认证令牌的私有 Storage 请求获取 CSV。
- 旧邮件 OTP Edge Functions 已改为只返回 410（停用）；开发分支不再包含对应函数源代码。不需要 Resend、SMTP、自购域名或邮件发信密钥。
- GitHub Pages 正式站点继续使用原 `web` 分支，暂未部署本开发分支。

## 项目负责人需要做什么

1. 在手机安装 Google Authenticator、Microsoft Authenticator 或兼容 TOTP 的其他验证器。
2. Supabase → Authentication → Users 核实已确认邮箱的登录用户；确认这个账号为本人管理。新成员应建立独立账号并经过管理员白名单审核。
3. Supabase → Authentication → Providers → Email 确认邮箱密码登录启用、公开新用户注册关闭；建议设置强密码要求，并检查是否可启用泄露密码保护。
4. **不要**再配置 Resend 的 API Key、发送邮箱、OTP_PEPPER。
5. 第一次在安全版网页登录时：角色选“项目组”，输入授权邮箱和自己的密码；浏览器呈现二维码。用手机验证器扫码，然后输入动态6位码绑定。
6. 若多名成员接入，管理员应验证身份后把其用户 UUID 加入 `app_private.project_members`：
   `insert into app_private.project_members (user_id, active) values ('已批准用户 UUID', true) on conflict (user_id) do update set active=true;`
   仅使用已审核过的 Auth 用户 ID，禁止批量盲目批准。
7. 身份验证器手机丢失时须经过管理员人工身份核验后安全地重新绑定。Supabase TOTP 没有标准恢复码；建议正式使用前制定恢复和撤销流程。

## 相关代码与迁移

- `index.html`、`styles.css`：登录页面、初次绑定二维码及六位动态验证码输入。
- `auth.js`：邮件密码登录 + Supabase TOTP MFA + 会话管理；不储存 TOTP 秘钥或共享密码。
- `secure-config.js`：只包含允许公开的 Supabase 项目 URL 和 publishable key。
- `app.js`：仅通过经过授权的 Storage API 读取 CSV；“数据总览”页面没有 CSV 下载操作，其他查询功能保持。
- `supabase/migrations/20261031_native_totp_mfa.sql`：已部署的 `aal2` 私有对象访问规则。
- `supabase/migrations/20261031_mfa_membership_check.sql`、`20261031_native_totp_status_rpc.sql`、`20261031_harden_membership_rpc.sql`：已部署的自查 API 和权限收紧规则。
- `supabase/migrations/20261031_secure_backend_v2.sql`：最初的项目基础结构，已执行，包含旧版 OTP 的未使用内部表；**不可在现有生产项目重复执行**。

## 正式切换前的测试清单

- 未登录访问 private CSV 和公开 API：应被拒绝。
- 密码正确但未完成 TOTP（AAL1）：私有对象请求应被 RLS 拒绝。
- 未加入白名单的用户，即使完成 TOTP（AAL2）：读取仍拒绝。
- 用户完成手机 TOTP 并取得 AAL2：可读取私有 CSV 并正常显示原有72条记录和图表。
- 退出登录、禁用白名单、无效会话：访问应失败；确认其他会话不能复用别人的认证。
- 二次验证二维码只在初次绑定呈现；验证器秘钥不会提交至 GitHub、写进日志或长期存入浏览器。
- 执行 Supabase Security Advisors，核对权限警告和配置。
- 处理旧 GitHub `web` 分支已公开的原 CSV、历史提交和可能的缓存副本；**已公开的数据无法单靠删除旧文件恢复保密**。
- 真实浏览器测试全部通过后，才考虑切换 Pages 发布分支；最好使用无历史 CSV 的全新前端发布仓库，避免旧文件仍可通过仓库历史直接获取。

## 注意

该方案能通过 Supabase Storage RLS 限制未获授权用户读取新私有文件；但**获得授权、已经在浏览器读取数据的成员仍能保存浏览器响应**，无法保证“不可复制”。此外，原 GitHub Pages 的 CSV 至今可能仍然公开。本开发分支在网页端的实际完成情况需要真实 TOTP 登录验收，不能仅凭数据库迁移成功认定生产级安全部署完成。
