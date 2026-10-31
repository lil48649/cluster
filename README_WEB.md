# GBD Research Hub｜科研数据查询与管理平台

一个采用医院信息管理系统（HIS）视觉语言的**静态科研数据门户**，实际数据来自上传的 IHME GBD 2023 CSV。**本项目不包含医院患者信息，不是电子病历系统。**

## 数据内容

- 地区：China；人群：All Population；年龄：All ages
- 危险因素：Low physical activity；量纲：Number
- 疾病：Diabetes mellitus type 2、Ischemic stroke、Ischemic heart disease
- 指标：Deaths、DALYs、YLLs、YLDs
- 性别：Both、Male、Female
- 年份：1990、2023（只有两个观测端点）
- 共 72 条记录，12 个原始字段，无缺失或维度重复；4 条数据的 UI 下限小于 0，保留原值

源文件原样保存于 \`data/gbd2023_low_physical_activity.csv\`。前端 CSV 解析、筛选、统计和导出都在浏览器本地执行，不向第三方分析服务器提交数据。

## 功能

1. **数据总览**：四项疾病负担指标卡片（同一指标、性别、年份下三病种合计）；病种1990/2023端点对比柱状图；2023年病种构成。
2. **数据档案**：疾病、指标、性别、年份组合筛选；关键词检索；列排序；分页；完整源字段详情、复制 JSON。
3. **跨年比较**：分别计算同一指标、同一性别、同一疾病1990与2023年的绝对及相对变化，下载计算结果。
4. **字段字典**：12个CSV字段释义与取值。
5. **质量核验**：空值、重复复合键、区间边界、负下限提示及维度覆盖情况。
6. **数据导入/导出**：右上方可导入同样12列结构的CSV供当前浏览器会话使用；按当前档案筛选条件导出源字段CSV；收藏记录保存在本机浏览器 localStorage。

## 运行

该站点为 HTML + CSS + 原生 JavaScript，无需 npm 或后端。

\`\`\`bash
git clone -b web https://github.com/lil48649/cluster.git
cd cluster
python -m http.server 8000
\`\`\`

访问 \`http://localhost:8000/\`。**不要直接双击 index.html**：部分浏览器会阻止 file:// 页面通过 fetch 读取 CSV。

## 发布到 GitHub Pages

仓库管理员可在 GitHub → **Settings → Pages** → **Build and deployment** 选择 **Deploy from a branch**，分支选 \`web\`，目录选 \`/(root)\`，保存。部署成功后主页通常位于 \`https://lil48649.github.io/cluster/\`，**实际发布状态需要以 GitHub Pages 显示为准**。配置 Pages 可能需要仓库管理员操作，本次提交并不代表网站已经上线。

## 重要统计学说明

- \`metric=Number\`：原始数据为绝对数量，不代表年龄标准化率。
- \`Both\` 包含男性和女性，不能再与 \`Male\` 和 \`Female\` 直接叠加。
- 不跨指标求和，特别是 DALY、YLL、YLD 之间存在定义关联。
- 页面展示的三病种合计仅是同一 measure × sex × year 内的**点估计求和**，不据此构造总体95%不确定区间。
- 只有 1990 年和 2023 年：页面不进行逐年趋势插值、拟合、预测或年度变化率推断。
- 95% UI 中出现负数下限时保留 GBD 上传值，不进行非负截断。
- 本站点是单机静态查询工具，无后端数据库、用户鉴权、跨用户同步、医疗病历录入或审计日志。请勿把真实患者隐私数据上传到公开GitHub仓库。

## 项目结构

\`\`\`text
index.html                           主页面
styles.css                           响应式设计
app.js                               CSV解析、检索、可视化与导出
data/gbd2023_low_physical_activity.csv  原始数据
README_WEB.md                        使用与发布说明
\`\`\`