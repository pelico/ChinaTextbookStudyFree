"use client";

import { useState, useEffect, useCallback } from "react";
import {
  navigate, listFolders, createBookFromFolder,
  type FolderInfo,
} from "@/lib/customApi";
import { ArrowLeft } from "@/components/icons";

const subjectOptions = [
  { value: "chinese", label: "语文" },
  { value: "math", label: "数学" },
  { value: "english", label: "英语" },
  { value: "science", label: "科学" },
];

const gradeOptions = [1, 2, 3, 4, 5, 6];
const semesterOptions = [
  { value: "up", label: "上册" },
  { value: "down", label: "下册" },
];

export function CustomFolderCreate() {
  const [title, setTitle] = useState("");
  const [subject, setSubject] = useState("chinese");
  const [grade, setGrade] = useState(3);
  const [semester, setSemester] = useState("up");
  const [folderPath, setFolderPath] = useState("");
  const [folders, setFolders] = useState<FolderInfo[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [statusMsg, setStatusMsg] = useState("");
  const [foldersLoading, setFoldersLoading] = useState(true);

  const loadFolders = useCallback(async () => {
    setFoldersLoading(true);
    try {
      const list = await listFolders();
      setFolders(list);
      if (list.length > 0 && !folderPath) {
        setFolderPath(list[0].path);
      }
    } catch {
      setFolders([]);
    } finally {
      setFoldersLoading(false);
    }
  }, [folderPath]);

  useEffect(() => { loadFolders(); }, [loadFolders]);

  async function handleSubmit() {
    setError("");
    if (!title.trim()) { setError("请输入教材名称"); return; }
    if (!folderPath.trim()) { setError("请选择或输入目录路径"); return; }

    setLoading(true);
    setStatusMsg("正在扫描目录并创建教材...");
    try {
      const book = await createBookFromFolder(
        title.trim(), subject, grade, semester, folderPath.trim()
      );
      setStatusMsg(`创建完成：${book.total_pages || 0} 页，接下来提取文字`);
      setTimeout(() => navigate(`/custom/book/${book.id}/`), 1000);
    } catch (e: any) {
      setError(e.message);
      setStatusMsg("");
    } finally {
      setLoading(false);
    }
  }

  return (
    <main className="min-h-screen bg-bg-soft pb-20 md:pb-8">
      <header className="sticky top-0 z-30 bg-white border-b border-bg-softer px-4 py-3 md:px-6">
        <div className="flex items-center gap-3 max-w-3xl mx-auto">
          <button onClick={() => navigate("/custom/")} className="text-ink-softer hover:text-ink transition-colors">
            <ArrowLeft className="w-5 h-5" />
          </button>
          <h1 className="text-lg font-extrabold text-ink">从文件夹创建教材</h1>
        </div>
      </header>

      <div className="max-w-3xl mx-auto px-4 py-6 space-y-5 md:px-6">
        <div>
          <label className="block text-sm font-extrabold text-ink mb-2">教材名称</label>
          <input
            type="text"
            value={title}
            onChange={e => setTitle(e.target.value)}
            placeholder="如：义务教育教科书·语文（三年级起点）三年级上册"
            className="w-full rounded-xl border-2 border-bg-softer bg-white px-4 py-3 text-ink outline-none focus:border-primary transition-colors"
          />
        </div>

        <div className="grid grid-cols-3 gap-3">
          <div>
            <label className="block text-sm font-extrabold text-ink mb-2">学科</label>
            <select
              value={subject}
              onChange={e => setSubject(e.target.value)}
              className="w-full rounded-xl border-2 border-bg-softer bg-white px-3 py-3 text-ink outline-none focus:border-primary"
            >
              {subjectOptions.map(o => (
                <option key={o.value} value={o.value}>{o.label}</option>
              ))}
            </select>
          </div>
          <div>
            <label className="block text-sm font-extrabold text-ink mb-2">年级</label>
            <select
              value={grade}
              onChange={e => setGrade(Number(e.target.value))}
              className="w-full rounded-xl border-2 border-bg-softer bg-white px-3 py-3 text-ink outline-none focus:border-primary"
            >
              {gradeOptions.map(g => (
                <option key={g} value={g}>{g}年级</option>
              ))}
            </select>
          </div>
          <div>
            <label className="block text-sm font-extrabold text-ink mb-2">学期</label>
            <select
              value={semester}
              onChange={e => setSemester(e.target.value)}
              className="w-full rounded-xl border-2 border-bg-softer bg-white px-3 py-3 text-ink outline-none focus:border-primary"
            >
              {semesterOptions.map(o => (
                <option key={o.value} value={o.value}>{o.label}</option>
              ))}
            </select>
          </div>
        </div>

        <div>
          <label className="block text-sm font-extrabold text-ink mb-2">
            教材图片目录
          </label>
          <p className="text-xs text-ink-light mb-2">
            将教材拍照或扫描的图片放到持久化目录，每页一张图。创建后进入阅读页逐页提取文字，可人工修正，再从文字生成大纲和题目。
          </p>
          {foldersLoading ? (
            <div className="rounded-xl border-2 border-bg-softer bg-white px-4 py-3 text-ink-light text-sm">
              正在扫描可用目录...
            </div>
          ) : folders.length > 0 ? (
            <div className="space-y-2">
              {folders.map(f => (
                <button
                  key={f.path}
                  onClick={() => setFolderPath(f.path)}
                  className={`w-full text-left rounded-xl px-4 py-3 transition-colors border-2 ${
                    folderPath === f.path
                      ? "bg-primary/10 border-primary"
                      : "bg-white border-bg-softer hover:border-ink/15"
                  }`}
                >
                  <div className="flex items-center justify-between">
                    <span className="text-sm font-extrabold text-ink">{f.name}</span>
                    <span className="text-xs text-ink-light">{f.image_count} 张</span>
                  </div>
                  <div className="text-xs text-ink-softer mt-0.5 truncate">{f.path}</div>
                </button>
              ))}
            </div>
          ) : (
            <div className="rounded-xl border-2 border-warning/30 bg-warning/10 px-4 py-3 text-ink text-sm">
              持久化目录 /data/textbooks/ 下没有找到子目录。
              <br />
              请在 Docker 卷中创建子目录并放入图片：
              <code className="block mt-1 text-xs bg-bg-soft px-2 py-1 rounded">
                docker exec china-study-free mkdir -p /data/textbooks/grade3-english
              </code>
            </div>
          )}
          <input
            type="text"
            value={folderPath}
            onChange={e => setFolderPath(e.target.value)}
            placeholder="/data/textbooks/你的教材目录"
            className="w-full mt-2 rounded-xl border-2 border-bg-softer bg-white px-4 py-3 text-ink text-sm outline-none focus:border-primary transition-colors"
          />
        </div>

        {error && (
          <div className="rounded-xl bg-danger/10 border-2 border-danger/30 px-4 py-3 text-danger-dark text-sm font-bold">
            {error}
          </div>
        )}

        {statusMsg && (
          <div className="rounded-xl border-2 border-primary/30 bg-primary/10 px-4 py-3 text-primary-dark text-sm">
            {loading && (
              <div className="inline-block w-4 h-4 mr-2 border-2 border-primary border-t-transparent rounded-full animate-spin" />
            )}
            {statusMsg}
          </div>
        )}

        <button
          onClick={handleSubmit}
          disabled={loading}
          className="w-full rounded-2xl bg-primary px-4 py-3.5 text-white font-extrabold hover:bg-primary-dark disabled:opacity-50 transition-colors shadow-lg shadow-primary/30"
        >
          {loading ? "创建中..." : "创建教材"}
        </button>
      </div>
    </main>
  );
}
