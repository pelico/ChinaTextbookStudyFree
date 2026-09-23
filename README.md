# ChinaStudyFree · 小学全科 AI 学习平台

> **一个免费、开源、纯公益的小学全科学习平台**
>
> 我们相信：**每一个中国孩子，无论身处北上广深，还是大山深处的乡村小学，都应该拥有一样好的学习资源。**
>
> 让孩子在玩中学，让 AI 方便你我他。 ❤️

---

## 🌱 项目愿景

中国的教育资源分布不均是一个长期存在的问题。一线城市的孩子可以购买数百元一套的教辅、上价格高昂的补习班；而偏远地区的孩子，往往连一本配套练习册都难以获得。

**ChinaStudyFree** 希望借助 AI 的力量，改变这件事：

- 📚 **覆盖小学全科**：语文、数学、英语、科学
- 🆓 **永久免费**：不收费、不卖课、不做广告、不收集隐私
- 🤖 **AI 原创题目**：基于人教版/统编版教材知识体系，由 AI 生成单元小测与知识点全解
- 🧩 **AI 打印试卷**：按教材单元/章节自由选题，AI 一键生成可打印试卷与答案
- 🔊 **全站语音**：题目、选项、知识讲解均配有 TTS 语音朗读
- 📖 **课文听读**：语文/英语课文逐句跟读，支持连播，配合课本原页展示
- 📚 **课外故事**：AI 生成 284 篇分级读物 + 阅读理解题 + 配图，巩固课内知识
- 🎮 **在玩中学**：题目形式生动、即时反馈，让孩子在闯关和互动中建立对知识的兴趣
- 🎁 **奖励系统**：宝石、成就、皮肤装扮、商店、排行榜、连胜激励，营造持续学习的动力
- 📱 **多端可用**：Web / 原生 Android App，支持连接局域网或公网（Cloudflare Tunnel）
- 🌏 **服务每一个孩子**：从一年级到六年级，只要有一台能上网的设备，就能用

---

## 📸 功能预览

### Web 端（支持手机浏览器添加到主屏幕，体验类原生 App）

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/screen-0.png" width="200" /><br/><b>年级选择</b></td>
    <td align="center"><img src="docs/screenshots/screen-1.png" width="400" /><br/><b>学科总览</b></td>
    <td align="center"><img src="docs/screenshots/screen-3.png" width="400" /><br/><b>学习路径</b></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/screen-2.png" width="200" /><br/><b>单元答题</b></td>
    <td align="center"><img src="docs/screenshots/screen-6.png" width="400" /><br/><b>课文听读</b></td>
    <td align="center"><img src="docs/screenshots/screen-7.png" width="400" /><br/><b>课外故事</b></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/screen-4.png" width="400" /><br/><b>错题回顾</b></td>
    <td align="center"><img src="docs/screenshots/screen-5.png" width="400" /><br/><b>个人中心</b></td>
    <td></td>
  </tr>
</table>

---

## ✨ 主要特性

| 功能 | 说明 |
|------|------|
| **单元小测** | 跟着课本章节走，学完一课就能练 |
| **知识点全解** | 每个知识点配有清晰讲解、核心概念、公式与易错点 |
| **课文听读** | 语文/英语课文逐句朗读，支持跟读与连播，展示课本原页 |
| **课外故事** | 每单元 2 篇 AI 分级故事 + 阅读理解题 + 儿童插画配图 |
| **全站 TTS** | 题目、选项、讲解、故事文本均可点击朗读（Opus 格式，71,500+ 音频） |
| **学习进度** | 自动保存每课完成情况与正确率，故事阅读支持星星评级 |
| **连击系统** | 连续答对触发连击动画与语音激励 |
| **AI 打印试卷** | 选择单元/章节与题目类型，AI 生成标准化试卷（含答案与解析），可打印下载 |
| **装扮商店** | 用宝石购买皮肤、主题、课程背景，全局生效，可装备展示 |
| **成就 / 连胜** | 成就墙、连胜记录、每日任务与本周报告，留存激励 |
| **多学习者档案** | 支持在同一设备/账号下管理多个孩子，各自独立进度 |
| **跨端数据同步** | 家长设置、学习进度、宝石等通过服务端同步，手机与 Web 一致 |

