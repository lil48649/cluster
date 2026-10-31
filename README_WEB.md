# GBD Research Hub｜安全版科研数据管理系统

> 本文档适用于 `secure-supabase` 开发分支；当前 GitHub Pages 正式站点仍发布自 `web` 分支。**不要在尚未完成真实 TOTP 验收前切换生产网站。**

## 身份验证

1. 项目组成员使用经审批的个人邮箱和密码登录 Supabase Auth。
2. 首次登录设置手机验证器（Google Authenticator / Microsoft Authenticator），扫描二维码，输入6位动态验证码。
3. 之后登录必须再次使用手机验证器的 TOTP 验证码；Supabase Auth 将当前会话提升到 `aal2`。
4. Supabase Storage RLS 同时核验用户白名单、有效登录会话、`aal2`、已验证的 TOTP 因子，满足后才允许读取指定私有 CSV。
5. 15分钟无操作自动退出，本地会话仅使用 sessionStorage（如果用户选择保持本次会话）。

本版本**无需 Resend、购买域名、SMTP 或邮件 OTP**。之前的邮件 Edge Functions 已停用（返回410）。

## 数据与查询

- 原始研究数据必须存放在 Supabase 的 `gbd-private` 私有桶，文件名为 `gbd2023_low_physical_activity.csv`。
- 前端仅通过经授权的 Storage API 加载数据；不再通过 GitHub Pages 公共 `data/` 路径获取。
- 保留数据总览、数据档案、跨年比较、字段字典和质量核验功能。
- 数据总览已移除CSV下载；其他页面此前已有的导出功能仍存在。已获准读取数据的用户无法被彻底阻止保存浏览器响应。

## 部署状态

截至2026-10-31：Supabase 私有桶存在，已上传目标CSV；现有唯一已确认用户已经加入项目白名单。云端 TOTP RLS 规则已部署，前端已修改并在模拟测试中验证了密码登录、首次扫码绑定、TOTP挑战及进入页面的衔接，但**尚未使用真实手机验证器和实际用户凭据完成端到端登录**。

原公开仓库的 `web` 分支和Git历史中仍留有早先公开的CSV；已有副本无法依靠更改RLS恢复保密。

详细部署及验收步骤见 [SECURE_DEPLOYMENT.md](./SECURE_DEPLOYMENT.md)。

## 安全约束

- 公开代码仅允许包含 Supabase 的项目URL和 **publishable** key。
- 绝不能在 GitHub 或聊天中公开服务角色密钥、数据库密码、用户密码、TOTP 绑定密钥。
- 真实私有数据与用户凭据应始终由 Supabase 管理。
- 新成员需先由管理员审核，再将其 `auth.users.id` 写入 `app_private.project_members`。
