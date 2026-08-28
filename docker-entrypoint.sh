#!/bin/sh
set -e

# ================================================================
# ChinaStudyFree · 容器入口脚本
#
# 先启动 nginx（立即可访问 Web 页面），后台下载音频/图片资源。
# 下载完成后自动 reload nginx，资源通过 Docker volume 持久化。
#
# 环境变量：
#   RELEASE_URL  — Release 下载基地址（可用镜像替换）
#   HTTP_PROXY   — 代理地址（国内推荐 http://192.168.2.88:10809）
#   SKIP_DOWNLOAD — 设为 true 则跳过资源下载（纯前端体验）
# ================================================================

RELEASE_URL="${RELEASE_URL:-https://github.com/pelico/ChinaTextbookStudyFree/releases/latest/download}"
HTML_ROOT="/usr/share/nginx/html"
SKIP_DOWNLOAD="${SKIP_DOWNLOAD:-false}"

# ---- 先启动 nginx（后台模式，Web 立即可用）----
echo "=== 启动 nginx（Web 立即可用）==="
nginx

# ---- 资源下载（后台执行，下载完后 reload nginx）----
download_and_serve() {
    url="$1"
    tmpfile="$2"
    label="$3"
    extract_cmd="$4"

    for attempt in 1 2 3; do
        echo "  [$label] 尝试 $attempt/3..."
        if curl -fL --connect-timeout 30 --max-time 3600 -o "$tmpfile" "$url" 2>&1; then
            echo "  [$label] 下载完成，解压中..."
            eval "$extract_cmd"
            rm -f "$tmpfile"
            nginx -s reload 2>/dev/null || true
            echo "  [$label] ✓ 已就绪"
            return 0
        fi
        echo "  [$label] 下载失败，${attempt}/3"
        [ $attempt -lt 3 ] && sleep 5
    done
    echo "  [$label] ✗ 下载失败，请检查网络或代理设置（页面仍可访问，音频/图片不可用）"
    return 1
}

# 解压 zip 并修复 Windows 反斜杠路径
extract_zip() {
    zip_path="$1"
    dest="$2"
    mkdir -p "$dest"
    cd "$dest"
    unzip -oq "$zip_path" 2>/dev/null || true
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
else
    echo "=== 后台下载资源（Web 页面已可访问）==="

    (
        # 1. 音频 (~870MB)
        if [ ! -d "$HTML_ROOT/audio" ] || [ -z "$(ls -A "$HTML_ROOT/audio" 2>/dev/null)" ]; then
            echo "[1/3] 下载音频 (~870MB)..."
            download_and_serve \
                "$RELEASE_URL/audio.tar.gz" \
                /tmp/audio.tar.gz \
                "audio" \
                "tar xzf /tmp/audio.tar.gz -C \"$HTML_ROOT\""
        else
            echo "[1/3] ✓ 音频已存在，跳过"
        fi

        # 2. 课本原页 (~192MB)
        if [ ! -d "$HTML_ROOT/textbook-pages" ] || [ -z "$(ls -A "$HTML_ROOT/textbook-pages" 2>/dev/null)" ]; then
            echo "[2/3] 下载课本原页 (~192MB)..."
            download_and_serve \
                "$RELEASE_URL/textbook-pages.zip" \
                /tmp/textbook-pages.zip \
                "pages" \
                "extract_zip /tmp/textbook-pages.zip \"$HTML_ROOT\""
        else
            echo "[2/3] ✓ 课本原页已存在，跳过"
        fi

        # 3. 故事配图 (~368MB)
        if [ ! -d "$HTML_ROOT/story-images" ] || [ -z "$(ls -A "$HTML_ROOT/story-images" 2>/dev/null)" ]; then
            echo "[3/3] 下载故事配图 (~368MB)..."
            download_and_serve \
                "$RELEASE_URL/story-images.zip" \
                /tmp/story-images.zip \
                "stories" \
                "extract_zip /tmp/story-images.zip \"$HTML_ROOT\""
        else
            echo "[3/3] ✓ 故事配图已存在，跳过"
        fi

        echo "=== 资源下载流程结束 ==="
    ) &
fi

# ---- 保持容器运行 ----
wait
