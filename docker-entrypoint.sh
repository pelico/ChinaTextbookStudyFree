#!/bin/sh
set -e

# ================================================================
# ChinaStudyFree · 容器入口脚本
#
# 以前台模式启动 nginx（作为容器主进程，保持运行），
# 后台异步下载音频/图片资源，下载完成后自动 reload nginx。
# 资源通过 Docker volume 持久化，重启不重复下载。
#
# 状态文件：/usr/share/nginx/html/assets-status.json
#   前端可通过 GET /assets-status.json 查看资源下载状态。
#
# 环境变量：
#   RELEASE_URL   — Release 下载基地址（可用镜像替换）
#   HTTP_PROXY    — 代理地址（国内推荐 http://192.168.2.88:10809）
#   SKIP_DOWNLOAD — 设为 true 则跳过资源下载（纯前端体验）
# ================================================================

RELEASE_URL="${RELEASE_URL:-https://github.com/pelico/ChinaTextbookStudyFree/releases/latest/download}"
HTML_ROOT="/usr/share/nginx/html"
SKIP_DOWNLOAD="${SKIP_DOWNLOAD:-false}"
STATUS_FILE="$HTML_ROOT/assets-status.json"

# ---- 写入状态文件 ----
write_status() {
    cat > "$STATUS_FILE" << EOF
{
  "audio": ${AUDIO_STATUS:-"pending"},
  "audioFiles": ${AUDIO_COUNT:-0},
  "textbookPages": ${PAGES_STATUS:-"pending"},
  "pageFiles": ${PAGES_COUNT:-0},
  "storyImages": ${STORIES_STATUS:-"pending"},
  "storyFiles": ${STORIES_COUNT:-0},
  "updatedAt": "$(date -Iseconds)"
}
EOF
}

# 统计目录文件数（递归）
count_files() {
    if [ -d "$1" ]; then
        find "$1" -type f 2>/dev/null | wc -l | tr -d ' '
    else
        echo 0
    fi
}

# 初始化状态
AUDIO_STATUS="pending"
PAGES_STATUS="pending"
STORIES_STATUS="pending"
AUDIO_COUNT=$(count_files "$HTML_ROOT/audio")
PAGES_COUNT=$(count_files "$HTML_ROOT/textbook-pages")
STORIES_COUNT=$(count_files "$HTML_ROOT/story-images")

# 如果已有文件，标记为 ready
[ "$AUDIO_COUNT" -gt 0 ] && AUDIO_STATUS="ready"
[ "$PAGES_COUNT" -gt 0 ] && PAGES_STATUS="ready"
[ "$STORIES_COUNT" -gt 0 ] && STORIES_STATUS="ready"

mkdir -p "$HTML_ROOT"
write_status

# ---- 磁盘空间检查 ----
check_disk_space() {
    available_kb=$(df -k "$HTML_ROOT" | awk 'NR==2 {print $4}')
    available_mb=$((available_kb / 1024))
    min_required_mb=2000

    if [ "$available_mb" -lt "$min_required_mb" ]; then
        echo "⚠ 磁盘空间不足：可用 ${available_mb}MB，至少需要 ${min_required_mb}MB"
        echo "  资源下载已跳过，Web 页面仍可访问（音频/图片不可用）"
        return 1
    fi
    echo "  磁盘空间检查：可用 ${available_mb}MB ✓"
    return 0
}

# ---- 下载文件（3 次重试）----
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

# ---- 解压 tar.gz ----
extract_tar_gz() {
    tar xzf "$1" -C "$2"
}

# ---- 解压 zip（修复 Windows 反斜杠路径）----
extract_zip() {
    zip_path="$1"
    dest="$2"
    mkdir -p "$dest"
    (
        cd "$dest"
        unzip -oq "$zip_path" 2>/dev/null || true
        find . -name '*\\*' -type f 2>/dev/null | while IFS= read -r f; do
            newpath=$(printf '%s' "$f" | tr '\\' '/')
            mkdir -p "$(dirname "$newpath")"
            mv "$f" "$newpath" 2>/dev/null || true
        done
        find . -name '*\\*' -type d -empty -delete 2>/dev/null || true
    )
}

# ---- 下载 + 解压 + reload + 状态更新 ----
download_and_serve() {
    url="$1"
    tmpfile="$2"
    label="$3"
    extract_func="$4"
    status_var="$5"
    count_var="$6"
    check_dir="$7"

    # 更新状态为 downloading
    eval "$status_var=\"downloading\""
    write_status

    if download_file "$url" "$tmpfile" "$label"; then
        echo "  [$label] 下载完成，解压中..."
        "$extract_func" "$tmpfile" "$HTML_ROOT"
        rm -f "$tmpfile"

        # 解压后验证文件数
        file_count=$(count_files "$check_dir")
        if [ "$file_count" -gt 0 ]; then
            eval "$status_var=\"ready\""
            eval "$count_var=\"$file_count\""
            nginx -s reload 2>/dev/null || true
            echo "  [$label] ✓ 已就绪（$file_count 个文件）"
            write_status
            return 0
        else
            eval "$status_var=\"error\""
            echo "  [$label] ✗ 解压后目录为空，请检查 zip 文件结构"
            write_status
            return 1
        fi
    fi
    eval "$status_var=\"error\""
    echo "  [$label] ✗ 资源不可用（页面仍可访问）"
    write_status
    return 1
}

# ================================================================
# 后台下载资源（nginx 启动后 Web 立即可用，资源在后台逐步就绪）
# ================================================================
start_background_download() {
    if [ "$SKIP_DOWNLOAD" = "true" ]; then
        echo "=== SKIP_DOWNLOAD=true，跳过资源下载 ==="
        AUDIO_STATUS="skipped"
        PAGES_STATUS="skipped"
        STORIES_STATUS="skipped"
        write_status
        return
    fi

    echo "=== 后台下载资源（Web 页面已可访问）==="

    (
        # 磁盘空间检查
        if ! check_disk_space; then
            AUDIO_STATUS="skipped"
            PAGES_STATUS="skipped"
            STORIES_STATUS="skipped"
            write_status
            exit 0
        fi

        # 1. 音频 (~870MB)
        if [ ! -d "$HTML_ROOT/audio" ] || [ -z "$(ls -A "$HTML_ROOT/audio" 2>/dev/null)" ]; then
            echo "[1/3] 下载音频 (~870MB)..."
            download_and_serve \
                "$RELEASE_URL/audio.tar.gz" \
                /tmp/audio.tar.gz \
                "audio" \
                extract_tar_gz \
                AUDIO_STATUS \
                AUDIO_COUNT \
                "$HTML_ROOT/audio"
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
                extract_zip \
                PAGES_STATUS \
                PAGES_COUNT \
                "$HTML_ROOT/textbook-pages"
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
                extract_zip \
                STORIES_STATUS \
                STORIES_COUNT \
                "$HTML_ROOT/story-images"
        else
            echo "[3/3] ✓ 故事配图已存在，跳过"
        fi

        echo "=== 资源下载流程结束 ==="
    ) &
}

# ---- 启动后台下载 ----
start_background_download

# ---- 以前台模式启动 nginx（作为容器 1 号主进程，保持运行）----
echo "=== 启动 nginx（前台模式，作为容器主进程）==="
exec nginx -g 'daemon off;'