**覆盖学科与版本：**

| 学科 | 版本 | 年级 | 课外故事 |
|------|------|------|----------|
| 数学 | 人教版 | 一至六年级 | — |
| 语文 | 统编版 | 一至六年级 | 188 篇 |
| 英语 | 人教版 PEP | 三至六年级 | 96 篇 |
| 科学 | 教科版 | 一至六年级 | — |

---

## 🏗️ 架构概览

本项目是**前后端分离**的单仓库：

```
┌─────────────────────────────────────────────┐
│  前端  apps/web  (Next.js 静态导出)           │
│  ├─ 学习：grade / book / lesson / guide      │
│  ├─ 内容：reading / stories / review         │
│  ├─ 互动：league(排行榜) / shop(商店) / profile │
│  └─ AI：custom(打印试卷) / worksheet         │
└──────────────┬──────────────────────────────┘
               │ 静态文件 (nginx 托送)
┌──────────────┴──────────────────────────────┐
│  后端  custom_server.py  (Python 内建 HTTP)  │
│  ├─ /api/custom/*  学习/家长/进度/kids 等 API │
│  ├─ /api/custom/worksheet/generate  AI 试卷   │
│  ├─ SQLite 持久化   /data 卷（家长设置/进度） │
│  └─ 资源代理：音频/图片/课本原页              │
└──────────────┬──────────────────────────────┘
               │
      nginx + 静态资源（音频/图片/课本）
```

- **前端**：Next.js `output: "export"` 纯静态导出，SPA 路由，配合 Service Worker 做弱网/离线优化。
- **后端**：Python 内建 `http.server`（`custom_server.py`），提供 REST API + 资源代理，数据落在挂载卷 `/data` 的 SQLite 中，容器重启数据不丢。
- **部署**：一个 `docker compose up` 即可同时拉起 nginx（前端）与后端 API，支持 AMD / ARM / ARMv7 多种架构。

---

## 🚀 快速开始（Docker 一键部署，推荐）

```bash
# 1. 克隆仓库
git clone https://github.com/pelico/ChinaTextbookStudyFree.git
cd ChinaTextbookStudyFree

# 2. 启动（首次会自动下载资源，见下方说明）
docker compose up -d

# 3. 访问
#    本机：http://localhost:3088
#    局域网：http://<主机IP>:3088
```

访问首页即直达默认一年级学习页 `http://<主机>/grade/1/`。

> 资源文件（音频/配图/课本原页，约 1.4GB）体积较大，首次启动/首拉镜像时通过 GitHub Release 下载。如网络受限，见下方「资源下载慢 / 受限网络」。

### 最小参数：docker run / docker compose

不想克隆整个仓库也可以，直接用官方镜像即可（镜像拉取即含 Web 端，运行时后台自动下载资源）：

```bash
# ---- docker run（最小参数）----
mkdir -p data audio textbook-pages story-images          # 先建卷目录
docker run -d --name china-study-free \
  -p 3088:80 \
  -v "$PWD/data:/data" \
  -v "$PWD/audio:/usr/share/nginx/html/audio" \
  -v "$PWD/textbook-pages:/usr/share/nginx/html/textbook-pages" \
  -v "$PWD/story-images:/usr/share/nginx/html/story-images" \
  ghcr.io/pelico/chinatextbookstudyfree:latest
```

```yaml
# ---- docker-compose（最小参数）----
# 保存为 docker-compose.yml 后运行 docker compose up -d
services:
  china-study-free:
    image: ghcr.io/pelico/chinatextbookstudyfree:latest
    container_name: china-study-free
    ports:
      - "3088:80"
    restart: unless-stopped
    volumes:
      - ./data:/data
      - ./audio:/usr/share/nginx/html/audio
      - ./textbook-pages:/usr/share/nginx/html/textbook-pages
      - ./story-images:/usr/share/nginx/html/story-images
```

> `/data` 保存学习进度与家长设置，建议挂载；`audio` / `textbook-pages` / `story-images` 挂载后缓存下载好的资源，重启/换容器不重复下载。

