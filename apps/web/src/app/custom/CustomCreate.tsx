"use client";

import { useState, useRef } from "react";
import { apiPost, navigate, compressImage, type CustomBook } from "@/lib/customApi";

const subjects = [
  { value: "math", label: "数学" },
  { value: "chinese", label: "语文" },
  { value: "english", label: "英语" },
  { value: "science", label: "科学" },
];

export function CustomCreate() {
  const [title, setTitle] = useState("");
  const [subject, setSubject] = useState("math");
  const [grade, setGrade] = useState(1);
  const [semester, setSemester] = useState("up");
  const [images, setImages] = useState<string[]>([]);
  const [previewUrls, setPreviewUrls] = useState<string[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const fileRef = useRef<HTMLInputElement>(null);

  async function handleFiles(files: FileList | null) {
    if (!files || files.length === 0) return;
    const compressed: string[] = [];
    const previews: string[] = [];
    for (const file of Array.from(files)) {
      try {
        const dataUrl = await compressImage(file, 1280, 0.65);
        compressed.push(dataUrl);
        previews.push(dataUrl);
      } catch {
        alert(`图片处理失败: ${file.name}`);
      }
    }
    setImages(prev => [...prev, ...compressed]);
    setPreviewUrls(prev => [...prev, ...previews]);
  }

  function removeImage(index: number) {
    setImages(prev => prev.filter((_, i) => i !== index));
    setPreviewUrls(prev => prev.filter((_, i) => i !== index));
  }

  async function handleSubmit() {
    if (!title.trim()) { setError("请输入教材名称"); return; }
    if (images.length === 0) { setError("请上传至少一张教材照片"); return; }

    setLoading(true);
    setError("");
    try {
      const book = await apiPost<CustomBook>("books", {
        title: title.trim(),
        subject,
        grade,
        semester,
        images,
      });
      navigate(`/custom/book/${book.id}/`);
    } catch (e: any) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="min-h-screen bg-bg p-4 md:p-6">
      <div className="mx-auto max-w-2xl">
        <div className="flex items-center gap-3 mb-6">
          <button onClick={() => navigate("/custom/")} className="text-text-muted hover:text-text">←</button>
          <h1 className="text-2xl font-bold text-text">创建自定义教材</h1>
        </div>

        {loading ? (
          <div className="flex flex-col items-center justify-center py-20">
            <div className="animate-spin rounded-full h-12 w-12 border-4 border-violet-500 border-t-transparent mb-4" />
            <p className="text-text font-bold">AI 正在识别教材内容</p>
            <p className="text-sm text-text-muted mt-1">分析图片、提取单元和知识点...（约 30-60 秒）</p>
          </div>
        ) : (
          <div className="space-y-5">
            <div>
              <label className="block text-sm font-bold text-text mb-2">教材名称</label>
              <input
                type="text"
                value={title}
                onChange={e => setTitle(e.target.value)}
                placeholder="如：广州版小学数学三年级上册"
                className="w-full rounded-xl bg-bg-soft px-4 py-3 text-text placeholder:text-text-muted/50 outline-none focus:ring-2 ring-violet-500/40"
              />
            </div>

            <div className="grid grid-cols-3 gap-3">
              <div>
                <label className="block text-sm font-bold text-text mb-2">学科</label>
                <select value={subject} onChange={e => setSubject(e.target.value)}
                  className="w-full rounded-xl bg-bg-soft px-3 py-3 text-text outline-none">
                  {subjects.map(s => <option key={s.value} value={s.value}>{s.label}</option>)}
                </select>
              </div>
              <div>
                <label className="block text-sm font-bold text-text mb-2">年级</label>
                <select value={grade} onChange={e => setGrade(Number(e.target.value))}
                  className="w-full rounded-xl bg-bg-soft px-3 py-3 text-text outline-none">
                  {[1,2,3,4,5,6].map(g => <option key={g} value={g}>{g}年级</option>)}
                </select>
              </div>
              <div>
                <label className="block text-sm font-bold text-text mb-2">学期</label>
                <select value={semester} onChange={e => setSemester(e.target.value)}
                  className="w-full rounded-xl bg-bg-soft px-3 py-3 text-text outline-none">
                  <option value="up">上册</option>
                  <option value="down">下册</option>
                </select>
              </div>
            </div>

            <div>
              <label className="block text-sm font-bold text-text mb-2">教材拍照（目录页 + 内容页）</label>
              <input
                ref={fileRef}
                type="file"
                accept="image/*"
                multiple
                capture="environment"
                onChange={e => handleFiles(e.target.files)}
                className="hidden"
              />
              <button
                onClick={() => fileRef.current?.click()}
                className="w-full flex items-center justify-center gap-2 rounded-2xl border-2 border-dashed border-violet-400/40 bg-violet-500/10 px-4 py-8 text-violet-300 hover:bg-violet-500/20 transition-colors"
              >
                <span className="text-3xl">📷</span>
                <span className="font-bold">点击拍照或选择图片</span>
              </button>
              {previewUrls.length > 0 && (
                <div className="mt-3 grid grid-cols-3 gap-2">
                  {previewUrls.map((url, i) => (
                    <div key={i} className="relative group">
                      <img src={url} alt={`page ${i+1}`} className="w-full h-24 object-cover rounded-lg" />
                      <button
                        onClick={() => removeImage(i)}
                        className="absolute top-1 right-1 rounded-full bg-black/60 text-white text-xs w-5 h-5 flex items-center justify-center opacity-0 group-hover:opacity-100"
                      >✕</button>
                    </div>
                  ))}
                </div>
              )}
              <p className="text-xs text-text-muted mt-2">支持多张图片，建议拍目录页和各单元内容页</p>
            </div>

            {error && (
              <div className="rounded-xl bg-red-500/10 border border-red-500/30 p-4 text-red-400 text-sm">
                {error}
              </div>
            )}

            <button
              onClick={handleSubmit}
              disabled={loading}
              className="w-full rounded-xl bg-violet-500 px-4 py-3.5 font-bold text-white hover:bg-violet-600 transition-colors disabled:opacity-50"
            >
              AI 识别并创建
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
