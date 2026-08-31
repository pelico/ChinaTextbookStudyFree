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

    conn.commit()
    conn.close()


def now_iso():
    return datetime.now(timezone.utc).isoformat()


# ============================================================
# AI API
# ============================================================
def call_ai(messages, timeout=120):
    """OpenAI 兼容 API 调用，返回 content 字符串"""
    if not AI_KEY:
        raise RuntimeError("AI_API_KEY 未设置，请在 .env 中配置")

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
        "Authorization": f"Bearer {AI_KEY}",
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


def call_ai_vision(images_b64, text_prompt, timeout=120):
    """带图片的 Vision API 调用"""
    content = [{"type": "text", "text": text_prompt}]
    for img in images_b64:
        if not img.startswith("data:"):
            img = f"data:image/jpeg;base64,{img}"
        content.append({"type": "image_url", "image_url": {"url": img}})

    return call_ai([{"role": "user", "content": content}], timeout=timeout)


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
    """从目录扫描图片 → 分批 AI 识别 → 合并大纲 → 写入 SQLite"""
    book_id = generate_book_id(subject, grade, semester)
    now = now_iso()

    # 扫描目录
    image_paths = scan_folder_images(folder_path)
    if not image_paths:
        raise RuntimeError(f"目录中没有找到图片文件: {folder_path}")

    total = len(image_paths)
    batch_size = 4
    partial_outlines = []

    # 分批处理
    for i in range(0, total, batch_size):
        batch = image_paths[i:i + batch_size]
        batch_start = i + 1
        batch_end = min(i + batch_size, total)

        # 读取图片为 base64
        images_b64 = [read_image_as_b64(p) for p in batch]

        # 调用 AI
        prompt = BATCH_OUTLINE_PROMPT.format(
            batch_start=batch_start,
            batch_end=batch_end,
            total_pages=total,
        )
        try:
            raw_resp = call_ai_vision(images_b64, prompt, timeout=180)
            partial = parse_json_response(raw_resp)
            partial_outlines.append(partial)
        except Exception as e:
            partial_outlines.append({"units": [], "error": str(e)})

    # 合并大纲
    merged_units = merge_outlines(partial_outlines)

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

    # 写入 SQLite
    with db_lock:
        conn = get_db()
        try:
            conn.execute(
                "INSERT INTO books (id, title, subject, grade, semester, source_type, folder_path, created_at, updated_at) "
                "VALUES (?, ?, ?, ?, ?, 'folder', ?, ?, ?)",
                (book_id, title, subject, grade, semester, folder_path, now, now)
            )

            for u in merged_units:
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
                    if kp_page and kp_page in page_map:
                        conn.execute(
                            "INSERT INTO page_images (id, book_id, unit_id, kp_id, filename, page_number, sort_idx, created_at) "
                            "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                            (uuid.uuid4().hex, book_id, unit_id, kp_id,
                             page_map[kp_page], kp_page, kp_page, now)
                        )

            # 所有页面图片都存一份（用于阅读视图）
            for page_num, fname in page_map.items():
                conn.execute(
                    "INSERT OR IGNORE INTO page_images (id, book_id, filename, page_number, sort_idx, created_at) "
                    "VALUES (?, ?, ?, ?, ?, ?)",
                    (f"{book_id}-p{page_num}", book_id, fname, page_num, page_num, now)
                )

            conn.commit()
        finally:
            conn.close()

    result = get_book_detail(book_id)
    result["total_pages"] = total
    result["batches"] = len(partial_outlines)
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


def extract_texts_for_book(book_id, force=False):
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
        batch_size = 3
        extracted = 0

        for i in range(0, len(to_extract), batch_size):
            batch = to_extract[i:i + batch_size]
            images_b64 = []
            for p in batch:
                img_path = os.path.join(book_img_dir, p["filename"])
                if os.path.exists(img_path):
                    images_b64.append(read_image_as_b64(img_path))

            if not images_b64:
                continue

            try:
                raw_resp = call_ai_vision(images_b64, EXTRACT_TEXT_PROMPT, timeout=120)
                # AI 可能返回多段文本（每张图片一段），用 --- 分隔
                texts = raw_resp.split("---") if "---" in raw_resp else [raw_resp]

                for j, p in enumerate(batch):
                    text = texts[j].strip() if j < len(texts) else texts[0].strip()
                    conn.execute(
                        "INSERT OR REPLACE INTO page_texts (id, book_id, page_number, text_content, created_at) "
                        "VALUES (?, ?, ?, ?, ?)",
                        (f"{book_id}-pt-{p['page_number']}", book_id, p["page_number"], text, now)
                    )
                    extracted += 1
                conn.commit()
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


def get_or_generate_questions(kp_id):
    """获取当前激活题目集；无则自动生成 v1"""
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
    return generate_questions_for_kp(kp_id, version=1)


def generate_questions_for_kp(kp_id, version=None):
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
    )

    # 调用 AI
    raw_resp = call_ai([
        {"role": "system", "content": QUESTION_SYSTEM},
        {"role": "user", "content": user_prompt},
    ], timeout=120)

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

                def _do_extract():
                    try:
                        result = extract_texts_for_book(book_id, force=force)
                        _extract_jobs[job_key] = {"status": "done", "result": result}
                    except Exception as e:
                        _extract_jobs[job_key] = {"status": "error", "message": str(e)}

                t = _threading.Thread(target=_do_extract, daemon=True)
                t.start()
                self._send_json({"status": "started", "message": "识别任务已启动"})
                return

            # /books/:id/extract-status — 查询提取状态
            if len(parts) == 3 and parts[0] == "books" and parts[2] == "extract-status":
                job = _extract_jobs.get(parts[1], {"status": "idle"})
                self._send_json(job)
                return

            # /lessons/:lessonId/questions
            if len(parts) == 3 and parts[0] == "lessons" and parts[2] == "questions":
                result = get_or_generate_questions(parts[1])
                self._send_json(result)
                return

            # /lessons/:lessonId/refresh
            if len(parts) == 3 and parts[0] == "lessons" and parts[2] == "refresh":
                result = generate_questions_for_kp(parts[1])
                self._send_json(result)
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
