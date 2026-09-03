#!/usr/bin/env python3
"""
custom_server.py — 自定义学习模块后端服务

零外部依赖：仅用 Python 标准库（http.server + sqlite3 + urllib.request）
功能：书本 CRUD、AI 识图生成大纲、AI 生成/刷新题目、题目版本管理
"""

import http.server
import json
import os
import re
import shutil
import sqlite3
import base64
import subprocess
import tempfile
import glob
import threading
import time
import uuid
import random
import urllib.request
import urllib.error
from datetime import datetime, timezone

# ============================================================
# Configuration
# ============================================================
DB_PATH = os.environ.get("CUSTOM_DB_PATH", "/data/custom.db")
IMAGES_DIR = os.environ.get("CUSTOM_IMAGES_DIR", "/data/images")
TEXTBOOKS_DIR = os.environ.get("CUSTOM_TEXTBOOKS_DIR", "/data/textbooks")
AI_BASE = os.environ.get("AI_API_BASE", "https://aiapi.fonken.net/v1")
AI_KEY = os.environ.get("AI_API_KEY", "")
AI_MODEL = os.environ.get("AI_MODEL", "gemini-3.1-flash-lite")
PORT = int(os.environ.get("CUSTOM_API_PORT", "18081"))
MAX_BODY = 60 * 1024 * 1024  # 60MB

db_lock = threading.Lock()

# ============================================================
# Proxy
# ============================================================
_proxy_handler = None
_http_p = os.environ.get("HTTP_PROXY", "") or os.environ.get("http_proxy", "")
_https_p = os.environ.get("HTTPS_PROXY", "") or os.environ.get("https_proxy", "")
if _http_p or _https_p:
    _proxy_handler = urllib.request.ProxyHandler({
        "http": _http_p,
        "https": _https_p or _http_p,
    })


def _urlopen(req, timeout=120):
    if _proxy_handler:
        opener = urllib.request.build_opener(_proxy_handler)
        return opener.open(req, timeout=timeout)
    return urllib.request.urlopen(req, timeout=timeout)


