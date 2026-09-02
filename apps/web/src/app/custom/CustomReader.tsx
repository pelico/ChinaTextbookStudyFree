"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import {
  navigate, getBookRead, extractBookText, getExtractStatus,
  updatePageText, imageUrl, type BookReadData,
} from "@/lib/customApi";
import {
  speakText, stopSpeaking, pauseSpeaking, resumeSpeaking,
  isSpeechSupported, type SpeakOptions,
} from "@/lib/speechTts";
import { requireParentAuth } from "@/lib/parentAuth";
import { ArrowLeft } from "@/components/icons";

export function CustomReader({ bookId }: { bookId: string }) {
  const [data, setData] = useState<BookReadData | null>(null);
  const [loading, setLoading] = useState(true);
  const [extracting, setExtracting] = useState(false);
  const [pageIdx, setPageIdx] = useState(0);
  const [speaking, setSpeaking] = useState(false);
  const [paused, setPaused] = useState(false);
  const [highlightIdx, setHighlightIdx] = useState(-1);
  const [rate, setRate] = useState(1);
  const [error, setError] = useState("");
  const [editing, setEditing] = useState(false);
  const [editText, setEditText] = useState("");
  const [saving, setSaving] = useState(false);
  const [saveMsg, setSaveMsg] = useState("");
  const textRef = useRef<HTMLDivElement>(null);
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const load = useCallback(async () => {
    try {
      const d = await getBookRead(bookId);
      setData(d);
    } catch (e: any) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }, [bookId]);

  useEffect(() => { load(); }, [load]);

  useEffect(() => {
    return () => {
      stopSpeaking();
      if (pollRef.current) clearInterval(pollRef.current);
    };
  }, []);

  const page = data?.pages[pageIdx];
  const lang = data?.book.subject === "english" ? "en-US" : "zh-CN";

  function handleSpeak() {
    if (!page?.text_content) return;
    if (speaking && !paused) {
      pauseSpeaking();
      setPaused(true);
      return;
    }
    if (speaking && paused) {
      resumeSpeaking();
      setPaused(false);
      return;
    }
    const opts: SpeakOptions = {
      lang,
      rate,
      onSentence: (idx) => setHighlightIdx(idx),
      onEnd: () => {
        setSpeaking(false);
        setPaused(false);
        setHighlightIdx(-1);
      },
    };
    speakText(page.text_content, opts);
    setSpeaking(true);
    setPaused(false);
  }

  function handleStop() {
    stopSpeaking();
    setSpeaking(false);
    setPaused(false);
    setHighlightIdx(-1);
  }

  function handlePrev() {
    handleStop();
    setEditing(false);
    if (pageIdx > 0) setPageIdx(pageIdx - 1);
  }

  function handleNext() {
    handleStop();
    setEditing(false);
    if (data && pageIdx < data.pages.length - 1) setPageIdx(pageIdx + 1);
  }

  async function handleStartEdit() {
    const ok = await requireParentAuth("编辑文字");
    if (!ok) return;
    handleStop();
    setEditText(page?.text_content || "");
    setEditing(true);
  }

  function handleCancelEdit() {
    setEditing(false);
    setSaveMsg("");
  }

  async function handleSaveEdit() {
    if (!page) return;
    setSaving(true);
    setSaveMsg("");
    try {
      await updatePageText(bookId, page.page_number, editText);
      setSaveMsg("已保存");
      setEditing(false);
      await load();
      setTimeout(() => setSaveMsg(""), 2000);
    } catch (e: any) {
      setSaveMsg("保存失败: " + e.message);
    } finally {
      setSaving(false);
    }
  }

  async function handleExtract() {
    const ok = await requireParentAuth("重新识别文字");
    if (!ok) return;
    setExtracting(true);
    setError("");
    setEditing(false);
    try {
      const hasText = data?.has_text;
      await extractBookText(bookId, hasText);
      if (pollRef.current) clearInterval(pollRef.current);
      let pollCount = 0;
      const MAX_POLLS = 120;
      pollRef.current = setInterval(async () => {
        pollCount++;
        if (pollCount > MAX_POLLS) {
          if (pollRef.current) clearInterval(pollRef.current);
          pollRef.current = null;
          setExtracting(false);
          setError("识别超时，请检查 AI API Key 是否正确配置");
          return;
        }
        try {
          const status = await getExtractStatus(bookId);
          if (status.status === "done") {
            if (pollRef.current) clearInterval(pollRef.current);
            pollRef.current = null;
            setExtracting(false);
            await load();
          } else if (status.status === "error") {
            if (pollRef.current) clearInterval(pollRef.current);
            pollRef.current = null;
            setExtracting(false);
            setError(status.message || "识别失败");
          }
        } catch {
          // 忽略临时网络错误，继续轮询
        }
      }, 3000);
    } catch (e: any) {
      setExtracting(false);
      setError(e.message);
    }
  }

  function handleAutoNext() {
    if (data && pageIdx < data.pages.length - 1) {
      setPageIdx(pageIdx + 1);
      setTimeout(() => {
        const next = data.pages[pageIdx + 1];
        if (next?.text_content) {
          const opts: SpeakOptions = {
            lang, rate,
            onSentence: (idx) => setHighlightIdx(idx),
            onEnd: () => { setSpeaking(false); setHighlightIdx(-1); },
          };
          speakText(next.text_content, opts);
          setSpeaking(true);
          setPaused(false);
        }
      }, 200);
    }
  }

  if (loading) {
    return (
      <div className="min-h-dvh bg-bg-soft flex items-center justify-center">
        <div className="animate-spin w-8 h-8 border-3 border-primary border-t-transparent rounded-full" />
      </div>
    );
  }

  if (error && !data) {
    return (
      <div className="min-h-dvh bg-bg-soft flex flex-col items-center justify-center gap-3">
        <p className="text-danger font-bold">{error}</p>
        <button onClick={() => navigate(`/custom/book/${bookId}/`)} className="text-primary-dark font-bold">
          ← 返回
        </button>
      </div>
    );
  }

  if (!data || data.pages.length === 0) {
    return (
      <div className="min-h-dvh bg-bg-soft flex flex-col items-center justify-center gap-3">
        <p className="text-ink-light">这本书没有页面图片</p>
        <button onClick={() => navigate(`/custom/book/${bookId}/`)} className="text-primary-dark font-bold">
          ← 返回
        </button>
      </div>
    );
  }

  const sentences = page?.text_content
    ? page.text_content.split(/(?<=[。！？.!?；;])/g).map(s => s.trim()).filter(Boolean)
    : [];

  return (
    <div className="h-dvh flex flex-col overflow-hidden bg-bg-soft">
      {/* 顶栏 */}
      <div className="shrink-0 flex items-center justify-between gap-3 border-b border-bg-softer bg-white/95 backdrop-blur px-4 py-2.5">
        <button onClick={() => navigate(`/custom/book/${bookId}/`)} className="text-sm text-ink-light hover:text-ink transition-colors">
          ← {data.book.title}
        </button>
        <span className="text-xs text-ink-light">
          {pageIdx + 1} / {data.pages.length}
          {saveMsg && <span className="ml-2 text-secondary-dark font-bold">{saveMsg}</span>}
        </span>
      </div>

      {/* 主内容区 */}
      <div className="flex-1 flex flex-col md:flex-row overflow-hidden">
        {/* 图片区 */}
        <div className="flex-1 overflow-y-auto bg-bg-soft/30 flex items-start justify-center p-2 md:p-4">
          {page && (
            <img
              src={imageUrl(bookId, page.filename)}
              alt={`第${page.page_number}页`}
              className="max-w-full h-auto rounded-lg shadow-lg"
            />
          )}
        </div>

        {/* 文字区 */}
        <div className="md:w-[420px] shrink-0 flex flex-col border-t md:border-t-0 md:border-l border-bg-softer overflow-hidden">
          {/* 控制栏 */}
          <div className="shrink-0 flex items-center gap-2 border-b border-bg-softer px-4 py-2.5 bg-white/95 flex-wrap">
            {page?.text_content ? (
              <>
                {!editing && (
                  <>
                    <button
                      onClick={handleSpeak}
                      className={`flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-sm font-bold transition-colors ${
                        speaking && !paused
                          ? "bg-warning/20 text-ink"
                          : "bg-primary/10 text-primary-dark hover:bg-primary/20"
                      }`}
                    >
                      {speaking && !paused ? "⏸ 暂停" : paused ? "▶ 继续" : "🔊 朗读"}
                    </button>
                    {(speaking || paused) && (
                      <button
                        onClick={handleStop}
                        className="rounded-lg bg-danger/10 px-3 py-1.5 text-sm text-danger-dark hover:bg-danger/20"
                      >
                        ⏹ 停止
                      </button>
                    )}
                    <select
                      value={rate}
                      onChange={e => { setRate(Number(e.target.value)); handleStop(); }}
                      className="rounded-lg bg-bg-soft px-2 py-1 text-xs text-ink outline-none"
                    >
                      <option value={0.8}>慢速</option>
                      <option value={1}>正常</option>
                      <option value={1.2}>快速</option>
                      <option value={1.5}>极速</option>
                    </select>
                    <button
                      onClick={handleStartEdit}
                      className="rounded-lg bg-secondary/10 px-2 py-1 text-xs text-secondary-dark hover:bg-secondary/20"
                      title="编辑文字"
                    >
                      ✏️ 编辑
                    </button>
                    <button
                      onClick={handleExtract}
                      disabled={extracting}
                      className="rounded-lg bg-secondary/10 px-2 py-1 text-xs text-secondary-dark hover:bg-secondary/20 disabled:opacity-50"
                      title="重新识别文字"
                    >
                      {extracting ? "⏳ 识别中..." : "🔄 重新识别"}
                    </button>
                    {isSpeechSupported() ? null : (
                      <span className="text-xs text-warning">浏览器不支持语音</span>
                    )}
                  </>
                )}
                {editing && (
                  <>
                    <button
                      onClick={handleSaveEdit}
                      disabled={saving}
                      className="flex items-center gap-1.5 rounded-lg bg-secondary px-3 py-1.5 text-sm text-white font-bold hover:bg-secondary-dark disabled:opacity-50"
                    >
                      {saving ? "保存中..." : "💾 保存"}
                    </button>
                    <button
                      onClick={handleCancelEdit}
                      disabled={saving}
                      className="rounded-lg bg-bg-soft px-3 py-1.5 text-sm text-ink-light hover:bg-bg-softer disabled:opacity-50"
                    >
                      取消
                    </button>
                  </>
                )}
              </>
            ) : (
              <button
                onClick={handleExtract}
                disabled={extracting}
                className="flex items-center gap-1.5 rounded-lg bg-secondary/10 px-3 py-1.5 text-sm text-secondary-dark hover:bg-secondary/20 disabled:opacity-50"
              >
                {extracting ? (
                  <>
                    <div className="animate-spin w-3.5 h-3.5 border-2 border-secondary border-t-transparent rounded-full" />
                    提取中...
                  </>
                ) : (
                  <>📝 提取文字</>
                )}
              </button>
            )}
          </div>

          {/* 文字内容 */}
          <div ref={textRef} className="flex-1 overflow-y-auto px-4 py-4 bg-white">
            {editing ? (
              <textarea
                value={editText}
                onChange={e => setEditText(e.target.value)}
                className="w-full h-full min-h-[300px] resize-none rounded-lg bg-bg-soft px-3 py-2 text-sm text-ink outline-none focus:ring-2 focus:ring-primary/40 border-2 border-bg-softer focus:border-primary"
                placeholder="在此编辑文字内容..."
                autoFocus
              />
            ) : page?.text_content ? (
              <div className="space-y-1.5 text-sm leading-relaxed text-ink">
                {sentences.map((s, i) => (
                  <span
                    key={i}
                    className={`block cursor-pointer rounded px-1.5 -mx-1.5 transition-colors ${
                      i === highlightIdx
                        ? "bg-primary/30 text-ink font-medium shadow-sm"
                        : "hover:bg-bg-soft/50"
                    }`}
                    onClick={() => {
                      if (speaking) {
                        stopSpeaking();
                        setSpeaking(false);
                        setPaused(false);
                      }
                      const opts: SpeakOptions = {
                        lang, rate,
                        onSentence: (idx) => setHighlightIdx(idx),
                        onEnd: () => { setSpeaking(false); setHighlightIdx(-1); },
                      };
                      speakText(sentences.slice(i).join(""), opts);
                      setSpeaking(true);
                      setPaused(false);
                    }}
                  >
                    {s}
                  </span>
                ))}
              </div>
            ) : (
              <div className="flex flex-col items-center justify-center h-full text-ink-light gap-3">
                <span className="text-4xl opacity-30">📄</span>
                <p className="text-sm">点击上方"提取文字"按钮</p>
                <p className="text-xs">AI 会逐页识别图片中的文字内容</p>
                <p className="text-xs text-ink-softer">识别后可编辑修正，再生成题目</p>
              </div>
            )}
            {error && (
              <p className="mt-3 text-xs text-danger">{error}</p>
            )}
          </div>

          {/* 翻页 */}
          <div className="shrink-0 flex items-center justify-between gap-3 border-t border-bg-softer px-4 py-2.5 bg-white">
            <button
              onClick={handlePrev}
              disabled={pageIdx === 0}
              className="rounded-lg bg-bg-soft px-3 py-1.5 text-sm text-ink disabled:opacity-30"
            >
              ← 上一页
            </button>
            {speaking && !paused && !editing && (
              <button
                onClick={handleAutoNext}
                className="text-xs text-primary-dark font-bold"
              >
                下一页 ▶
              </button>
            )}
            <button
              onClick={handleNext}
              disabled={pageIdx >= data.pages.length - 1}
              className="rounded-lg bg-bg-soft px-3 py-1.5 text-sm text-ink disabled:opacity-30"
            >
              下一页 →
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
