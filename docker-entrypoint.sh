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

# ---- 磁盘空间检查 ----
check_disk_space() {
    # 检查 HTML_ROOT 所在分区的可用空间（单位：KB）
    available_kb=$(df -k "$HTML_ROOT" | awk 'NR==2 {print $4}')
    available_mb=$((available_kb / 1024))
    # 预估总资源大小 ~1500MB，给 2000MB 缓冲
    min_required_mb=2000

    if [ "$available_mb" -lt "$min_required_mb" ]; then
        echo "⚠ 磁盘空间不足：可用 ${available_mb}MB，至少需要 ${min_required_mb}MB"
        echo "  资源下载已跳过，Web 页面仍可访问（音频/图片不可用）"
        return 1
    fi
    echo "  磁盘空间检查：可用 ${available_mb}MB ✓"
    return 0
}

# ---- 资源下载（后台执行，下载完后 reload nginx）----
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

# 解压 tar.gz
extract_tar_gz() {
    tar_path="$1"
    dest="$2"
    tar xzf "$tar_path" -C "$dest"
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

download_and_serve() {
    url="$1"
    tmpfile="$2"
    label="$3"
    extract_func="$4"

    if download_file "$url" "$tmpfile" "$label"; then
        echo "  [$label] 下载完成，解压中..."
        "$extract_func" "$tmpfile" "$HTML_ROOT"
        rm -f "$tmpfile"
        nginx -s reload 2>/dev/null || true
        echo "  [$label] ✓ 已就绪"
        return 0
    fi
    echo "  [$label] ✗ 资源不可用（页面仍可访问）"
    return 1
}

if [ "$SKIP_DOWNLOAD" = "true" ]; then
    echo "=== SKIP_DOWNLOAD=true，跳过资源下载 ==="
else
    echo "=== 后台下载资源（Web 页面已可访问）==="

    (
        # 磁盘空间检查
        if ! check_disk_space; then
            exit 0
        fi

        # 1. 音频 (~870MB)
        if [ ! -d "$HTML_ROOT/audio" ] || [ -z "$(ls -A "$HTML_ROOT/audio" 2>/dev/null)" ]; then
            echo "[1/3] 下载音频 (~870MB)..."
            download_and_serve \
                "$RELEASE_URL/audio.tar.gz" \
                /tmp/audio.tar.gz \
                "audio" \
                extract_tar_gz
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
                extract_zip
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
                extract_zip
        else
            echo "[3/3] ✓ 故事配图已存在，跳过"
        fi

        echo "=== 资源下载流程结束 ==="
    ) &
fi

# ---- 保持容器运行 ----
wait