### 资源下载慢 / 受限网络

首次启动容器会在后台自动下载音频、配图、课本原页（合计约 1.4GB，来自 GitHub Release）。Web 页面先可访问，资源逐步就绪；下载失败会自动重试 3 次，失败也不影响页面访问。若下载慢或失败，按需处理：

1. **挂载资源目录（推荐，下载一次永久生效）**：见上例，把三个资源目录挂载到宿主机，资源缓存本地，重启/重建容器不重复下载。
2. **配置代理**：给容器设置 `HTTP_PROXY` / `HTTPS_PROXY` 环境变量；后端 AI 接口会自动强制直连，代理只作用于资源下载，互不影响。
3. **换源**：设环境变量 `RELEASE_URL` 指向你本地可达的镜像地址（如内网源）。
4. **跳过下载**：只体验纯前端（不需要音频/图片）时设 `SKIP_DOWNLOAD=true`。
5. **查进度**：浏览器打开 `http://<主机>:3088/assets-status.json` 可查看资源下载状态。

### 端口与数据卷

`docker-compose.yml` 默认映射（可在 compose 中按需调整）：

| 项 | 值 |
|----|----|
| 外部端口 | `3088` → 容器 `80` |
| 数据卷 | `./data/custom:/data`（保存家长设置、学习进度等） |
| 镜像 | 见 `.github/workflows/docker-publish.yml`（`latest` + commit sha） |

### 轻量镜像（资源用卷挂载，镜像更小）

```bash
# 镜像内不含 1.4GB 资源，运行时用 volume 挂载音频/图片/课本
docker build -t china-study-free:lite --build-arg SKIP_ASSETS=true .
```

---

## 🖥️ 本地开发（源码方式）

### 1. 克隆仓库

```bash
git clone https://github.com/pelico/ChinaTextbookStudyFree.git
cd ChinaTextbookStudyFree
```

### 2. 下载资源文件

音频、配图、课本原页和题库数据体积较大，通过 GitHub Release 分发，不包含在 Git 仓库中。

```bash
# Linux / macOS / Git Bash (Windows)
bash scripts/download-assets.sh

# Windows PowerShell
powershell -ExecutionPolicy Bypass -File scripts\download-assets.ps1
```

这会自动下载并解压以下文件：

| 文件 | 内容 | 大小 | 解压到 |
|------|------|------|--------|
| `audio.tar.gz` | 71,502 个 TTS 音频 (Opus) | ~870 MB | `apps/web/public/audio/` |
| `story-images.zip` | 284 张 AI 故事配图 | ~368 MB | `apps/web/public/story-images/` |
| `textbook-pages.zip` | 1,577 张课本原页 (JPG) | ~192 MB | `apps/web/public/textbook-pages/` |
| `data.zip` | 前端构建数据 (JSON) | ~4.3 MB | `apps/web/public/data/` |
| `data-source.zip` | passages + stories 源 JSON | ~811 KB | `data/` |

### 3. 运行后端（可选，启用自定义 API）

```bash
python3 -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate

# 按需配置环境变量（见 custom_server.py 顶部说明）
export PORT=8001
export AI_API_KEY=sk-xxx               # AI 密钥（若未在后端默认 Key 中配置）
export AI_BASE_URL="https://aiapi.fonken.net/v1"

python3 custom_server.py
```

### 4. 运行 Web 端

```bash
cd apps/web
npm install
npm run dev
```

访问 http://localhost:3000 即可。手机端用浏览器打开后「添加到主屏幕」即可获得类原生 App 体验。

### 5. （可选）运行数据生成 Pipeline

如需从教材 PDF 重新生成题库数据：

```bash
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate
pip install -r requirements.txt

# 配置 .env（填入 API Key）

# 生成题库
python scripts/quiz/pipeline.py --subject all

# 生成课外故事
python scripts/stories/pipeline.py --subject all

# 生成故事配图
python scripts/stories/images.py --subject all

# 生成 TTS 音频
python scripts/tts/collect_texts.py
python scripts/tts/api_tts.py

# 构建前端数据
cd apps/web && npx tsx scripts/build-data.ts
```

