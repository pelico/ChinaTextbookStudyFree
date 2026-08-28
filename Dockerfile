# ================================================================
# ChinaStudyFree · Docker 镜像
#
# 多阶段构建：
#   1. builder  — 在宿主机原生平台运行（$BUILDPLATFORM），@next/swc 有 amd64/arm64 二进制
#   2. runtime  — nginx:stable-alpine，原生支持 linux/arm/v7
#
# 最终镜像只含 nginx + 静态文件（HTML/CSS/JS/音频/图片），架构无关。
#
# 构建命令：
#   # 本机平台（快速测试）
#   docker build -t china-study-free .
#
#   # 交叉构建 armv7l 镜像（在 x64/arm64 Mac 上构建，部署到 armv7l 设备）
#   docker buildx build --platform linux/arm/v7 -t china-study-free --load .
#
#   # 使用代理（国内）+ armv7l
#   docker buildx build --platform linux/arm/v7 \
#     --build-arg HTTP_PROXY=http://192.168.2.88:10809 \
#     -t china-study-free --load .
#
#   # 轻量镜像（~50MB，跳过 1.4GB 资源下载，运行时用 volume 挂载）
#   docker buildx build --platform linux/arm/v7 \
#     --build-arg SKIP_ASSETS=true \
#     -t china-study-free:lite --load .
# ================================================================

# ---- Build stage：在宿主机原生平台运行（避免 QEMU 模拟，构建快）----
FROM --platform=$BUILDPLATFORM node:22-alpine AS builder

# 代理支持（国内构建可传入 http://192.168.2.88:10809）
ARG HTTP_PROXY=""
ARG HTTPS_PROXY=""
ENV http_proxy=$HTTP_PROXY \
    https_proxy=$HTTPS_PROXY \
    NO_PROXY=localhost,127.0.0.1

# 构建工具：python3（解压 zip）、curl、tar、bash
RUN apk add --no-cache python3 curl tar bash

WORKDIR /app

# 先复制 workspace 配置和子包 package.json，利用 Docker 层缓存
COPY package.json package-lock.json ./
COPY apps/web/package.json apps/web/package.json
COPY packages/core/package.json packages/core/package.json

RUN npm ci --no-audit --no-fund

# 复制源码（output/ 里的 outlines + quizzes 也在此步进入）
COPY . .

# ---- 资源下载 ----
# SKIP_ASSETS=false（默认）：下载全部资源 ~1.4GB，镜像自包含
# SKIP_ASSETS=true：仅下载预构建 data.zip (~4MB)，音频/图片用 volume 挂载
ARG SKIP_ASSETS=false
ARG RELEASE_URL="https://github.com/wuwangzhang1216/ChinaTextbookStudyFree/releases/latest/download"
RUN if [ "$SKIP_ASSETS" = "false" ]; then \
      bash scripts/download-assets.sh; \
    else \
      echo ">> 轻量模式：仅下载预构建 data.zip (~4MB)" && \
      mkdir -p apps/web/public/data && \
      curl -sL "${RELEASE_URL}/data.zip" -o /tmp/data.zip && \
      printf 'import zipfile,os\nwith zipfile.ZipFile("/tmp/data.zip") as z:\n    for name in z.namelist():\n        fixed=name.replace(chr(92),"/")\n        target=os.path.join("apps/web/public/data",fixed)\n        if fixed.endswith("/"):\n            os.makedirs(target,exist_ok=True)\n            continue\n        os.makedirs(os.path.dirname(target),exist_ok=True)\n        with z.open(name) as sf,open(target,"wb") as df:\n            df.write(sf.read())\n' > /tmp/extract.py && \
      python3 /tmp/extract.py && \
      rm /tmp/extract.py /tmp/data.zip && \
      echo ">> 音频/图片/课本原页请通过 volume 挂载（见 docker-compose.yml）"; \
    fi

# ---- 构建 ----
# 完整模式：npm run build = build:data + next build（从 output/ + data/ 重新生成数据）
# 轻量模式：npx next build（跳过 build:data，直接使用预构建的 data.zip）
WORKDIR /app/apps/web
RUN if [ "$SKIP_ASSETS" = "false" ]; then \
      npm run build; \
    else \
      npx next build; \
    fi

# ---- Runtime stage：目标平台（支持 linux/arm/v7）----
FROM nginx:stable-alpine

LABEL org.opencontainers.image.title="ChinaStudyFree"
LABEL org.opencontainers.image.description="小学全科 AI 学习平台（Web 端）"
LABEL org.opencontainers.image.licenses="MIT"

# curl + unzip：entrypoint 首次启动时自动下载音频/图片资源
RUN apk add --no-cache curl unzip

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# 静态导出产物（含 HTML/CSS/JS + data/）
COPY --from=builder /app/apps/web/out /usr/share/nginx/html

EXPOSE 80

ENTRYPOINT ["/docker-entrypoint.sh"]