# ============================================================
# Database
# ============================================================
def get_db():
    conn = sqlite3.connect(DB_PATH, timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


def init_db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    os.makedirs(IMAGES_DIR, exist_ok=True)
    conn = get_db()
    conn.executescript("""
    CREATE TABLE IF NOT EXISTS books (
        id          TEXT PRIMARY KEY,
        title       TEXT NOT NULL,
        subject     TEXT NOT NULL,
        grade       INTEGER NOT NULL,
        semester    TEXT NOT NULL,
        source_type TEXT DEFAULT 'photo',
        cover_image TEXT,
        created_at  TEXT NOT NULL,
        updated_at  TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS units (
        id           TEXT PRIMARY KEY,
        book_id      TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
        unit_number  INTEGER NOT NULL,
        title        TEXT NOT NULL,
        sort_order   INTEGER DEFAULT 0
    );
    CREATE INDEX IF NOT EXISTS idx_units_book ON units(book_id);

    CREATE TABLE IF NOT EXISTS knowledge_points (
        id             TEXT PRIMARY KEY,
        unit_id        TEXT NOT NULL REFERENCES units(id) ON DELETE CASCADE,
        name           TEXT NOT NULL,
        description    TEXT,
        difficulty     INTEGER DEFAULT 3,
        question_types TEXT DEFAULT '[]',
        sort_order     INTEGER DEFAULT 0,
        source         TEXT DEFAULT 'ai',
        created_at     TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_kp_unit ON knowledge_points(unit_id);

    CREATE TABLE IF NOT EXISTS question_sets (
        id           TEXT PRIMARY KEY,
        kp_id        TEXT NOT NULL REFERENCES knowledge_points(id) ON DELETE CASCADE,
        version      INTEGER NOT NULL,
        questions    TEXT NOT NULL,
        is_active    INTEGER DEFAULT 1,
        ai_model     TEXT,
        generated_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_qs_kp ON question_sets(kp_id);
    CREATE INDEX IF NOT EXISTS idx_qs_active ON question_sets(kp_id, is_active);

    CREATE TABLE IF NOT EXISTS page_images (
        id          TEXT PRIMARY KEY,
        book_id     TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
        unit_id      TEXT,
        filename    TEXT NOT NULL,
        ocr_text    TEXT,
        page_number INTEGER,
        created_at  TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_img_book ON page_images(book_id);
    """)

    # Schema migrations (SQLite 不支持 IF NOT EXISTS for ADD COLUMN)
    cols_page = {r[1] for r in conn.execute("PRAGMA table_info(page_images)")}
    if "kp_id" not in cols_page:
        conn.execute("ALTER TABLE page_images ADD COLUMN kp_id TEXT")
    if "sort_idx" not in cols_page:
        conn.execute("ALTER TABLE page_images ADD COLUMN sort_idx INTEGER DEFAULT 0")

    cols_books = {r[1] for r in conn.execute("PRAGMA table_info(books)")}
    if "folder_path" not in cols_books:
        conn.execute("ALTER TABLE books ADD COLUMN folder_path TEXT")

    conn.execute("""
    CREATE TABLE IF NOT EXISTS page_texts (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        page_number INTEGER NOT NULL,
        text_content TEXT,
        created_at TEXT,
        UNIQUE(book_id, page_number)
    );
    """)
    conn.execute("CREATE INDEX IF NOT EXISTS idx_pt_book ON page_texts(book_id);")

    # 家长设置 + 进度同步表
    conn.execute("""
    CREATE TABLE IF NOT EXISTS parent_settings (
        id              INTEGER PRIMARY KEY DEFAULT 1,
        password_hash   TEXT,
        password_salt   TEXT,
        is_setup        INTEGER DEFAULT 0,
        ai_api_key      TEXT,
        ai_base_url     TEXT DEFAULT 'https://aiapi.fonken.net/v1',
        ai_model        TEXT DEFAULT 'gemini-3.1-flash-lite',
        daily_limit_ms  INTEGER DEFAULT 0,
        session_limit_ms INTEGER DEFAULT 0,
        updated_at      TEXT NOT NULL
    );
    """)
    conn.execute("""
    CREATE TABLE IF NOT EXISTS kids (
        id              TEXT PRIMARY KEY,
        name            TEXT NOT NULL,
        avatar          TEXT DEFAULT 'default',
        sort_order      INTEGER DEFAULT 0,
        created_at      TEXT NOT NULL
    );
    """)
    conn.execute("""
    CREATE TABLE IF NOT EXISTS progress_sync (
        id              TEXT PRIMARY KEY,
        kid_id          TEXT NOT NULL DEFAULT 'default',
        device_id       TEXT NOT NULL,
        device_name     TEXT,
        progress_json   TEXT NOT NULL,
        last_sync_at    TEXT NOT NULL,
        xp              INTEGER DEFAULT 0,
        gems            INTEGER DEFAULT 0
    );
    """)
    conn.execute("""
    CREATE TABLE IF NOT EXISTS audit_log (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id       TEXT,
        action          TEXT NOT NULL,
        detail          TEXT,
        created_at      TEXT NOT NULL
    );
    """)

    # Migration: old progress_sync may not have kid_id column
    cols_ps = {r[1] for r in conn.execute("PRAGMA table_info(progress_sync)")}
    if "kid_id" not in cols_ps:
        conn.execute("ALTER TABLE progress_sync ADD COLUMN kid_id TEXT NOT NULL DEFAULT 'default'")
    if "id" not in cols_ps:
        # Very old table had device_id as PK, add id column
        conn.execute("ALTER TABLE progress_sync ADD COLUMN id TEXT")
        conn.execute("UPDATE progress_sync SET id = 'default:' || device_id WHERE id IS NULL")

    conn.execute("CREATE INDEX IF NOT EXISTS idx_progress_kid ON progress_sync(kid_id)")
    conn.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_progress_kid_dev ON progress_sync(kid_id, device_id)")

    # 真题库
    conn.execute("""
    CREATE TABLE IF NOT EXISTS exams (
        id           TEXT PRIMARY KEY,
        title        TEXT NOT NULL,
        subject      TEXT NOT NULL,
        grade        INTEGER NOT NULL,
        semester     TEXT NOT NULL,
        difficulty   TEXT DEFAULT 'normal',
        text_content TEXT,
        total_pages  INTEGER DEFAULT 0,
        created_at   TEXT NOT NULL,
        updated_at   TEXT NOT NULL
    );
    """)
    conn.execute("""
    CREATE TABLE IF NOT EXISTS exam_pages (
        id           TEXT PRIMARY KEY,
        exam_id      TEXT NOT NULL REFERENCES exams(id) ON DELETE CASCADE,
        filename     TEXT NOT NULL,
        page_number  INTEGER,
        sort_idx     INTEGER DEFAULT 0,
        created_at   TEXT NOT NULL
    );
    """)
    conn.execute("CREATE INDEX IF NOT EXISTS idx_exam_pages ON exam_pages(exam_id);")

    # Migration: exams 表加 structure 字段（试卷结构分析结果 JSON）
    cols_exams = {r[1] for r in conn.execute("PRAGMA table_info(exams)")}
    if "structure" not in cols_exams:
        conn.execute("ALTER TABLE exams ADD COLUMN structure TEXT")
    if "analyze_status" not in cols_exams:
        conn.execute("ALTER TABLE exams ADD COLUMN analyze_status TEXT DEFAULT 'idle'")

    conn.commit()
    conn.close()


def now_iso():
    return datetime.now(timezone.utc).isoformat()


# ============================================================
# Parent auth & settings helpers
# ============================================================
import hashlib, secrets

_active_tokens = {}  # token -> expiry_ts

def hash_password(password, salt):
    return hashlib.sha256((password + salt).encode()).hexdigest()

def create_token():
    token = secrets.token_hex(16)
    _active_tokens[token] = time.time() + 1800  # 30 min
    return token

def verify_token(token):
    if not token:
        return False
    exp = _active_tokens.get(token)
    if not exp:
        return False
    if time.time() > exp:
        _active_tokens.pop(token, None)
        return False
    return True

def get_parent_settings():
    conn = get_db()
    try:
        row = conn.execute("SELECT * FROM parent_settings WHERE id = 1").fetchone()
        if not row:
            return None
        return dict(row)
    finally:
        conn.close()

def get_default_ai_key():
    """从 parent_settings 表读取默认 AI Key"""
    s = get_parent_settings()
    if s and s.get("ai_api_key"):
        return s["ai_api_key"].strip()
    return None


# ============================================================
# Kids (student profiles) CRUD
# ============================================================
def list_kids():
    conn = get_db()
    try:
        rows = conn.execute(
            "SELECT id, name, avatar, sort_order, created_at FROM kids ORDER BY sort_order, created_at"
        ).fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()

def create_kid(name, avatar="default"):
    kid_id = f"kid-{uuid.uuid4().hex[:8]}"
    now = now_iso()
    conn = get_db()
    try:
        conn.execute(
            "INSERT INTO kids (id, name, avatar, sort_order, created_at) VALUES (?, ?, ?, ?, ?)",
            (kid_id, name, avatar, int(time.time()) % 1000, now)
        )
        conn.commit()
        return {"id": kid_id, "name": name, "avatar": avatar, "sort_order": 0, "created_at": now}
    finally:
        conn.close()

def update_kid(kid_id, name=None, avatar=None):
    conn = get_db()
    try:
        updates, params = [], []
        if name is not None:
            updates.append("name = ?")
            params.append(name)
        if avatar is not None:
            updates.append("avatar = ?")
            params.append(avatar)
        if updates:
            params.append(kid_id)
            conn.execute(f"UPDATE kids SET {', '.join(updates)} WHERE id = ?", params)
            conn.commit()
    finally:
        conn.close()

def delete_kid(kid_id):
    conn = get_db()
    try:
        conn.execute("DELETE FROM progress_sync WHERE kid_id = ?", (kid_id,))
        conn.execute("DELETE FROM kids WHERE id = ?", (kid_id,))
        conn.commit()
    finally:
        conn.close()


def merge_progress(server_state, client_state):
    """跨设备进度合并：取最优值"""
    merged = dict(client_state)
    for key in ("xp", "gems", "streak", "lifetimeGems", "streakFreezes"):
        sv = server_state.get(key, 0) if server_state else 0
        cv = client_state.get(key, 0)
        merged[key] = max(sv, cv)
    for key in ("completedLessons", "mistakesBank", "unlockedAchievements",
                "xpHistory", "lessonHistory", "claimedQuests", "claimedChests",
                "completedReadings"):
        sv = server_state.get(key, {}) if server_state else {}
        cv = client_state.get(key, {})
        merged[key] = {**sv, **cv}
    # 今日数据取客户端值（本地实时更准）
    for key in ("todayXp", "todayTimeMs", "dailyLessons", "dailyReviews", "dailyReadings"):
        merged[key] = client_state.get(key, 0)
    return merged


# ============================================================
# AI API
# ============================================================
def call_ai(messages, timeout=120, api_key=None):
    """OpenAI 兼容 API 调用，返回 content 字符串。
    api_key 三层回退：header 传入 → DB 默认 → 环境变量。
    """
    key = api_key or get_default_ai_key() or AI_KEY
    if not key:
        raise RuntimeError("未配置 AI API Key，请在家长设置中配置默认 Key")

    url = AI_BASE.rstrip("/") + "/chat/completions"
    body = json.dumps({
        "model": AI_MODEL,
        "messages": messages,
        "temperature": 0.7,
        "stream": False,
        "max_tokens": 8192,
    }).encode("utf-8")

    req = urllib.request.Request(url, data=body, headers={
        "Content-Type": "application/json",
        "Authorization": f"Bearer {key}",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
        "Accept": "application/json",
    })

    try:
        resp = _urlopen(req, timeout=timeout)
        data = json.loads(resp.read().decode("utf-8"))
        content = data.get("choices", [{}])[0].get("message", {}).get("content", "")
        if not content:
            raise RuntimeError("AI 返回空内容，请检查模型名或 API Key")
        return content
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")[:300]
        raise RuntimeError(f"AI 接口错误 ({e.code}): {err_body}")
    except urllib.error.URLError as e:
        raise RuntimeError(f"AI 接口连接失败: {e.reason}")


def call_ai_vision(images_b64, text_prompt, timeout=120, api_key=None):
    """带图片的 Vision API 调用"""
    content = [{"type": "text", "text": text_prompt}]
    for img in images_b64:
        if not img.startswith("data:"):
            img = f"data:image/jpeg;base64,{img}"
        content.append({"type": "image_url", "image_url": {"url": img}})

    return call_ai([{"role": "user", "content": content}], timeout=timeout, api_key=api_key)


def parse_json_response(text):
    """从 AI 返回文本中提取 JSON（兼容 markdown 代码块包裹）"""
    text = text.strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*\n?", "", text)
        text = re.sub(r"\n?```\s*$", "", text)
    # 找到第一个 JSON 结构（{ 或 [）
    for i, ch in enumerate(text):
        if ch in "{[":
            text = text[i:]
            break
    # 找到最后一个 } 或 ]
    for i in range(len(text) - 1, -1, -1):
        if text[i] in "}]":
            text = text[:i+1]
            break
    return json.loads(text)


# ============================================================
# PDF → Images
# ============================================================
def convert_pdf_to_images(pdf_b64, max_pages=20):
    """将 PDF（base64）转换为 JPEG 图片列表（base64 data URL）"""
    raw = pdf_b64.split(",", 1)[-1] if "," in pdf_b64 else pdf_b64
    pdf_bytes = base64.b64decode(raw)

    images = []
    with tempfile.TemporaryDirectory() as tmpdir:
        pdf_path = os.path.join(tmpdir, "input.pdf")
        with open(pdf_path, "wb") as f:
            f.write(pdf_bytes)

        try:
            subprocess.run(
                ["pdftoppm", "-jpeg", "-r", "150", "-l", str(max_pages),
                 pdf_path, "page"],
                cwd=tmpdir, check=True, capture_output=True, timeout=60
            )
        except FileNotFoundError:
            raise RuntimeError("pdftoppm 未安装，无法处理 PDF")
        except subprocess.TimeoutExpired:
            raise RuntimeError("PDF 转换超时（超过 60 秒）")

        for img_path in sorted(glob.glob(os.path.join(tmpdir, "page-*.jpg"))):
            with open(img_path, "rb") as f:
                img_b64 = base64.b64encode(f.read()).decode("utf-8")
                images.append(f"data:image/jpeg;base64,{img_b64}")

    return images


def process_uploads(uploads):
    """处理混合图片/PDF 上传，统一输出为 JPEG base64 data URL 列表"""
    all_images = []
    for item in uploads:
        if item.startswith("data:application/pdf") or item.startswith("data:pdf"):
            pdf_images = convert_pdf_to_images(item)
            all_images.extend(pdf_images)
        else:
            all_images.append(item)
    return all_images


# ============================================================
# Folder scanning + batch processing
# ============================================================
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}


def scan_folder_images(folder_path):
    """扫描目录下的所有图片文件（含 PDF 转换），按文件名排序返回绝对路径列表"""
    if not os.path.isdir(folder_path):
        raise RuntimeError(f"目录不存在: {folder_path}")

    image_files = []
    pdf_files = []

    for name in sorted(os.listdir(folder_path)):
        full = os.path.join(folder_path, name)
        if not os.path.isfile(full):
            continue
        ext = os.path.splitext(name)[1].lower()
        if ext in IMAGE_EXTS:
            image_files.append(full)
        elif ext == ".pdf":
            pdf_files.append(full)

    # PDF 转图片（临时文件）
    converted = []
    for pdf_path in pdf_files:
        with tempfile.TemporaryDirectory() as tmpdir:
            try:
                subprocess.run(
                    ["pdftoppm", "-jpeg", "-r", "150", "-l", "30", pdf_path, "page"],
                    cwd=tmpdir, check=True, capture_output=True, timeout=120
                )
            except Exception as e:
                continue
            for img_path in sorted(glob.glob(os.path.join(tmpdir, "page-*.jpg"))):
                # 复制到持久化临时目录
                dest = os.path.join(folder_path, f".pdf_{os.path.basename(pdf_path)}_{os.path.basename(img_path)}")
                import shutil
                shutil.copy2(img_path, dest)
                converted.append(dest)

    image_files.extend(converted)
    image_files.sort(key=lambda p: os.path.basename(p))
    return image_files