---

## 📱 Android App

`apps/android` 为原生 Android 包装，用 WebView 加载前端，行为与 Web 端一致。

- **构建**：由 `.github/workflows/android-build.yml` 在打 Tag / main 变更时自动产出 APK。
- **数据持久化**：WebView 使用 `LOAD_DEFAULT` + 禁用 Service Worker 防坏缓存；`csf-active-kid`（当前学习者）等偏好存于 localStorage 并**持久保留**，冷启动不再要求反复选择。
- **使用**：安装后填入你的部署地址（局域网 `http://主机IP:3088` 或公网 Cloudflare Tunnel 地址）即可。

---

## 🧩 AI 打印试卷

在「打印试卷」（`/custom` 与 `/worksheet`）模块中，可按教材单元/章节课内选题、选择题型与难度，由 AI 生成标准化试卷：

- 支持**单元练习**与**考试模拟**两种模式
- 生成结果含题干、选项、标准答案与解析，可打印表格下载
- AI 密钥优先级：`页面填写的本地 Key` → 请求头 → **服务端默认 Key（在「我的」中配置，跨设备共享）** → 环境变量 `AI_API_KEY`
- 后端对 AI 接口强制直连，不受容器 `HTTPS_PROXY` 影响

---

## 🗂️ 项目结构

```
ChinaStudyFree/
│
├── scripts/
│   ├── quiz/                       # 题库生成 Pipeline
│   │   ├── pipeline.py             #   PDF → 大纲 → 题库
│   │   ├── prompts.py              #   AI Prompt 模板（按学科定制）
│   │   └── subjects.py             #   学科 / 版本 / 年级配置
│   ├── stories/                    # 课外故事生成 Pipeline
│   │   ├── pipeline.py             #   大纲 → 分级故事 + 阅读理解题
│   │   ├── prompts_story.py        #   故事 Prompt 模板 + JSON Schema
│   │   └── images.py               #   Gemini AI 配图生成
│   ├── passages/                   # 课文抽取
│   │   ├── extract_passages.py     #   PDF → 逐句课文 JSON
│   │   └── render_pages.py         #   PDF → 课本原页 JPG
│   ├── tts/                        # TTS 语音合成
│   │   ├── collect_texts.py        #   扫描全部文本，生成待合成清单
│   │   └── api_tts.py              #   DashScope API 批量合成
│   ├── download-assets.sh          # 下载 Release 资源（Linux/macOS）
│   ├── download-assets.ps1         # 下载 Release 资源（Windows）
│   └── package-release.sh          # 打包资源为 Release 附件
│
├── custom_server.py                # 后端：REST API + AI 试卷 + 资源代理 + SQLite
├── nginx.conf                      # nginx 静态托管 + API 反代
├── docker-entrypoint.sh            # 容器入口（启动时下载资源/拉起后端）
├── Dockerfile                      # 多架构 Docker 镜像（builder + nginx runtime）
├── docker-compose.yml              # 一键部署（前端 + 后端 + 数据卷）
│
├── apps/
│   ├── web/                        # Next.js 前端（静态导出 + SPA）
│   │   ├── src/
│   │   │   ├── app/                # 路由与页面
│   │   │   │   ├── book/           #   教材详情 / 学习路径
│   │   │   │   ├── lesson/         #   答题页面
│   │   │   │   ├── grade/          #   年级总览
│   │   │   │   ├── reading/        #   课文听读
│   │   │   │   ├── stories/        #   课外故事阅读 + 答题
│   │   │   │   ├── review/         #   错题回顾
│   │   │   │   ├── shop/           #   商店 / 装扮
│   │   │   │   ├── league/         #   排行榜 / 连胜
│   │   │   │   ├── profile/        #   个人中心 / 家长模式
│   │   │   │   ├── custom/         #   打印试卷工作台
│   │   │   │   └── worksheet/      #   AI 试卷生成
│   │   │   ├── components/         # UI 组件
│   │   │   ├── lib/                # 工具库（TTS、音效、kid、试卷、主题…）
│   │   │   ├── store/              # Zustand 状态管理
│   │   │   └── types/              # TypeScript 类型定义
│   │   └── public/
│   │       ├── audio/              # TTS 音频（通过 Release 下载）
│   │       ├── data/               # 题库+故事 JSON（通过 Release 下载）
│   │       ├── story-images/       # AI 故事配图（通过 Release 下载）
│   │       └── textbook-pages/     # 课本原页图片（通过 Release 下载）
│   └── android/                    # 原生 Android App（WebView 包装）
│
├── data/                           # 源数据（通过 Release 下载）
│   ├── passages/                   #   课文听读源 JSON（语文/英语）
│   └── stories/                    #   课外故事源 JSON（语文/英语）
│
├── output/                         # Pipeline 产出（大纲 + 题库 JSON）
│
├── packages/core/                  # TypeScript 共享域逻辑（Web 端运行时）
│
└── docs/
    ├── screenshots/                # README 截图
    └── custom-module-tech-design.html  # 自定义模块技术设计
```

