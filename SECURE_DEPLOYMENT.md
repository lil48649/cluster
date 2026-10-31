# GBD Research Hub — 安全后台配置指南

> 状态：安全架构的代码已准备在 secure-supabase 分支，未部署真实云后端。
> 当前发布中的 web 分支保持不变，不能将本开发分支直接设为 Pages 发布源。

## 安全访问流程

1. 每位成员使用获准邮箱和个人密码登录 Supabase Auth，获取有效 JWT 会话。
2. 服务器检查 project_members 白名单，随机生成六位OTP，使用服务端 Resend API 发送到该成员邮箱，验证码五分钟有效。
3. 服务端核验 OTP（含失败计数和一次性使用），授权指定 user_id + session_id 二次验证30分钟。
4. 浏览器携带 JWT 读取 Supabase 私有 Storage，RLS 同时要求账户在白名单及当前会话OTP授权有效。
5. 退出时撤销对应 OTP 验证；15分钟页面无操作退出。RLS才是真正阻挡未认证请求的核心。

## 需要项目管理员操作

### 1 创建 Supabase 项目

- 在 https://supabase.com/dashboard 新建项目，并确定合适数据驻留区域与费用。
- Authentication > Providers > Email 启用邮箱和个人密码登录，禁止公开注册/匿名用户。
- Authentication > Users 为每位项目成员邀请或创建个人账户。
- SQL Editor 执行 supabase/migrations/20261031_secure_auth.sql。
- 用 SQL Editor 向白名单加入已获准的用户 UUID（从 Auth Users 界面复制）： 

    insert into public.project_members(user_id, active) values ('AUTH_USER_UUID', true);

- Storage 中确认 gbd-private 是 private 桶，手动上传源CSV文件，文件名称必须为 gbd2023_low_physical_activity.csv。
- 文件只存入私有 Storage，不再上传到公开 GitHub。

### 2 配置邮件服务与 Edge Functions

- 建立 https://resend.com/ 的邮件发送服务；完成自有发信域名DNS验证。
- 在 Supabase Edge Functions Secrets 中设置：
  - RESEND_API_KEY：邮件服务私钥
  - OTP_FROM_EMAIL：已验证的发信邮箱
  - OTP_PEPPER：安全随机生成至少32字符的高熵秘密
  - FRONTEND_ORIGIN：https://lil48649.github.io
- Supabase 的 SUPABASE_URL 与 SUPABASE_SERVICE_ROLE_KEY 仅限服务端使用，绝不能放到公开仓库或前端脚本里。
- 部署 send-email-otp 和 verify-email-otp 两个 Edge Functions，保持默认 verify_jwt 开启。可通过 Supabase CLI 或项目界面部署。
- 注意邮件服务通常有发信额度；生产环境配置发信限制、监控与告警。

### 3 设置网页的非秘密参数

- 编辑 secure-config.js 的 url 为对应 Supabase 项目 URL。
- publishableKey 为该项目的 publishable 公开密钥，不可填写 service_role 或 secret key。
- 确认网页使用的 HTTPS 域名与 CORS / CSP 配置一致。

## 必做验收

1. 未登录用户获取 private CSV 被拒绝。
2. 仅登录邮箱和密码、未完成 OTP：请求被 RLS 拒绝。
3. 已完成OTP但不在白名单：请求被拒绝。
4. 验证码错误、过期、重复提交均被拒绝；重发受60秒限制。
5. OTP成功：只有相应用户和对应session_id可以读取私有CSV。
6. 退出或授权到期后，再次读取私有文件必须失败。
7. 进入原统计管理系统，确认72条数据及查询图表仍正确。
8. 浏览器和公开 GitHub 中不得出现真正私钥或机密数据。

## 公开历史特别说明

原始CSV过去已发布在公开GitHub仓库，虽然 secure-supabase 开发分支的当前版本已经删除这份CSV，原web分支及其Git历史仍保留它，原网址可能仍能下载。
**将文件从一个分支删除，不能使此前已经公开的内容重新成为秘密。**

对今后需要真正保密的CSV，建议新建一个干净且不含旧历史的仓库发布静态前端，私有数据永远只存在服务端私有存储；原站点的公开副本和历史应另行退役或处理。已公开历史、缓存和第三方副本可能无法完全回收。

## 本次交付状态

- 已准备 SQL 安全迁移、私有桶 RLS、项目组白名单、服务端OTP发送与核验、前端邮件OTP登录和私有CSV读取。
- 尚无 Supabase 项目连接、正式成员邮箱和 Resend 发信身份；因此无法实际创建私有云资源、发送邮件、完成生产验收。
- **请勿直接把 secure-supabase 分支用作线上网站**。待云服务配置完成后，整体切换并验证。

绝不在聊天中传送API私钥、service_role密钥、数据库密码、Resend API key或OTP_PEPPER。它们应该直接在云服务的Secrets设置页面配置。