BATCH_OUTLINE_PROMPT = """分析以下教材图片（第 {batch_start}-{batch_end} 页，共 {total_pages} 页），提取单元和知识点结构。

要求：
1. 仔细识别每张图片中的教材内容
2. 标注每个单元和知识点出现在第几页（page 字段 = 该知识点首次出现的页码，从1开始）
3. 按教材的实际结构组织，不要编造不存在的内容
4. 每个知识点需要：名称、简短描述、难度（1-5级）、适合的题型
5. 题型从以下选择：true_false, choice, fill_blank, fill_blank_text, calculation, word_order, matching

只输出 JSON，不要包含 markdown 代码块标记或任何其他文字：
{{
  "units": [
    {{
      "unit_number": 1,
      "title": "单元标题",
      "page_start": 1,
      "page_end": 3,
      "knowledge_points": [
        {{
          "name": "知识点名称",
          "description": "简短描述",
          "difficulty": 2,
          "question_types": ["choice", "fill_blank_text"],
          "page": 1
        }}
      ]
    }}
  ]
}}"""


def read_image_as_b64(path):
    """读取图片文件为 base64 data URL"""
    with open(path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode("utf-8")
    ext = os.path.splitext(path)[1].lower().lstrip(".")
    if ext == "jpg":
        ext = "jpeg"
    return f"data:image/{ext};base64,{b64}"


def merge_outlines(partial_outlines):
    """合并多个批次的大纲：按 unit_number 去重，知识点按 name 去重"""
    merged_units = {}

    for outline in partial_outlines:
        if not outline:
            continue
        for u in outline.get("units", []):
            un = u.get("unit_number", 0)
            if un not in merged_units:
                merged_units[un] = {
                    "unit_number": un,
                    "title": u.get("title", f"第{un}单元"),
                    "page_start": u.get("page_start", 999),
                    "page_end": u.get("page_end", 0),
                    "knowledge_points": [],
                    "_kp_names": set(),
                }
            mu = merged_units[un]
            # 合并标题（取非空的）
            if u.get("title") and len(u["title"]) > len(mu["title"]):
                mu["title"] = u["title"]
            mu["page_start"] = min(mu["page_start"], u.get("page_start", 999))
            mu["page_end"] = max(mu["page_end"], u.get("page_end", 0))

            for kp in u.get("knowledge_points", []):
                kp_name = kp.get("name", "")
                if kp_name and kp_name not in mu["_kp_names"]:
                    mu["_kp_names"].add(kp_name)
                    mu["knowledge_points"].append(kp)

    result = []
    for un in sorted(merged_units.keys()):
        mu = merged_units[un]
        del mu["_kp_names"]
        mu["knowledge_points"].sort(key=lambda k: k.get("page", 999))
        result.append(mu)
    return result


def create_book_from_folder(title, subject, grade, semester, folder_path):
    """从目录扫描图片 → 复制到标准目录 → 写入 SQLite（不生成大纲）
    大纲生成改为后续从文字内容生成（generate_outline_from_texts）
    """
    book_id = generate_book_id(subject, grade, semester)
    now = now_iso()

    # 扫描目录
    image_paths = scan_folder_images(folder_path)
    if not image_paths:
        raise RuntimeError(f"目录中没有找到图片文件: {folder_path}")

    total = len(image_paths)

    # 复制图片到标准目录
    book_img_dir = os.path.join(IMAGES_DIR, book_id)
    os.makedirs(book_img_dir, exist_ok=True)
    page_map = {}  # page_number → filename
    for i, src_path in enumerate(image_paths):
        fname = f"page_{i+1:03d}.jpg"
        dest = os.path.join(book_img_dir, fname)
        import shutil
        shutil.copy2(src_path, dest)
        page_map[i + 1] = fname

    # 写入 SQLite（仅书本 + 页面图片，不生成大纲）
    with db_lock:
        conn = get_db()
        try:
            conn.execute(
                "INSERT INTO books (id, title, subject, grade, semester, source_type, folder_path, created_at, updated_at) "
                "VALUES (?, ?, ?, ?, ?, 'folder', ?, ?, ?)",
                (book_id, title, subject, grade, semester, folder_path, now, now)
            )

            for page_num, fname in page_map.items():
                conn.execute(
                    "INSERT INTO page_images (id, book_id, filename, page_number, sort_idx, created_at) "
                    "VALUES (?, ?, ?, ?, ?, ?)",
                    (f"{book_id}-p{page_num}", book_id, fname, page_num, page_num, now)
                )

            conn.commit()
        finally:
            conn.close()

    result = get_book_detail(book_id)
    result["total_pages"] = total
    return result


import threading as _threading

# 异步任务状态追踪
_extract_jobs: dict = {}


# ============================================================
# Page text extraction (for reading view)
# ============================================================
EXTRACT_TEXT_PROMPT = """请识别这张教材图片的全部文字内容。

要求：
1. 按原文格式输出所有可见文字，包括标题、正文、例题、注释、图说等
2. 保持原有的段落和换行结构
3. 只输出纯文字内容，不要添加任何解释、标记或代码块
4. 如果有表格，按行输出，用 | 分隔
5. 跳过图片、插图、装饰性图形，不要描述图片内容
6. 如果有图片中的标注文字（如地图上的地名、图表中的数据），可以提取"""


def extract_texts_for_book(book_id, force=False, api_key=None):
    """批量提取书本所有页面的文字内容"""
    conn = get_db()
    try:
        # 获取所有页面图片
        pages = conn.execute(
            "SELECT page_number, filename FROM page_images "
            "WHERE book_id = ? AND page_number IS NOT NULL "
            "ORDER BY page_number", (book_id,)
        ).fetchall()
        if not pages:
            raise RuntimeError("没有找到页面图片")

        # 已提取的页面（force=True 时清空重来）
        existing = set()
        if force:
            conn.execute("DELETE FROM page_texts WHERE book_id = ?", (book_id,))
            conn.commit()
        else:
            existing = {r["page_number"] for r in conn.execute(
                "SELECT page_number FROM page_texts WHERE book_id = ?", (book_id,)
            ).fetchall()}

        to_extract = [p for p in pages if p["page_number"] not in existing]
        if not to_extract:
            return {"total": len(pages), "extracted": 0, "skipped": len(existing)}

        now = now_iso()
        book_img_dir = os.path.join(IMAGES_DIR, book_id)
        extracted = 0

        for p in to_extract:
            img_path = os.path.join(book_img_dir, p["filename"])
            if not os.path.exists(img_path):
                continue
            images_b64 = [read_image_as_b64(img_path)]

            try:
                raw_resp = call_ai_vision(images_b64, EXTRACT_TEXT_PROMPT, timeout=120, api_key=api_key)
                text = raw_resp.strip()

                conn.execute(
                    "INSERT OR REPLACE INTO page_texts (id, book_id, page_number, text_content, created_at) "
                    "VALUES (?, ?, ?, ?, ?)",
                    (f"{book_id}-pt-{p['page_number']}", book_id, p["page_number"], text, now)
                )
                conn.commit()
                extracted += 1
            except Exception:
                continue

        return {"total": len(pages), "extracted": extracted, "skipped": len(existing)}
    finally:
        conn.close()


def get_book_read(book_id):
    """获取阅读视图数据：页面图片 + 文字"""
    conn = get_db()
    try:
        book = conn.execute(
            "SELECT id, title, subject, grade, semester FROM books WHERE id = ?", (book_id,)
        ).fetchone()
        if not book:
            return None

        pages = conn.execute(
            "SELECT pi.page_number, pi.filename, pi.kp_id, pi.unit_id, "
            "COALESCE(pt.text_content, '') as text_content, pt.text_content IS NOT NULL as has_text "
            "FROM page_images pi "
            "LEFT JOIN page_texts pt ON pt.book_id = pi.book_id AND pt.page_number = pi.page_number "
            "WHERE pi.book_id = ? AND pi.page_number IS NOT NULL "
            "ORDER BY pi.page_number", (book_id,)
        ).fetchall()

        units = conn.execute(
            "SELECT id, unit_number, title FROM units WHERE book_id = ? ORDER BY unit_number",
            (book_id,)
        ).fetchall()

        return {
            "book": dict(book),
            "pages": [dict(p) for p in pages],
            "units": [dict(u) for u in units],
            "has_text": any(p["has_text"] for p in pages),
        }
    finally:
        conn.close()


def update_page_text(book_id, page_number, text):
    """保存人工修正的页面文字"""
    now = now_iso()
    with db_lock:
        conn = get_db()
        try:
            conn.execute(
                "INSERT OR REPLACE INTO page_texts (id, book_id, page_number, text_content, created_at) "
                "VALUES (?, ?, ?, ?, ?)",
                (f"{book_id}-pt-{page_number}", book_id, page_number, text, now)
            )
            conn.commit()
        finally:
            conn.close()
    return {"success": True}


def get_page_texts_for_kp(kp_id):
    """获取知识点关联页面的文字内容"""
    conn = get_db()
    try:
        rows = conn.execute(
            "SELECT pt.page_number, pt.text_content "
            "FROM page_texts pt "
            "JOIN page_images pi ON pi.book_id = pt.book_id AND pi.page_number = pt.page_number "
            "WHERE pi.kp_id = ? "
            "ORDER BY pt.page_number",
            (kp_id,)
        ).fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()


def get_all_page_texts(book_id):
    """获取书本所有页面的文字内容"""
    conn = get_db()
    try:
        rows = conn.execute(
            "SELECT page_number, text_content FROM page_texts "
            "WHERE book_id = ? ORDER BY page_number",
            (book_id,)
        ).fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()


TEXT_OUTLINE_PROMPT = """以下是教材的逐页文字内容。请分析这些内容，提取完整的单元和知识点结构。

{pages_text}

要求：
1. 按教材的实际结构组织单元和知识点，不要编造不存在的内容
2. 每个知识点标注其首次出现的页码（page 字段）
3. 每个知识点需要：名称、简短描述、难度（1-5级）、适合的题型
4. 题型从以下选择：true_false, choice, fill_blank, fill_blank_text, calculation, word_order, matching
5. 单元之间用 unit_number 区分，按教材实际编排

只输出 JSON，不要包含 markdown 代码块标记或任何其他文字：
{{
  "units": [
    {{
      "unit_number": 1,
      "title": "单元标题",
      "page_start": 1,
      "page_end": 3,
      "knowledge_points": [
        {{
          "name": "知识点名称",
          "description": "简短描述",
          "difficulty": 2,
          "question_types": ["choice", "fill_blank_text"],
          "page": 1
        }}
      ]
    }}
  ]
}}"""


def generate_outline_from_texts(book_id, api_key=None):
    """基于已提取/修正的页面文字生成大纲（纯文本 AI 调用，不使用图片）"""
    page_texts = get_all_page_texts(book_id)
    if not page_texts:
        raise RuntimeError("尚无页面文字，请先提取文字")

    pages_text = "\n\n".join(
        f"第{pt['page_number']}页：\n{pt['text_content']}" for pt in page_texts
    )

    prompt = TEXT_OUTLINE_PROMPT.format(pages_text=pages_text)

    raw_resp = call_ai([
        {"role": "system", "content": OUTLINE_SYSTEM},
        {"role": "user", "content": prompt},
    ], timeout=180, api_key=api_key)

    outline_data = parse_json_response(raw_resp)
    units_data = outline_data.get("units", [])
    if not units_data:
        raise RuntimeError("AI 未能从文字内容中识别出单元结构")

    now = now_iso()

    with db_lock:
        conn = get_db()
        try:
            # 清除旧大纲（如果有）
            conn.execute("DELETE FROM question_sets WHERE kp_id IN (SELECT id FROM knowledge_points WHERE unit_id IN (SELECT id FROM units WHERE book_id = ?))", (book_id,))
            conn.execute("DELETE FROM knowledge_points WHERE unit_id IN (SELECT id FROM units WHERE book_id = ?)", (book_id,))
            conn.execute("DELETE FROM units WHERE book_id = ?", (book_id,))
            # 清除 page_images 中的 kp 关联
            conn.execute("UPDATE page_images SET kp_id = NULL, unit_id = NULL WHERE book_id = ?", (book_id,))

            for u in units_data:
                unit_id = f"{book_id}-u{u['unit_number']}"
                conn.execute(
                    "INSERT INTO units (id, book_id, unit_number, title, sort_order) "
                    "VALUES (?, ?, ?, ?, ?)",
                    (unit_id, book_id, u["unit_number"], u.get("title", ""), u["unit_number"])
                )
                kps = u.get("knowledge_points", [])
                for j, kp in enumerate(kps):
                    kp_id = f"{unit_id}-kp{j+1}"
                    qtypes = json.dumps(kp.get("question_types", ["true_false", "choice"]), ensure_ascii=False)
                    conn.execute(
                        "INSERT INTO knowledge_points "
                        "(id, unit_id, name, description, difficulty, question_types, sort_order, source, created_at) "
                        "VALUES (?, ?, ?, ?, ?, ?, ?, 'ai', ?)",
                        (kp_id, unit_id, kp.get("name", ""), kp.get("description", ""),
                         kp.get("difficulty", 3), qtypes, j+1, now)
                    )
                    # 关联图片
                    kp_page = kp.get("page")
                    if kp_page:
                        conn.execute(
                            "UPDATE page_images SET kp_id = ?, unit_id = ? "
                            "WHERE book_id = ? AND page_number = ?",
                            (kp_id, unit_id, book_id, kp_page)
                        )

            conn.commit()
        finally:
            conn.close()

    result = get_book_detail(book_id)
    result["total_pages"] = len(page_texts)
    return result
# ============================================================
OUTLINE_SYSTEM = "你是一名资深小学教研员，精通中国小学各科教材体系。"

OUTLINE_PROMPT = """分析以下教材图片，提取完整的单元和知识点结构。

要求：
1. 仔细识别图片中的教材内容，包括单元标题、小节标题、知识点
2. 按教材的实际结构组织，不要编造不存在的内容
3. 每个知识点需要：名称、简短描述、难度（1-5级）、适合的题型
4. 如果图片不清晰或无法识别，在描述中标注"图片不清晰"
5. 题型从以下选择：true_false（判断题）、choice（选择题）、fill_blank（数字填空）、
   fill_blank_text（文字填空）、calculation（计算题）、word_order（词语排序）、matching（连线配对）

只输出 JSON，不要包含 markdown 代码块标记或任何其他文字：
{
  "units": [
    {
      "unit_number": 1,
      "title": "单元标题",
      "knowledge_points": [
        {
          "name": "知识点名称",
          "description": "简短描述该知识点需要掌握的内容",
          "difficulty": 2,
          "question_types": ["true_false", "choice", "fill_blank"]
        }
      ]
    }
  ]
}"""

QUESTION_SYSTEM = """你是一位资深的中国小学教师，擅长根据课程标准和知识点设计练习题目。

要求：
1. 题目内容必须符合中国小学课程标准，适合对应年级学生的认知水平
2. 题目用词简洁清晰，小学生能独立理解题意
3. 每道题必须有明确的标准答案和解析
4. 选择题必须提供4个选项
5. 判断题答案为"对"或"错"
6. 填空题用"____"表示空缺处，多个空用分号分隔答案
7. 每次生成的题目应尽量不同，富有变化

输出格式为 JSON 数组，不要包含任何其他文字：
[
  {
    "type": "true_false",
    "score": 2,
    "difficulty": 1,
    "knowledge_point": "知识点名称",
    "question": "题目内容",
    "options": [],
    "answer": "对",
    "explanation": "解析说明"
  },
  {
    "type": "choice",
    "score": 5,
    "difficulty": 2,
    "knowledge_point": "知识点名称",
    "question": "题目内容",
    "options": ["选项A", "选项B", "选项C", "选项D"],
    "answer": "选项B",
    "explanation": "解析说明"
  },
  {
    "type": "fill_blank_text",
    "score": 2,
    "difficulty": 1,
    "knowledge_point": "知识点名称",
    "question": "太阳从____方升起，从____方落下。",
    "options": [],
    "answer": "东;西",
    "explanation": "太阳东升西落是自然规律。"
  }
]"""

QUESTION_USER_TEMPLATE = """学科：{subject}
教材：{textbook}
年级：{grade}年级
单元：第{unit_number}单元 {unit_title}

知识点：{kp_name}
知识点描述：{kp_description}
难度上限：{difficulty}级
适合题型：{question_types}
{page_text_context}
请生成 5-7 道题目，覆盖以上知识点，难度不超过 {difficulty} 级。

重要：本次生成编号为 {seed}，请确保生成全新的题目内容和角度，不要与之前的题目重复。每道题应从不同角度考察该知识点。

只输出 JSON 数组，不要包含 markdown 代码块标记或任何其他文字。"""


# ============================================================
# Business Logic
# ============================================================
def generate_book_id(subject, grade, semester):
    """生成唯一的 bookId: custom-{subject}-{grade}{semester}-{uuid6}"""
    short_uuid = uuid.uuid4().hex[:6]
    return f"custom-{subject}-g{grade}{semester}-{short_uuid}"


def create_book_with_ai(title, subject, grade, semester, images_b64):
    """创建自定义书本：保存图片 → AI 识图 → 生成大纲 → 写入 SQLite"""
    book_id = generate_book_id(subject, grade, semester)
    now = now_iso()

    # 处理混合上传：PDF 转图片，统一为 JPEG base64
    images_b64 = process_uploads(images_b64)

    # 保存图片到磁盘
    book_img_dir = os.path.join(IMAGES_DIR, book_id)
    os.makedirs(book_img_dir, exist_ok=True)
    saved_filenames = []
    for i, img_b64 in enumerate(images_b64):
        raw = img_b64.split(",", 1)[-1] if "," in img_b64 else img_b64
        fname = f"page_{i+1:03d}.jpg"
        with open(os.path.join(book_img_dir, fname), "wb") as f:
            f.write(base64.b64decode(raw))
        saved_filenames.append(fname)

    # AI 识图生成大纲
    outline_data = None
    ocr_texts = []
    if images_b64:
        raw_resp = call_ai_vision(images_b64, OUTLINE_PROMPT, timeout=120)
        outline_data = parse_json_response(raw_resp)
        # 保存 OCR 文本（简化：用 AI 原始返回作为 OCR 摘要）
        ocr_texts = [raw_resp[:2000]]  # 截断

    # 写入 SQLite
    with db_lock:
        conn = get_db()
        try:
            conn.execute(
                "INSERT INTO books (id, title, subject, grade, semester, source_type, created_at, updated_at) "
                "VALUES (?, ?, ?, ?, ?, 'photo', ?, ?)",
                (book_id, title, subject, grade, semester, now, now)
            )

            units_data = outline_data.get("units", []) if outline_data else []
            for u in units_data:
                unit_id = f"{book_id}-u{u['unit_number']}"
                conn.execute(
                    "INSERT INTO units (id, book_id, unit_number, title, sort_order) "
                    "VALUES (?, ?, ?, ?, ?)",
                    (unit_id, book_id, u["unit_number"], u.get("title", ""), u["unit_number"])
                )
                kps = u.get("knowledge_points", [])
                for j, kp in enumerate(kps):
                    kp_id = f"{unit_id}-kp{j+1}"
                    qtypes = json.dumps(kp.get("question_types", ["true_false", "choice"]), ensure_ascii=False)
                    conn.execute(
                        "INSERT INTO knowledge_points "
                        "(id, unit_id, name, description, difficulty, question_types, sort_order, source, created_at) "
                        "VALUES (?, ?, ?, ?, ?, ?, ?, 'ai', ?)",
                        (kp_id, unit_id, kp.get("name", ""), kp.get("description", ""),
                         kp.get("difficulty", 3), qtypes, j+1, now)
                    )

            # 保存图片记录
            for i, fname in enumerate(saved_filenames):
                conn.execute(
                    "INSERT INTO page_images (id, book_id, filename, ocr_text, page_number, created_at) "
                    "VALUES (?, ?, ?, ?, ?, ?)",
                    (uuid.uuid4().hex, book_id, fname,
                     ocr_texts[0] if i == 0 and ocr_texts else None,
                     i+1, now)
                )

            conn.commit()
        finally:
            conn.close()

    return get_book_detail(book_id)


def get_book_detail(book_id):
    """获取书本详情 + 完整大纲树"""
    conn = get_db()
    try:
        book = conn.execute("SELECT * FROM books WHERE id = ?", (book_id,)).fetchone()
        if not book:
            return None

        units = conn.execute(
            "SELECT * FROM units WHERE book_id = ? ORDER BY unit_number",
            (book_id,)
        ).fetchall()

        units_list = []
        for u in units:
            kps = conn.execute(
                "SELECT * FROM knowledge_points WHERE unit_id = ? ORDER BY sort_order",
                (u["id"],)
            ).fetchall()
            units_list.append({
                "id": u["id"],
                "unit_number": u["unit_number"],
                "title": u["title"],
                "knowledge_points": [{
                    "id": kp["id"],
                    "name": kp["name"],
                    "description": kp["description"],
                    "difficulty": kp["difficulty"],
                    "question_types": json.loads(kp["question_types"]),
                } for kp in kps]
            })

        return {
            "id": book["id"],
            "title": book["title"],
            "subject": book["subject"],
            "grade": book["grade"],
            "semester": book["semester"],
            "created_at": book["created_at"],
            "units": units_list,
        }
    finally:
        conn.close()


def list_books():
    """列出所有自定义书本"""
    conn = get_db()
    try:
        rows = conn.execute(
            "SELECT id, title, subject, grade, semester, created_at FROM books ORDER BY created_at DESC"
        ).fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()


def delete_book(book_id):
    """删除书本（级联删除）"""
    with db_lock:
        conn = get_db()
        try:
            # 删除图片文件
            img_dir = os.path.join(IMAGES_DIR, book_id)
            if os.path.isdir(img_dir):
                import shutil
                shutil.rmtree(img_dir, ignore_errors=True)
            conn.execute("DELETE FROM books WHERE id = ?", (book_id,))
            conn.commit()
        finally:
            conn.close()


def get_kp_info(kp_id):
    """从 kp_id 获取知识点信息 + 所属单元/书本信息"""
    conn = get_db()
    try:
        row = conn.execute(
            "SELECT kp.*, u.title as unit_title, u.unit_number, "
            "b.title as book_title, b.subject, b.grade "
            "FROM knowledge_points kp "
            "JOIN units u ON kp.unit_id = u.id "
            "JOIN books b ON u.book_id = b.id "
            "WHERE kp.id = ?",
            (kp_id,)
        ).fetchone()
        return dict(row) if row else None
    finally:
        conn.close()


def get_or_generate_questions(kp_id, api_key=None):
    """获取或生成题目（如已有 active 版本则直接返回）"""
    conn = get_db()
    try:
        existing = conn.execute(
            "SELECT * FROM question_sets WHERE kp_id = ? AND is_active = 1",
            (kp_id,)
        ).fetchone()
        if existing:
            return {
                "version": existing["version"],
                "questions": json.loads(existing["questions"]),
                "generated_at": existing["generated_at"],
            }
    finally:
        conn.close()

    # 无题目，生成 v1
    return generate_questions_for_kp(kp_id, version=1, api_key=api_key)


def generate_questions_for_kp(kp_id, version=None, api_key=None):
    """AI 生成题目并存入 SQLite"""
    kp = get_kp_info(kp_id)
    if not kp:
        raise RuntimeError(f"知识点不存在: {kp_id}")

    # 确定 version 号
    if version is None:
        conn = get_db()
        try:
            row = conn.execute(
                "SELECT MAX(version) as max_v FROM question_sets WHERE kp_id = ?",
                (kp_id,)
            ).fetchone()
            version = (row["max_v"] or 0) + 1
        finally:
            conn.close()

    # 构建 prompt
    subject_labels = {
        "math": "数学", "chinese": "语文", "english": "英语", "science": "科学"
    }

    # 获取知识点关联页面的文字内容
    page_texts = get_page_texts_for_kp(kp_id)
    if page_texts:
        text_ctx = "\n教材原文参考：\n"
        for pt in page_texts:
            text_ctx += f"第{pt['page_number']}页：{pt['text_content']}\n\n"
        text_ctx = text_ctx.rstrip()
    else:
        text_ctx = ""

    user_prompt = QUESTION_USER_TEMPLATE.format(
        subject=subject_labels.get(kp["subject"], kp["subject"]),
        textbook=kp["book_title"],
        grade=kp["grade"],
        unit_number=kp["unit_number"],
        unit_title=kp["unit_title"],
        kp_name=kp["name"],
        kp_description=kp["description"] or "（无描述）",
        difficulty=kp["difficulty"],
        question_types=", ".join(json.loads(kp["question_types"])),
        seed=random.randint(1, 99999),
        page_text_context=text_ctx,
    )

    # 调用 AI
    raw_resp = call_ai([
        {"role": "system", "content": QUESTION_SYSTEM},
        {"role": "user", "content": user_prompt},
    ], timeout=120, api_key=api_key)

    questions = parse_json_response(raw_resp)

    # 确保是 list
    if isinstance(questions, dict):
        questions = [questions]

    # 自动编号 id
    for i, q in enumerate(questions, 1):
        q["id"] = i
        q.setdefault("score", 5)
        q.setdefault("difficulty", kp["difficulty"])
        q.setdefault("knowledge_point", kp["name"])
        q.setdefault("options", [])
        q.setdefault("explanation", "")

    questions_json = json.dumps(questions, ensure_ascii=False)
    set_id = uuid.uuid4().hex
    now = now_iso()

    with db_lock:
        conn = get_db()
        try:
            # 旧版本设为 inactive
            conn.execute(
                "UPDATE question_sets SET is_active = 0 WHERE kp_id = ?",
                (kp_id,)
            )
            # 插入新版本
            conn.execute(
                "INSERT INTO question_sets (id, kp_id, version, questions, is_active, ai_model, generated_at) "
                "VALUES (?, ?, ?, ?, 1, ?, ?)",
                (set_id, kp_id, version, questions_json, AI_MODEL, now)
            )
            conn.commit()
        finally:
            conn.close()

    return {
        "version": version,
        "questions": questions,
        "generated_at": now,
    }


def list_question_versions(kp_id):
    """列出知识点的所有题目版本"""
    conn = get_db()
    try:
        rows = conn.execute(
            "SELECT version, is_active, ai_model, generated_at, "
            "LENGTH(questions) as questions_size "
            "FROM question_sets WHERE kp_id = ? ORDER BY version DESC",
            (kp_id,)
        ).fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()


# ============================================================
# Exam (真题库) Logic
# ============================================================

_exam_extract_jobs = {}  # exam_id -> {status, message, result}
_exam_analyze_jobs = {}  # exam_id -> {status, message, result}


def list_exams():
    conn = get_db()
    try:
        rows = conn.execute(
            "SELECT id, title, subject, grade, semester, difficulty, "
            "total_pages, LENGTH(text_content) as text_len, "
            "text_content IS NOT NULL as has_text, "
            "structure IS NOT NULL as has_structure, "
            "analyze_status, created_at "
            "FROM exams ORDER BY created_at DESC"
        ).fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()


def get_exam(exam_id):
    conn = get_db()
    try:
        row = conn.execute(
            "SELECT * FROM exams WHERE id = ?", (exam_id,)
        ).fetchone()
        return dict(row) if row else None
    finally:
        conn.close()


def create_exam(title, subject, grade, semester, difficulty, images_b64):
    exam_id = f"exam-{subject}-g{grade}{semester}-{uuid.uuid4().hex[:6]}"
    now = now_iso()

    images_b64 = process_uploads(images_b64)

    book_img_dir = os.path.join(IMAGES_DIR, exam_id)
    os.makedirs(book_img_dir, exist_ok=True)
    saved = []
    for i, img_b64 in enumerate(images_b64):
        raw = img_b64.split(",", 1)[-1] if "," in img_b64 else img_b64
        fname = f"page_{i+1:03d}.jpg"
        with open(os.path.join(book_img_dir, fname), "wb") as f:
            f.write(base64.b64decode(raw))
        saved.append(fname)

    conn = get_db()
    try:
        conn.execute(
            "INSERT INTO exams (id, title, subject, grade, semester, difficulty, "
            "text_content, total_pages, created_at, updated_at) "
            "VALUES (?, ?, ?, ?, ?, ?, NULL, ?, ?, ?)",
            (exam_id, title, subject, grade, semester, difficulty,
             len(saved), now, now)
        )
        for i, fname in enumerate(saved):
            conn.execute(
                "INSERT INTO exam_pages (id, exam_id, filename, page_number, sort_idx, created_at) "
                "VALUES (?, ?, ?, ?, ?, ?)",
                (f"{exam_id}-{i}", exam_id, fname, i + 1, i, now)
            )
        conn.commit()
    finally:
        conn.close()

    return get_exam(exam_id)


def delete_exam(exam_id):
    img_dir = os.path.join(IMAGES_DIR, exam_id)
    if os.path.isdir(img_dir):
        shutil.rmtree(img_dir, ignore_errors=True)
    conn = get_db()
    try:
        conn.execute("DELETE FROM exam_pages WHERE exam_id = ?", (exam_id,))
        conn.execute("DELETE FROM exams WHERE id = ?", (exam_id,))
        conn.commit()
    finally:
        conn.close()


def update_exam_text(exam_id, text):
    now = now_iso()
    conn = get_db()
    try:
        conn.execute(
            "UPDATE exams SET text_content = ?, updated_at = ? WHERE id = ?",
            (text, now, exam_id)
        )
        conn.commit()
    finally:
        conn.close()
    return {"success": True}


def extract_exam_text(exam_id, api_key=None):
    """OCR all pages of an exam and combine into one text field."""
    exam = get_exam(exam_id)
    if not exam:
        raise RuntimeError("试卷不存在")

    conn = get_db()
    try:
        rows = conn.execute(
            "SELECT filename, page_number FROM exam_pages "
            "WHERE exam_id = ? ORDER BY page_number", (exam_id,)
        ).fetchall()
    finally:
        conn.close()

    if not rows:
        raise RuntimeError("没有页面图片")

    all_text = []
    for row in rows:
        img_path = os.path.join(IMAGES_DIR, exam_id, row["filename"])
        if not os.path.exists(img_path):
            continue
        with open(img_path, "rb") as f:
            img_b64 = base64.b64encode(f.read()).decode()

        prompt = (
            "请提取这张试卷图片中的所有文字内容，保持原始格式和题号。"
            "只输出文字内容，不要添加任何解释说明。"
            "如果有图片或表格，用文字描述其内容。"
        )
        resp = call_ai_vision([img_b64], prompt, api_key=api_key)
        page_text = resp.strip() if resp else ""
        if page_text:
            all_text.append(f"--- 第{row['page_number']}页 ---\n{page_text}")

    combined = "\n\n".join(all_text)
    update_exam_text(exam_id, combined)

    return {"total": len(rows), "extracted": len(all_text)}


def update_exam_structure(exam_id, structure_json, status="done"):
    now = now_iso()
    conn = get_db()
    try:
        conn.execute(
            "UPDATE exams SET structure = ?, analyze_status = ?, updated_at = ? WHERE id = ?",
            (structure_json, status, now, exam_id)
        )
        conn.commit()
    finally:
        conn.close()
    return {"success": True}


def analyze_exam_structure(exam_id, api_key=None):
    """AI 分析真题试卷的题型结构，产出结构化数据。"""
    exam = get_exam(exam_id)
    if not exam:
        raise RuntimeError("试卷不存在")
    if not exam.get("text_content"):
        raise RuntimeError("请先识别文字再分析结构")

    prompt = f"""请分析下面这份小学试卷的题型结构，提取每一大题的信息。

试卷内容：
{exam["text_content"][:6000]}

请输出 JSON 格式，包含以下字段：
- total_score: 总分（整数）
- duration_minutes: 考试时长分钟数（整数，未知则填 90）
- sections: 数组，每个元素包含：
  - name: 大题名称（如"一、填空题"）
  - type: 题型标识（英文，用小写字母和下划线，如 fill_blank、choice、true_false、calculation、application、reading_comprehension、word_problem、cloze、composition 等）
  - count: 该大题小题数量（整数）
  - score_each: 每小题分值（整数，如果各小题分值不同则填 0）
  - total_score: 该大题总分（整数）
  - description: 题型说明（可选，如"每题只有一个正确答案"）

注意：
1. 严格按照试卷上的大题顺序排列
2. 题型标识尽量标准化，但可以自由定义，不要局限于给定的例子
3. 只输出 JSON，不要包含任何其他文字或 markdown 标记"""

    resp = call_ai([{"role": "user", "content": prompt}], api_key=api_key)
    if not resp:
        raise RuntimeError("AI 未返回内容")

    # 清理 markdown 代码块
    text = resp.strip()
    if text.startswith("```"):
        text = text.replace("```json", "").replace("```", "").strip()

    try:
        structure = json.loads(text)
    except json.JSONDecodeError:
        # 尝试提取第一个 { 到最后一个 } 之间的内容
        start = text.find("{")
        end = text.rfind("}")
        if start >= 0 and end > start:
            structure = json.loads(text[start:end + 1])
        else:
            raise RuntimeError("AI 返回格式错误，无法解析为 JSON")

    # 保存到数据库
    update_exam_structure(exam_id, json.dumps(structure, ensure_ascii=False), "done")

    return structure


# ============================================================
# HTTP Handler
# ============================================================
class CustomHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, format, *args):
        # 简洁日志
        sys_msg = f"[custom-api] {self.command} {self.path} - "
        try:
            sys_msg += format % args
        except Exception:
            pass
        print(sys_msg, flush=True)

    def _send_json(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()
        self.wfile.write(body)

    def _send_error(self, msg, status=500):
        self._send_json({"error": msg}, status)

    def _read_body(self):
        length = int(self.headers.get("Content-Length", 0))
        if length > MAX_BODY:
            raise RuntimeError(f"请求体过大 ({length} bytes), 上限 {MAX_BODY}")
        if length == 0:
            return b""
        return self.rfile.read(length)

    def _ai_key(self):
        """从请求头读取前端传入的 AI Key，回退到环境变量"""
        return self.headers.get("X-AI-Key", "").strip() or None

    def do_OPTIONS(self):
        self._send_json({"ok": True})

    def do_GET(self):
        path = self.path.split("?")[0].rstrip("/")
        parts = [p for p in path.split("/") if p]

        try:
            # /books
            if parts == ["books"]:
                self._send_json({"books": list_books()})
                return

            # /books/:id/outline
            if len(parts) == 3 and parts[0] == "books" and parts[2] == "outline":
                book = get_book_detail(parts[1])
                if book:
                    self._send_json(book)
                else:
                    self._send_error("书本不存在", 404)
                return

            # /books/:id
            if len(parts) == 2 and parts[0] == "books":
                book = get_book_detail(parts[1])
                if book:
                    self._send_json(book)
                else:
                    self._send_error("书本不存在", 404)
                return

            # /books/:id/pages — 获取所有页面图片（阅读视图用）
            if len(parts) == 3 and parts[0] == "books" and parts[2] == "pages":
                book_id = parts[1]
                conn = get_db()
                try:
                    rows = conn.execute(
                        "SELECT filename, page_number, kp_id, unit_id, sort_idx "
                        "FROM page_images WHERE book_id = ? ORDER BY sort_idx, page_number",
                        (book_id,)
                    ).fetchall()
                    pages = [dict(r) for r in rows]
                    self._send_json({"pages": pages})
                finally:
                    conn.close()
                return

            # /books/:id/read — 阅读视图数据（图片 + 文字）
            if len(parts) == 3 and parts[0] == "books" and parts[2] == "read":
                data = get_book_read(parts[1])
                if data:
                    self._send_json(data)
                else:
                    self._send_error("书本不存在", 404)
                return

            # /books/:id/text-status — 查询文字提取状态
            if len(parts) == 3 and parts[0] == "books" and parts[2] == "text-status":
                book_id = parts[1]
                conn = get_db()
                try:
                    total_pages = conn.execute(
                        "SELECT COUNT(*) as c FROM page_images WHERE book_id = ? AND page_number IS NOT NULL",
                        (book_id,)
                    ).fetchone()["c"]
                    text_pages = conn.execute(
                        "SELECT COUNT(*) as c FROM page_texts WHERE book_id = ?",
                        (book_id,)
                    ).fetchone()["c"]
                    units_count = conn.execute(
                        "SELECT COUNT(*) as c FROM units WHERE book_id = ?",
                        (book_id,)
                    ).fetchone()["c"]
                    self._send_json({
                        "total_pages": total_pages,
                        "text_pages": text_pages,
                        "has_text": text_pages > 0,
                        "has_outline": units_count > 0,
                    })
                finally:
                    conn.close()
                return

            # /books/:id/extract-status — 查询异步提取任务状态
            if len(parts) == 3 and parts[0] == "books" and parts[2] == "extract-status":
                job = _extract_jobs.get(parts[1], {"status": "idle"})
                self._send_json(job)
                return

            # /folders — 列出 textbooks 目录下的子目录
            if parts == ["folders"]:
                folders = []
                if os.path.isdir(TEXTBOOKS_DIR):
                    for name in sorted(os.listdir(TEXTBOOKS_DIR)):
                        full = os.path.join(TEXTBOOKS_DIR, name)
                        if os.path.isdir(full):
                            # 统计图片数量
                            count = sum(1 for f in os.listdir(full)
                                       if os.path.splitext(f)[1].lower() in IMAGE_EXTS
                                       or os.path.splitext(f)[1].lower() == ".pdf")
                            folders.append({"name": name, "path": full, "image_count": count})
                self._send_json({"folders": folders})
                return

            # /lessons/:lessonId/versions
            if len(parts) == 3 and parts[0] == "lessons" and parts[2] == "versions":
                versions = list_question_versions(parts[1])
                self._send_json({"versions": versions})
                return

            # /parent/status — 是否已设密码
            if parts == ["parent", "status"]:
                s = get_parent_settings()
                self._send_json({"is_setup": bool(s and s.get("is_setup"))})
                return

            # /parent/settings — 获取设置（不含密码，需 token）
            if parts == ["parent", "settings"]:
                token = self.headers.get("X-Parent-Auth", "")
                if not verify_token(token):
                    self._send_error("需要家长授权", 403)
                    return
                s = get_parent_settings() or {}
                self._send_json({
                    "is_setup": bool(s.get("is_setup")),
                    "ai_key_set": bool(s.get("ai_api_key")),
                    "ai_base_url": s.get("ai_base_url", "https://aiapi.fonken.net/v1"),
                    "ai_model": s.get("ai_model", "gemini-3.1-flash-lite"),
                    "daily_limit_ms": s.get("daily_limit_ms", 0),
                    "session_limit_ms": s.get("session_limit_ms", 0),
                })
                return

            # /parent/public-settings — 获取防沉迷参数（无需 token，前端启动时覆盖 localStorage）
            if parts == ["parent", "public-settings"]:
                s = get_parent_settings() or {}
                self._send_json({
                    "daily_limit_ms": s.get("daily_limit_ms", 0),
                    "session_limit_ms": s.get("session_limit_ms", 0),
                })
                return

            # /kids — 列出所有学生档案
            if parts == ["kids"]:
                self._send_json({"kids": list_kids()})
                return

            # /sync/progress — 拉取合并后的进度（按 kid_id 隔离）
            if parts == ["sync", "progress"]:
                kid_id = self.headers.get("X-Kid-Id", "default")
                conn = get_db()
                try:
                    rows = conn.execute(
                        "SELECT progress_json FROM progress_sync WHERE kid_id = ? ORDER BY last_sync_at",
                        (kid_id,)
                    ).fetchall()
                    if not rows:
                        self._send_json({"progress": None})
                        return
                    merged = None
                    for r in rows:
                        state = json.loads(r["progress_json"])
                        if merged is None:
                            merged = state
                        else:
                            merged = merge_progress(merged, state)
                    self._send_json({"progress": merged})
                finally:
                    conn.close()
                return

            # /exams — 列出所有真题
            if parts == ["exams"]:
                self._send_json({"exams": list_exams()})
                return

            # /exams/:id — 获取真题详情
            if len(parts) == 2 and parts[0] == "exams":
                exam = get_exam(parts[1])
                if exam:
                    self._send_json(exam)
                else:
                    self._send_error("试卷不存在", 404)
                return

            # /exams/:id/extract-status — 查询 OCR 任务状态
            if len(parts) == 3 and parts[0] == "exams" and parts[2] == "extract-status":
                job = _exam_extract_jobs.get(parts[1], {"status": "idle"})
                self._send_json(job)
                return

            # /exams/:id/analyze-status — 查询试卷结构分析任务状态
            if len(parts) == 3 and parts[0] == "exams" and parts[2] == "analyze-status":
                exam = get_exam(parts[1])
                job = _exam_analyze_jobs.get(parts[1], {"status": exam.get("analyze_status", "idle") if exam else "idle"})
                # 如果数据库里已经有 structure，直接返回 done
                if exam and exam.get("structure") and job.get("status") != "processing":
                    job = {"status": "done", "structure": json.loads(exam["structure"]) if exam["structure"] else None}
                self._send_json(job)
                return

            self._send_error("未知路径", 404)

        except Exception as e:
            self._send_error(str(e))

    def do_POST(self):
        path = self.path.split("?")[0].rstrip("/")
        parts = [p for p in path.split("/") if p]

        try:
            # /books
            if parts == ["books"]:
                body = self._read_body()
                data = json.loads(body)
                title = data.get("title", "自定义教材")
                subject = data.get("subject", "math")
                grade = data.get("grade", 1)
                semester = data.get("semester", "up")
                images = data.get("images", [])

                if not images:
                    self._send_error("请上传至少一张教材照片", 400)
                    return

                book = create_book_with_ai(title, subject, grade, semester, images)
                self._send_json(book)
                return

            # /books/from-folder
            if parts == ["books", "from-folder"]:
                body = self._read_body()
                data = json.loads(body)
                title = data.get("title", "自定义教材")
                subject = data.get("subject", "math")
                grade = data.get("grade", 1)
                semester = data.get("semester", "up")
                folder = data.get("folder_path", "")

                if not folder:
                    self._send_error("请指定教材图片目录", 400)
                    return

                book = create_book_from_folder(title, subject, grade, semester, folder)
                self._send_json(book)
                return

            # /books/:id/extract-text — 提取页面文字（异步）
            if len(parts) == 3 and parts[0] == "books" and parts[2] == "extract-text":
                body = self._read_body()
                force = False
                if body:
                    try:
                        force = json.loads(body).get("force", False)
                    except Exception:
                        pass
                book_id = parts[1]
                job_key = f"{book_id}"
                # 已在跑？返回当前状态
                if job_key in _extract_jobs and _extract_jobs[job_key].get("status") == "processing":
                    self._send_json({"status": "processing", "message": "正在识别中..."})
                    return
                # 启动后台线程
                _extract_jobs[job_key] = {"status": "processing", "message": "正在识别..."}

                ai_key = self._ai_key()
                def _do_extract():
                    try:
                        result = extract_texts_for_book(book_id, force=force, api_key=ai_key)
                        _extract_jobs[job_key] = {"status": "done", "result": result}
                    except Exception as e:
                        _extract_jobs[job_key] = {"status": "error", "message": str(e)}

                t = _threading.Thread(target=_do_extract, daemon=True)
                t.start()
                self._send_json({"status": "started", "message": "识别任务已启动"})
                return

            # /books/:id/pages/:page/text — 保存人工修正的页面文字
            if (len(parts) == 5 and parts[0] == "books" and parts[2] == "pages"
                    and parts[4] == "text"):
                book_id = parts[1]
                page_number = int(parts[3])
                body = self._read_body()
                data = json.loads(body)
                text = data.get("text", "")
                result = update_page_text(book_id, page_number, text)
                self._send_json(result)
                return

            # /books/:id/generate-outline — 从文字内容生成大纲
            if len(parts) == 3 and parts[0] == "books" and parts[2] == "generate-outline":
                book_id = parts[1]
                result = generate_outline_from_texts(book_id, api_key=self._ai_key())
                self._send_json(result)
                return

            # /lessons/:lessonId/questions
            if len(parts) == 3 and parts[0] == "lessons" and parts[2] == "questions":
                result = get_or_generate_questions(parts[1], api_key=self._ai_key())
                self._send_json(result)
                return

            # /lessons/:lessonId/refresh
            if len(parts) == 3 and parts[0] == "lessons" and parts[2] == "refresh":
                result = generate_questions_for_kp(parts[1], api_key=self._ai_key())
                self._send_json(result)
                return

            # /parent/setup — 首次设置密码 + 默认配置
            if parts == ["parent", "setup"]:
                body = self._read_body()
                data = json.loads(body)
                password = data.get("password", "")
                if len(password) < 4:
                    self._send_error("密码至少 4 位", 400)
                    return
                salt = secrets.token_hex(8)
                pwd_hash = hash_password(password, salt)
                now = now_iso()
                conn = get_db()
                try:
                    conn.execute("""
                        INSERT OR REPLACE INTO parent_settings
                        (id, password_hash, password_salt, is_setup,
                         ai_api_key, ai_base_url, ai_model,
                         daily_limit_ms, session_limit_ms, updated_at)
                        VALUES (1, ?, ?, 1, ?, ?, ?, ?, ?, ?)
                    """, (
                        pwd_hash, salt,
                        data.get("ai_api_key", ""),
                        data.get("ai_base_url", "https://aiapi.fonken.net/v1"),
                        data.get("ai_model", "gemini-3.1-flash-lite"),
                        data.get("daily_limit_ms", 0),
                        data.get("session_limit_ms", 0),
                        now,
                    ))
                    conn.commit()
                finally:
                    conn.close()
                token = create_token()
                self._send_json({"ok": True, "token": token})
                return

            # /parent/verify — 验证密码，返回 token
            if parts == ["parent", "verify"]:
                body = self._read_body()
                data = json.loads(body)
                password = data.get("password", "")
                s = get_parent_settings()
                if not s or not s.get("is_setup"):
                    self._send_error("尚未设置家长密码", 400)
                    return
                pwd_hash = hash_password(password, s["password_salt"])
                if pwd_hash != s["password_hash"]:
                    self._send_error("密码错误", 403)
                    return
                token = create_token()
                self._send_json({"ok": True, "token": token})
                return

            # /parent/settings — 修改设置（需 token）
            if parts == ["parent", "settings"]:
                token = self.headers.get("X-Parent-Auth", "")
                if not verify_token(token):
                    self._send_error("需要家长授权", 403)
                    return
                body = self._read_body()
                data = json.loads(body)
                s = get_parent_settings() or {}
                now = now_iso()
                conn = get_db()
                try:
                    updates = []
                    params = []
                    for field in ("ai_api_key", "ai_base_url", "ai_model",
                                  "daily_limit_ms", "session_limit_ms"):
                        if field in data:
                            updates.append(f"{field} = ?")
                            params.append(data[field])
                    if updates:
                        updates.append("updated_at = ?")
                        params.append(now)
                        params.append(1)  # id
                        conn.execute(
                            f"UPDATE parent_settings SET {', '.join(updates)} WHERE id = ?",
                            params
                        )
                        conn.commit()
                finally:
                    conn.close()
                self._send_json({"ok": True})
                return

            # /kids — 创建学生档案
            if parts == ["kids"]:
                token = self.headers.get("X-Parent-Auth", "")
                if not verify_token(token):
                    self._send_error("需要家长授权", 403)
                    return
                body = self._read_body()
                data = json.loads(body)
                kid = create_kid(data.get("name", "未命名"), data.get("avatar", "default"))
                self._send_json(kid)
                return

            # /kids/:id — 更新或删除学生档案
            if len(parts) == 2 and parts[0] == "kids":
                token = self.headers.get("X-Parent-Auth", "")
                if not verify_token(token):
                    self._send_error("需要家长授权", 403)
                    return
                kid_id = parts[1]
                body = self._read_body()
                data = json.loads(body)
                update_kid(kid_id, data.get("name"), data.get("avatar"))
                self._send_json({"ok": True})
                return

            # /sync/progress — 上报进度（含 kid_id）
            if parts == ["sync", "progress"]:
                body = self._read_body()
                data = json.loads(body)
                device_id = data.get("device_id", "unknown")
                kid_id = data.get("kid_id", "default")
                device_name = data.get("device_name", "")
                progress = data.get("progress", {})
                xp = progress.get("xp", 0)
                gems = progress.get("gems", 0)
                now = now_iso()
                row_id = f"{kid_id}:{device_id}"
                conn = get_db()
                try:
                    conn.execute("""
                        INSERT OR REPLACE INTO progress_sync
                        (id, kid_id, device_id, device_name, progress_json, last_sync_at, xp, gems)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """, (row_id, kid_id, device_id, device_name, json.dumps(progress), now, xp, gems))
                    conn.commit()
                finally:
                    conn.close()
                self._send_json({"ok": True})
                return

            # /exams — 创建真题
            if parts == ["exams"]:
                body = self._read_body()
                data = json.loads(body)
                title = data.get("title", "真题试卷")
                subject = data.get("subject", "math")
                grade = data.get("grade", 1)
                semester = data.get("semester", "up")
                difficulty = data.get("difficulty", "normal")
                images = data.get("images", [])
                if not images:
                    self._send_error("请上传至少一张试卷照片", 400)
                    return
                exam = create_exam(title, subject, grade, semester, difficulty, images)
                self._send_json(exam)
                return

            # /exams/:id/text — 更新真题文本
            if len(parts) == 3 and parts[0] == "exams" and parts[2] == "text":
                body = self._read_body()
                data = json.loads(body)
                result = update_exam_text(parts[1], data.get("text", ""))
                self._send_json(result)
                return

            # /exams/:id/extract-text — 异步 OCR 提取文字
            if len(parts) == 3 and parts[0] == "exams" and parts[2] == "extract-text":
                exam_id = parts[1]
                if exam_id in _exam_extract_jobs and _exam_extract_jobs[exam_id].get("status") == "processing":
                    self._send_json({"status": "processing", "message": "正在识别中..."})
                    return
                _exam_extract_jobs[exam_id] = {"status": "processing", "message": "正在识别..."}
                ai_key = self._ai_key()
                def _do_extract_exam():
                    try:
                        result = extract_exam_text(exam_id, api_key=ai_key)
                        _exam_extract_jobs[exam_id] = {"status": "done", "result": result}
                    except Exception as e:
                        _exam_extract_jobs[exam_id] = {"status": "error", "message": str(e)}
                t = _threading.Thread(target=_do_extract_exam, daemon=True)
                t.start()
                self._send_json({"status": "started", "message": "识别任务已启动"})
                return

            # /exams/:id/analyze — 异步 AI 分析试卷结构
            if len(parts) == 3 and parts[0] == "exams" and parts[2] == "analyze":
                exam_id = parts[1]
                if exam_id in _exam_analyze_jobs and _exam_analyze_jobs[exam_id].get("status") == "processing":
                    self._send_json({"status": "processing", "message": "正在分析中..."})
                    return
                update_exam_structure(exam_id, None, "processing")
                _exam_analyze_jobs[exam_id] = {"status": "processing", "message": "正在分析试卷结构..."}
                ai_key = self._ai_key()
                def _do_analyze():
                    try:
                        result = analyze_exam_structure(exam_id, api_key=ai_key)
                        _exam_analyze_jobs[exam_id] = {"status": "done", "result": result}
                    except Exception as e:
                        update_exam_structure(exam_id, None, "error")
                        _exam_analyze_jobs[exam_id] = {"status": "error", "message": str(e)}
                t = _threading.Thread(target=_do_analyze, daemon=True)
                t.start()
                self._send_json({"status": "started", "message": "分析任务已启动"})
                return

            self._send_error("未知路径", 404)

        except RuntimeError as e:
            self._send_error(str(e), 500)
        except json.JSONDecodeError as e:
            self._send_error(f"JSON 解析失败: {e}", 400)
        except Exception as e:
            self._send_error(f"内部错误: {e}", 500)

    def do_DELETE(self):
        path = self.path.split("?")[0].rstrip("/")
        parts = [p for p in path.split("/") if p]

        try:
            # /books/:id
            if len(parts) == 2 and parts[0] == "books":
                delete_book(parts[1])
                self._send_json({"ok": True})
                return

            # /kids/:id — 删除学生档案
            if len(parts) == 2 and parts[0] == "kids":
                token = self.headers.get("X-Parent-Auth", "")
                if not verify_token(token):
                    self._send_error("需要家长授权", 403)
                    return
                delete_kid(parts[1])
                self._send_json({"ok": True})
                return

            # /exams/:id — 删除真题
            if len(parts) == 2 and parts[0] == "exams":
                delete_exam(parts[1])
                self._send_json({"ok": True})
                return

            self._send_error("未知路径", 404)

        except Exception as e:
            self._send_error(str(e), 500)


# ============================================================
# Main
# ============================================================
if __name__ == "__main__":
    import sys
    init_db()
    server = http.server.ThreadingHTTPServer(
        ("127.0.0.1", PORT), CustomHandler
    )
    print(f"=== 自定义学习 API 服务已启动（127.0.0.1:{PORT}）===", flush=True)
    print(f"    DB: {DB_PATH}", flush=True)
    print(f"    AI: {AI_BASE} / {AI_MODEL}", flush=True)
    print(f"    Key: {'已配置' if AI_KEY else '未配置（AI 功能不可用）'}", flush=True)
    server.serve_forever()