---

## 🔒 家长模式与数据

- **家长模式**：在「我的」中设置、验证密码后进入，可管理孩子档案、配置默认 AI Key、时间限制等。
- **默认 AI Key（服务端存储）**：在「我的」配置后跨设备共享，打印试卷/生成功能无需每台设备单独填 Key。
- **多学习者**：同一部署下可创建多个孩子档案，各自学习进度、宝石独立保存。
- **数据安全**：进度与设置存于服务端 `/data` 卷（SQLite），容器升级不丢失；宝石/成就在多设备间通过 delta 协议保持一致。

---

## 📖 教材来源与版权

本项目引用的教材结构来自开源项目 [TapXWorld/ChinaTextbook](https://github.com/TapXWorld/ChinaTextbook)。

**版权策略**：

1. **不搬运教材原文**，只提取知识大纲与章节结构
2. **所有题目由 AI 原创生成**，基于知识点而非教材原题
3. **课外故事为 AI 原创**，不抄袭任何已出版读物
4. 如相关版权方认为本项目存在任何问题，请与我们联系，我们会第一时间响应处理

---

## 🤝 如何参与

这是一个**纯公益项目**，我们非常欢迎任何形式的参与：

- 👩‍🏫 **一线老师**：帮我们审核题目质量、指出错误、建议题型
- 👨‍👩‍👧 **家长**：把平台分享给需要的家庭，反馈孩子的使用体验
- 💻 **开发者**：提交 PR 修 bug、加功能、优化 UI
- 🎨 **设计师**：帮我们让界面对孩子更友好、更有趣
- 📣 **任何人**：把这个项目告诉一所乡村小学的老师

---

## 🛣️ 路线图

- [x] 数学、语文、英语、科学 Pipeline
- [x] Web 前端（单元小测 / 知识点全解 / 学习路径）
- [x] 全站 TTS 语音朗读（71,500+ 音频）
- [x] 课文听读（语文 / 英语，逐句 + 连播）
- [x] 课外故事阅读（语文 188 篇 + 英语 96 篇，含 AI 配图）
- [x] 装扮系统闭环（皮肤 / 主题 / 课程背景购买后全局生效）
- [x] 留存机制（每日任务 / 本周报告 / 连胜提醒推送）
- [x] AI 打印试卷（单元练习 / 考试模拟，含答案与解析）
- [x] 多学习者档案 + 跨端数据同步
- [x] 原生 Android App 包装
- [x] Docker 多架构一键部署
- [ ] 道德与法治内容
- [ ] 题目质量评估与人工审核流程
- [ ] 离线版 / 校园内网部署包
- [ ] 家长 / 老师端的学习报告

---

## 📜 许可协议

本项目采用 **MIT License** 开源发布，详见 [LICENSE](LICENSE)。

---

## 💌 写在最后

> 我们不知道这个项目能走多远，
> 但我们知道，只要多一个孩子因为它而多做对一道题、
> 多理解一个知识点、多喜欢上一门课，
> 这件事就是值得的。

如果你认同我们的理念，欢迎 ⭐ Star 支持，也欢迎把它转发给任何一位你认识的老师和家长。

**让每一个中国孩子，都能在玩中学。**