#!/bin/sh
set -e

# ================================================================
# ChinaStudyFree · 容器入口脚本
#
# 首次启动时自动从 GitHub Release 下载音频/图片资源到 HTML 根目录。
# 后续启动检测到资源已存在则跳过。资源通过 Docker volume 持久化。
#
# 环境变量：
#   RELEASE_URL  — Release 下载基地址（可用镜像替换）
#   HTTP_PROXY   — 代理地址（国内推荐 http://192.168.2.88:10809）
#   SKIP_DOWNLOAD — 设为 true 则跳过资源下载（纯前端体验）
# ================================================================

RELEASE_URL="${RELEASE_URL:-https://github.com/wuwangzhang1216/ChinaTextbookStudyFree/releases/latest/download}"
HTML_ROOT="/usr/share/nginx/html"
SKIP_DOWNLOAD="${SKIP_DOWNLOAD:-false}"

# 下载文件（含 3 次重试）
download_file() {
    url="$1"
    output="$2"
    label="$3"
    for attempt in 1 2 3; do
        echo "  [$label] 尝试 $attempt/3..."
        if curl -fL --connect-timeout 30 --max-time 3600 -o "$output" "$url" 2>&1; then
            return 0
        fi
        echo "  [$label] 下载失败，${attempt}/3"
        [ $attempt -lt 3 ] && sleep 5
    done
    echo "  [$label] ✗ 下载失败，请检查网络或代理设置"
    return 1
}

# 解压 zip 并修复 Windows 反斜杠路径
extract_zip() {
    zip_path="$1"
    dest="$2"
    mkdir -p "$dest"
    cd "$dest"
    unzip -oq "$zip_path" 2>/dev/null || true
    # 修复 Windows 反斜杠路径：books\g1up\file.json → books/g1up/file.json
    find . -name '*\\*' -type f 2>/dev/null | while IFS= read -r f; do
        newpath=$(printf '%s' "$f" | tr '\\' '/')
        mkdir -p "$(dirname "$newpath")"
        mv "$f" "$newpath" 2>/dev/null || true
    done
    find . -name '*\\*' -type d -empty -delete 2>/dev/null || true
    cd /
}

if [ "$SKIP_DOWNLOAD" = "true" ]; then
    echo "=== SKIP_DOWNLOAD=true，跳过资源下载 ==="
    exec nginx -g 'daemon off;'
fi

echo "=== ChinaStudyFree 资源检查 ==="

# ---- 1. 音频 (~870MB, tar.gz) ----
if [ ! -d "$HTML_ROOT/audio" ] || [ -z "$(ls -A "$HTML_ROOT/audio" 2>/dev/null)" ]; then
    echo "[1/3] 下载音频文件 (~870MB)..."
    if download_file "$RELEASE_URL/audio.tar.gz" /tmp/audio.tar.gz "audio"; then
        tar xzf /tmp/audio.tar.gz -C "$HTML_ROOT"
        rm -f /tmp/audio.tar.gz
        count=$(find "$HTML_ROOT/audio" -name '*.opus' 2>/dev/null | wc -l)
        echo "  ✓ 完成 ($count 个音频)"
    fi
else
    echo "[1/3] ✓ 音频已存在，跳过"
fi

# ---- 2. 课本原页 (~192MB, zip) ----
if [ ! -d "$HTML_ROOT/textbook-pages" ] || [ -z "$(ls -A "$HTML_ROOT/textbook-pages" 2>/dev/null)" ]; then
    echo "[2/3] 下载课本原页 (~192MB)..."
    if download_file "$RELEASE_URL/textbook-pages.zip" /tmp/textbook-pages.zip "pages"; then
        extract_zip /tmp/textbook-pages.zip "$HTML_ROOT"
        rm -f /tmp/textbook-pages.zip
        echo "  ✓ 完成"
    fi
else
    echo "[2/3] ✓ 课本原页已存在，跳过"
fi

# ---- 3. 故事配图 (~368MB, zip) ----
if [ ! -d "$HTML_ROOT/story-images" ] || [ -z "$(ls -A "$HTML_ROOT/story-images" 2>/dev/null)" ]; then
    echo "[3/3] 下载故事配图 (~368MB)..."
    if download_file "$RELEASE_URL/story-images.zip" /tmp/story-images.zip "stories"; then
        extract_zip /tmp/story-images.zip "$HTML_ROOT"
        rm -f /tmp/story-images.zip
        echo "  ✓ 完成"
    fi
else
    echo "[3/3] ✓ 故事配图已存在，跳过"
fi

echo "=== 资源就绪，启动 nginx ==="

exec nginx -g 'daemon off;'
