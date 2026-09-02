"use client";

import { useState, useRef } from "react";
import { navigate, compressImage, createExam } from "@/lib/customApi";
import { DIFFICULTY_LABELS, type ExamDifficulty } from "@/lib/customApi";
import { ArrowLeft } from "@/components/icons";

const subjects = [
  { value: "math", label: "数学" },
  { value: "chinese", label: "语文" },
  { value: "english", label: "英语" },
  { value: "science", label: "科学" },
];

const difficulties = Object.entries(DIFFICULTY_LABELS).map(([value, label]) => ({ value, label }));

export function CustomExamCreate() {
  const [title, setTitle] = useState("");
  const [subject, setSubject] = useState("math");
  const [grade, setGrade] = useState(1);
  const [semester, setSemester] = useState("up");
  const [difficulty, setDifficulty] = useState<ExamDifficulty>("mid_final");
  const [images, setImages] = useState<string[]>([]);
  const [previewUrls, setPreviewUrls] = useState<string[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const fileRef = useRef<HTMLInputElement>(null);

  async function handleFiles(files: FileList | null) {
    if (!files || files.length === 0) return;
    const processed: string[] = [];
    const previews: string[] = [];
    for (const file of Array.from(files)) {
      try {
        if (file.type === "application/pdf") {
          const dataUrl = await new Promise<string>((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => resolve(reader.result as string);
            reader.onerror = reject;
            reader.readAsDataURL(file);
          });
          processed.push(dataUrl);
          previews.push("__pdf__");
        } else {
          const dataUrl = await compressImage(file, 1280, 0.65);
          processed.push(dataUrl);
          previews.push(dataUrl);
        }
      } catch {
        alert(`文件处理失败: ${file.name}`);
      }
    }
    setImages(prev => [...prev, ...processed]);
    setPreviewUrls(prev => [...prev, ...previews]);
  }

  function removeImage(index: number) {
    setImages(prev => prev.filter((_, i) => i !== index));
    setPreviewUrls(prev => prev.filter((_, i) => i !== index));
  }

  async function handleSubmit() {
    if (!title.trim()) { setError("请输入试卷名称"); return; }
    if (images.length === 0) { setError("请上传至少一张试卷照片或 PDF"); return; }

    setLoading(true);
    setError("");
    try {
      const exam = await createExam(title.trim(), subject, grade, semester, difficulty, images);
      navigate(`/custom/exam/${exam.id}`);
    } catch (e: any) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }

  return (
    <main className="min-h-screen bg-bg-soft pb-20 md:pb-8">
      <header className="sticky top-0 z-30 bg-white border-b border-bg-softer px-4 py-3 md:px-6">
        <div className="flex items-center gap-3 max-w-3xl mx-auto">
          <button onClick={() => navigate("/custom/exams")} className="text-ink-softer hover:text-ink transition-colors">
            <ArrowLeft className="w-5 h-5" />
          </button>
          <h1 className="text-lg font-extrabold text-ink">上传真题</h1>
        </div>
      </header>

      <div className="max-w-3xl mx-auto px-4 py-6 space-y-5 md:px-6">
        <div>
          <label className="block text-sm font-bold text-ink mb-1.5">试卷名称</label>
          <input
            type="text"
            value={title}
            onChange={e => setTitle(e.target.value)}
            placeholder="如：二年级数学上册期末真题"
            className="w-full rounded-xl border-2 border-bg-softer bg-white px-4 py-2.5 text-sm text-ink focus:border-primary focus:outline-none"
          />
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-sm font-bold text-ink mb-1.5">学科</label>
            <select
              value={subject}
              onChange={e => setSubject(e.target.value)}
              className="w-full rounded-xl border-2 border-bg-softer bg-white px-4 py-2.5 text-sm text-ink focus:border-primary focus:outline-none"
            >
              {subjects.map(s => <option key={s.value} value={s.value}>{s.label}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-sm font-bold text-ink mb-1.5">年级</label>
            <select
              value={grade}
              onChange={e => setGrade(Number(e.target.value))}
              className="w-full rounded-xl border-2 border-bg-softer bg-white px-4 py-2.5 text-sm text-ink focus:border-primary focus:outline-none"
            >
              {[1,2,3,4,5,6].map(g => <option key={g} value={g}>{g}年级</option>)}
            </select>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-sm font-bold text-ink mb-1.5">学期</label>
            <select
              value={semester}
              onChange={e => setSemester(e.target.value)}
              className="w-full rounded-xl border-2 border-bg-softer bg-white px-4 py-2.5 text-sm text-ink focus:border-primary focus:outline-none"
            >
              <option value="up">上册</option>
              <option value="down">下册</option>
            </select>
          </div>
          <div>
            <label className="block text-sm font-bold text-ink mb-1.5">难度</label>
            <select
              value={difficulty}
              onChange={e => setDifficulty(e.target.value as ExamDifficulty)}
              className="w-full rounded-xl border-2 border-bg-softer bg-white px-4 py-2.5 text-sm text-ink focus:border-primary focus:outline-none"
            >
              {difficulties.map(d => <option key={d.value} value={d.value}>{d.label}</option>)}
            </select>
          </div>
        </div>

        <div>
          <label className="block text-sm font-bold text-ink mb-1.5">试卷照片 / PDF</label>
          <input
            ref={fileRef}
            type="file"
            accept="image/*,application/pdf"
            multiple
            className="hidden"
            onChange={e => { handleFiles(e.target.files); e.target.value = ""; }}
          />
          <button
            onClick={() => fileRef.current?.click()}
            className="w-full rounded-2xl border-2 border-dashed border-bg-softer bg-white px-4 py-8 text-center hover:border-primary/30 transition-colors"
          >
            <span className="text-3xl block mb-1">📷</span>
            <span className="text-sm text-ink-light">点击上传试卷照片或 PDF</span>
          </button>

          {previewUrls.length > 0 && (
            <div className="grid grid-cols-3 gap-2 mt-3">
              {previewUrls.map((url, i) => (
                <div key={i} className="relative group">
                  {url === "__pdf__" ? (
                    <div className="aspect-[3/4] rounded-lg border-2 border-bg-softer flex items-center justify-center text-2xl">📄</div>
                  ) : (
                    <img src={url} alt="" className="aspect-[3/4] object-cover rounded-lg border-2 border-bg-softer" />
                  )}
                  <button
                    onClick={() => removeImage(i)}
                    className="absolute top-1 right-1 w-5 h-5 rounded-full bg-danger text-white text-xs flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity"
                  >
                    ×
                  </button>
                </div>
              ))}
            </div>
          )}
        </div>

        {error && (
          <div className="px-4 py-3 rounded-xl bg-danger/10 border-2 border-danger/30 text-sm text-danger-dark font-bold">
            {error}
          </div>
        )}

        <button
          onClick={handleSubmit}
          disabled={loading}
          className="w-full flex items-center justify-center gap-2 rounded-xl bg-primary px-4 py-3 text-white font-extrabold hover:bg-primary-dark disabled:opacity-50 transition-colors"
        >
          {loading ? (
            <>
              <div className="animate-spin w-4 h-4 border-2 border-white border-t-transparent rounded-full" />
              创建中...
            </>
          ) : (
            <>创建真题</>
          )}
        </button>
      </div>
    </main>
  );
}
