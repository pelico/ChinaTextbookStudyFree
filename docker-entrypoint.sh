#!/bin/sh
# 注意：不使用 set -e，后台下载失败不应导致 nginx 退出

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

# 代理设置（curl 会自动读取 HTTP_PROXY / HTTPS_PROXY 环境变量）
if [ -n "$HTTP_PROXY" ] && [ -z "$HTTPS_PROXY" ]; then
    export HTTPS_PROXY="$HTTP_PROXY"
fi
if [ -n "$http_proxy" ] && [ -z "$https_proxy" ]; then
    export https_proxy="$http_proxy"
fi

# 脱敏显示代理地址
mask_proxy() {
    if [ -z "$1" ]; then
        echo ""
    else
        echo "$1" | sed -E 's|(https?://)([^/:@]+@)?([^/:]+)(:[0-9]+)?/.*|\1\3\4|'
    fi
}

PROXY_DISPLAY=""
if [ -n "$HTTPS_PROXY" ]; then
    PROXY_DISPLAY=$(mask_proxy "$HTTPS_PROXY")
elif [ -n "$HTTP_PROXY" ]; then
    PROXY_DISPLAY=$(mask_proxy "$HTTP_PROXY")
fi

# ---- 写入状态文件 ----
write_status() {
    cat > "$STATUS_FILE" << EOF
{
  "audio": "${AUDIO_STATUS:-pending}",
  "audioFiles": ${AUDIO_COUNT:-0},
  "audioPercent": ${AUDIO_PERCENT:-0},
  "audioDownloaded": "${AUDIO_DOWNLOADED:-}",
  "audioTotal": "${AUDIO_TOTAL:-}",
  "audioError": "${AUDIO_ERROR:-}",
  "textbookPages": "${PAGES_STATUS:-pending}",
  "pageFiles": ${PAGES_COUNT:-0},
  "pagesPercent": ${PAGES_PERCENT:-0},
  "pagesDownloaded": "${PAGES_DOWNLOADED:-}",
  "pagesTotal": "${PAGES_TOTAL:-}",
  "pagesError": "${PAGES_ERROR:-}",
  "storyImages": "${STORIES_STATUS:-pending}",
  "storyFiles": ${STORIES_COUNT:-0},
  "storiesPercent": ${STORIES_PERCENT:-0},
  "storiesDownloaded": "${STORIES_DOWNLOADED:-}",
  "storiesTotal": "${STORIES_TOTAL:-}",
  "storiesError": "${STORIES_ERROR:-}",
  "proxy": "${PROXY_DISPLAY}",
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

# 格式化字节数为人类可读格式
human_bytes() {
    bytes=$1
    if [ "$bytes" -lt 1024 ]; then
        echo "${bytes}B"
    elif [ "$bytes" -lt 1048576 ]; then
        echo "$((bytes / 1024))KB"
    elif [ "$bytes" -lt 1073741824 ]; then
        echo "$((bytes / 1048576))MB"
    else
        echo "$((bytes / 1073741824)).$(( (bytes % 1073741824) * 10 / 1073741824 ))GB"
    fi
}

# 获取文件大小（字节）
file_size() {
    if [ -f "$1" ]; then
        wc -c < "$1" | tr -d ' '
    else
        echo 0
    fi
}

# 初始化状态
AUDIO_STATUS="pending"
PAGES_STATUS="pending"
STORIES_STATUS="pending"
AUDIO_PERCENT=0
PAGES_PERCENT=0
STORIES_PERCENT=0
AUDIO_COUNT=$(count_files "$HTML_ROOT/audio")
PAGES_COUNT=$(count_files "$HTML_ROOT/textbook-pages")
STORIES_COUNT=$(count_files "$HTML_ROOT/story-images")

# 如果已有文件，标记为 ready
if [ "$AUDIO_COUNT" -gt 0 ]; then
    AUDIO_STATUS="ready"
    AUDIO_PERCENT=100
fi
if [ "$PAGES_COUNT" -gt 0 ]; then
    PAGES_STATUS="ready"
    PAGES_PERCENT=100
fi
if [ "$STORIES_COUNT" -gt 0 ]; then
    STORIES_STATUS="ready"
    STORIES_PERCENT=100
fi

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

# ---- 获取远程文件大小 ----
get_remote_size() {
    url="$1"
    # 用 HEAD 请求获取 Content-Length，失败则返回空
    size=$(curl -sIL --connect-timeout 10 "$url" 2>/dev/null \
        | grep -i 'content-length' \
        | tail -1 \
        | tr -d '\r' \
        | awk '{print $2}' \
        | tr -d ' ')
    if [ -n "$size" ] && [ "$size" -gt 0 ] 2>/dev/null; then
        echo "$size"
    else
        echo ""
    fi
}

# ---- 带进度跟踪的下载 ----
# 参数: url output label total_size_var status_var percent_var downloaded_var total_var error_var
download_with_progress() {
    url="$1"
    output="$2"
    label="$3"
    _status_var="$4"
    _percent_var="$5"
    _downloaded_var="$6"
    _total_var="$7"
    _error_var="$8"

    # 先获取文件总大小
    total_size=$(get_remote_size "$url")
    if [ -n "$total_size" ]; then
        eval "$_total_var=\"$(human_bytes $total_size)\""
        echo "  [$label] 文件大小：$(human_bytes $total_size)"
    else
        eval "$_total_var=\"未知\""
        echo "  [$label] 无法获取文件大小，将不显示进度百分比"
    fi

    # 清理旧文件
    rm -f "$output"

    # 后台启动 curl 下载
    curl -fL --connect-timeout 30 --max-time 3600 \
         -o "$output" "$url" > /tmp/curl-${label}.log 2>&1 &
    curl_pid=$!

    # 进度监控循环
    last_size=0
    stall_count=0
    while kill -0 "$curl_pid" 2>/dev/null; do
        sleep 3

        current_size=$(file_size "$output")
        eval "$_downloaded_var=\"$(human_bytes $current_size)\""

        if [ -n "$total_size" ] && [ "$total_size" -gt 0 ]; then
            percent=$(( current_size * 100 / total_size ))
            if [ "$percent" -gt 100 ]; then percent=100; fi
            eval "$_percent_var=\"$percent\""
        fi

        # 检查是否卡住（30秒内没有增长）
        if [ "$current_size" -eq "$last_size" ]; then
            stall_count=$((stall_count + 1))
        else
            stall_count=0
        fi
        last_size=$current_size

        # 如果卡住超过 60 秒（20次检查 * 3秒），且还没完成，判定为网络问题
        if [ "$stall_count" -ge 20 ] && [ -n "$total_size" ] && [ "$current_size" -lt "$total_size" ]; then
            echo "  [$label] 下载卡住超过 60 秒，可能网络或代理有问题"
            kill "$curl_pid" 2>/dev/null || true
            wait "$curl_pid" 2>/dev/null || true
            eval "$_error_var=\"下载卡住 60 秒无响应，请检查网络或代理设置\""
            return 1
        fi

        write_status
    done

    # 等待 curl 真正结束并获取退出码
    wait "$curl_pid" 2>/dev/null && curl_exit=0 || curl_exit=$?

    if [ "$curl_exit" -eq 0 ] && [ -f "$output" ]; then
        final_size=$(file_size "$output")
        eval "$_percent_var=100"
        eval "$_downloaded_var=\"$(human_bytes $final_size)\""
        if [ -z "$total_size" ]; then
            eval "$_total_var=\"$(human_bytes $final_size)\""
        fi
        write_status
        return 0
    else
        # 读取 curl 错误日志
        err_msg=$(cat /tmp/curl-${label}.log 2>/dev/null | tail -3 | tr '\n' ' ' | sed 's/"/\\"/g')
        if [ -z "$err_msg" ]; then
            err_msg="下载失败（退出码 $curl_exit），请检查网络或代理设置"
        fi
        eval "$_error_var=\"$err_msg\""
        echo "  [$label] 下载失败：$err_msg"
        rm -f "$output"
        return 1
    fi
}

# ---- 下载 + 进度 + 重试 + 解压 + reload + 状态更新 ----
download_and_serve() {
    url="$1"
    tmpfile="$2"
    label="$3"
    extract_func="$4"
    status_var="$5"
    count_var="$6"
    check_dir="$7"
    percent_var="$8"
    downloaded_var="$9"
    total_var="${10}"
    error_var="${11}"

    # 更新状态为 downloading
    eval "$status_var=\"downloading\""
    eval "$percent_var=0"
    eval "$error_var=\"\""
    write_status

    success=0
    for attempt in 1 2 3; do
        echo "  [$label] 尝试 $attempt/3..."
        if download_with_progress "$url" "$tmpfile" "$label" \
            "$status_var" "$percent_var" "$downloaded_var" "$total_var" "$error_var"; then
            success=1
            break
        fi
        echo "  [$label] 第 $attempt 次失败"
        if [ $attempt -lt 3 ]; then
            eval "$status_var=\"downloading\""
            eval "$percent_var=0"
            write_status
            sleep 5
        fi
    done

    if [ "$success" -eq 1 ]; then
        echo "  [$label] 下载完成，解压中..."
        "$extract_func" "$tmpfile" "$HTML_ROOT"
        rm -f "$tmpfile"

        # 解压后验证文件数
        file_count=$(count_files "$check_dir")
        if [ "$file_count" -gt 0 ]; then
            eval "$status_var=\"ready\""
            eval "$count_var=\"$file_count\""
            eval "$percent_var=100"
            eval "$error_var=\"\""
            nginx -s reload 2>/dev/null || true
            echo "  [$label] ✓ 已就绪（$file_count 个文件）"
            write_status
            return 0
        else
            eval "$status_var=\"error\""
            eval "$error_var=\"解压后目录为空，请检查 zip 文件结构\""
            echo "  [$label] ✗ 解压后目录为空"
            write_status
            return 1
        fi
    else
        eval "$status_var=\"error\""
        echo "  [$label] ✗ 下载失败（页面仍可访问）"
        write_status
        return 1
    fi
}

# ================================================================
# 迷你 HTTP API 服务（处理重试请求）
# 监听 127.0.0.1:18080，通过 nginx 反代到 /api/
# ================================================================
RETRY_FLAG_DIR="/tmp/cstf-retry"
mkdir -p "$RETRY_FLAG_DIR"

start_api_server() {
    (
        FIFO="/tmp/cstf-api.fifo"
        rm -f "$FIFO"
        mkfifo "$FIFO"

        while true; do
            # 用 fifo 实现请求-响应模式
            # nc 读取客户端请求写入 fifo，同时从 fifo 读取响应发回客户端
            (
                # 先读请求
                read -r first_line
                path=$(echo "$first_line" | awk '{print $2}')

                # 处理请求
                case "$path" in
                    *retry*resource=audio*)
                        touch "$RETRY_FLAG_DIR/audio"
                        echo "[API] 收到音频重试请求"
                        ;;
                    *retry*resource=pages*)
                        touch "$RETRY_FLAG_DIR/pages"
                        echo "[API] 收到课本原页重试请求"
                        ;;
                    *retry*resource=stories*)
                        touch "$RETRY_FLAG_DIR/stories"
                        echo "[API] 收到故事配图重试请求"
                        ;;
                    *retry*resource=all*)
                        touch "$RETRY_FLAG_DIR/audio"
                        touch "$RETRY_FLAG_DIR/pages"
                        touch "$RETRY_FLAG_DIR/stories"
                        echo "[API] 收到全部重试请求"
                        ;;
                esac

                # 读完剩余请求头
                while IFS= read -r line; do
                    line=$(printf '%s' "$line" | tr -d '\r')
                    [ -z "$line" ] && break
                done

                # 输出 HTTP 响应
                printf 'HTTP/1.1 200 OK\r\n'
                printf 'Content-Type: application/json\r\n'
                printf 'Content-Length: 11\r\n'
                printf 'Access-Control-Allow-Origin: *\r\n'
                printf 'Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n'
                printf 'Access-Control-Allow-Headers: Content-Type\r\n'
                printf 'Connection: close\r\n'
                printf '\r\n'
                printf '{"ok":true}'
            ) < "$FIFO" | nc -l 127.0.0.1 18080 > "$FIFO" 2>/dev/null

            sleep 0.1
        done
    ) &
    echo "=== API 服务已启动（127.0.0.1:18080）==="
}

# ================================================================
# 后台下载资源（nginx 启动后 Web 立即可用，资源在后台逐步就绪）
# 支持通过 flag 文件触发重试
# ================================================================
start_background_download() {
    if [ "$SKIP_DOWNLOAD" = "true" ]; then
        echo "=== SKIP_DOWNLOAD=true，跳过资源下载 ==="
        AUDIO_STATUS="skipped"
        PAGES_STATUS="skipped"
        STORIES_STATUS="skipped"
        AUDIO_PERCENT=100
        PAGES_PERCENT=100
        STORIES_PERCENT=100
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
            AUDIO_PERCENT=100
            PAGES_PERCENT=100
            STORIES_PERCENT=100
            write_status
            exit 0
        fi

        # ---- 下载单个资源的封装 ----
        do_download_audio() {
            if [ ! -d "$HTML_ROOT/audio" ] || [ -z "$(ls -A "$HTML_ROOT/audio" 2>/dev/null)" ]; then
                download_and_serve \
                    "$RELEASE_URL/audio.tar.gz" \
                    /tmp/audio.tar.gz \
                    "audio" \
                    extract_tar_gz \
                    AUDIO_STATUS \
                    AUDIO_COUNT \
                    "$HTML_ROOT/audio" \
                    AUDIO_PERCENT \
                    AUDIO_DOWNLOADED \
                    AUDIO_TOTAL \
                    AUDIO_ERROR
            else
                AUDIO_STATUS="ready"
                AUDIO_PERCENT=100
                AUDIO_COUNT=$(count_files "$HTML_ROOT/audio")
            fi
        }

        do_download_pages() {
            if [ ! -d "$HTML_ROOT/textbook-pages" ] || [ -z "$(ls -A "$HTML_ROOT/textbook-pages" 2>/dev/null)" ]; then
                download_and_serve \
                    "$RELEASE_URL/textbook-pages.zip" \
                    /tmp/textbook-pages.zip \
                    "pages" \
                    extract_zip \
                    PAGES_STATUS \
                    PAGES_COUNT \
                    "$HTML_ROOT/textbook-pages" \
                    PAGES_PERCENT \
                    PAGES_DOWNLOADED \
                    PAGES_TOTAL \
                    PAGES_ERROR
            else
                PAGES_STATUS="ready"
                PAGES_PERCENT=100
                PAGES_COUNT=$(count_files "$HTML_ROOT/textbook-pages")
            fi
        }

        do_download_stories() {
            if [ ! -d "$HTML_ROOT/story-images" ] || [ -z "$(ls -A "$HTML_ROOT/story-images" 2>/dev/null)" ]; then
                download_and_serve \
                    "$RELEASE_URL/story-images.zip" \
                    /tmp/story-images.zip \
                    "stories" \
                    extract_zip \
                    STORIES_STATUS \
                    STORIES_COUNT \
                    "$HTML_ROOT/story-images" \
                    STORIES_PERCENT \
                    STORIES_DOWNLOADED \
                    STORIES_TOTAL \
                    STORIES_ERROR
            else
                STORIES_STATUS="ready"
                STORIES_PERCENT=100
                STORIES_COUNT=$(count_files "$HTML_ROOT/story-images")
            fi
        }

        # 初始下载
        echo "[1/3] 下载音频..."
        do_download_audio
        echo "[2/3] 下载课本原页..."
        do_download_pages
        echo "[3/3] 下载故事配图..."
        do_download_stories
        echo "=== 初始下载流程结束，进入监听重试模式 ==="

        # ---- 重试监听循环（每 5 秒检查一次 flag 文件）----
        while true; do
            sleep 5

            if [ -f "$RETRY_FLAG_DIR/audio" ] && [ "$AUDIO_STATUS" = "error" ]; then
                rm -f "$RETRY_FLAG_DIR/audio"
                echo "[重试] 重新下载音频..."
                # 清理旧的不完整文件
                rm -rf "$HTML_ROOT/audio"
                mkdir -p "$HTML_ROOT/audio"
                do_download_audio
                write_status
                nginx -s reload 2>/dev/null || true
            fi

            if [ -f "$RETRY_FLAG_DIR/pages" ] && [ "$PAGES_STATUS" = "error" ]; then
                rm -f "$RETRY_FLAG_DIR/pages"
                echo "[重试] 重新下载课本原页..."
                rm -rf "$HTML_ROOT/textbook-pages"
                mkdir -p "$HTML_ROOT/textbook-pages"
                do_download_pages
                write_status
                nginx -s reload 2>/dev/null || true
            fi

            if [ -f "$RETRY_FLAG_DIR/stories" ] && [ "$STORIES_STATUS" = "error" ]; then
                rm -f "$RETRY_FLAG_DIR/stories"
                echo "[重试] 重新下载故事配图..."
                rm -rf "$HTML_ROOT/story-images"
                mkdir -p "$HTML_ROOT/story-images"
                do_download_stories
                write_status
                nginx -s reload 2>/dev/null || true
            fi

            # 清理过期的 flag（状态不是 error 但有 flag）
            [ -f "$RETRY_FLAG_DIR/audio" ] && [ "$AUDIO_STATUS" != "error" ] && rm -f "$RETRY_FLAG_DIR/audio"
            [ -f "$RETRY_FLAG_DIR/pages" ] && [ "$PAGES_STATUS" != "error" ] && rm -f "$RETRY_FLAG_DIR/pages"
            [ -f "$RETRY_FLAG_DIR/stories" ] && [ "$STORIES_STATUS" != "error" ] && rm -f "$RETRY_FLAG_DIR/stories"
        done
    ) &
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

# ---- 启动后台下载 ----
start_background_download

# ---- 启动 API 服务（处理重试请求）----
start_api_server

# ---- 以前台模式启动 nginx（作为容器 1 号主进程，保持运行）----
echo "=== 启动 nginx（前台模式，作为容器主进程）==="
exec nginx -g 'daemon off;'
