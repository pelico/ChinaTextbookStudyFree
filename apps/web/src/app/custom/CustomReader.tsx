"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import { navigate, getBookRead, extractBookText, imageUrl, type BookReadData } from "@/lib/customApi";
import {
  speakText, stopSpeaking, pauseSpeaking, resumeSpeaking,
  isSpeechSupported, type SpeakOptions,
} from "@/lib/speechTts";

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
  const textRef = useRef<HTMLDivElement>(null);

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
    return () => stopSpeaking();
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
    if (pageIdx > 0) setPageIdx(pageIdx - 1);
  }

  function handleNext() {
    handleStop();
    if (data && pageIdx < data.pages.length - 1) setPageIdx(pageIdx + 1);
  }

  async function handleExtract() {
    setExtracting(true);
    setError("");
    try {
      const hasText = data?.has_text;
      await extractBookText(bookId, hasText);  // 已有文字时 force=true 重新识别
      await load();
    } catch (e: any) {
      setError(e.message);
    } finally {
      setExtracting(false);
    }
  }

  // 自动朗读下一页
  function handleAutoNext() {
    if (data && pageIdx < data.pages.length - 1) {
      setPageIdx(pageIdx + 1);
      // 下一页自动开始朗读
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
      <div className="min-h-dvh bg-bg flex items-center justify-center">
        <div className="animate-spin w-8 h-8 border-3 border-violet-400 border-t-transparent rounded-full" />
      </div>
    );
  }

  if (error && !data) {
    return (
      <div className="min-h-dvh bg-bg flex flex-col items-center justify-center gap-3">
        <p className="text-red-400">{error}</p>
        <button onClick={() => navigate(`/custom/book/${bookId}/`)} className="text-violet-400">
          ← 返回
        </button>
      </div>
    );
  }

  if (!data || data.pages.length === 0) {
    return (
      <div className="min-h-dvh bg-bg flex flex-col items-center justify-center gap-3">
        <p className="text-text-muted">这本书没有页面图片</p>
        <button onClick={() => navigate(`/custom/book/${bookId}/`)} className="text-violet-400">
          ← 返回
        </button>
      </div>
    );
  }

  const sentences = page?.text_content
    ? page.text_content.split(/(?<=[。！？.!?；;])/g).map(s => s.trim()).filter(Boolean)
    : [];

  return (
    <div className="h-dvh flex flex-col overflow-hidden bg-bg">
      {/* 顶栏 */}
      <div className="shrink-0 flex items-center justify-between gap-3 border-b border-bg-soft bg-bg/95 backdrop-blur px-4 py-2.5">
        <button onClick={() => navigate(`/custom/book/${bookId}/`)} className="text-sm text-text-muted hover:text-text">
          ← {data.book.title}
        </button>
        <span className="text-xs text-text-muted">
          {pageIdx + 1} / {data.pages.length}
        </span>
      </div>

      {/* 主内容区 */}
      <div className="flex-1 flex flex-col md:flex-row overflow-hidden">
        {/* 图片区 */}
        <div className="flex-1 md:flex-1 overflow-y-auto bg-bg-soft/30 flex items-start justify-center p-2 md:p-4">
          {page && (
            <img
              src={imageUrl(bookId, page.filename)}
              alt={`第${page.page_number}页`}
              className="max-w-full h-auto rounded-lg shadow-lg"
            />
          )}
        </div>

        {/* 文字区 */}
        <div className="md:w-[420px] shrink-0 flex flex-col border-t md:border-t-0 md:border-l border-bg-soft overflow-hidden">
          {/* TTS 控制栏 */}
          <div className="shrink-0 flex items-center gap-2 border-b border-bg-soft px-4 py-2.5 bg-bg/95">
            {page?.text_content ? (
              <>
                <button
                  onClick={handleSpeak}
                  className={`flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-sm font-bold transition-colors ${
                    speaking && !paused
                      ? "bg-amber-500/20 text-amber-300"
                      : "bg-violet-500/15 text-violet-300 hover:bg-violet-500/25"
                  }`}
                >
                  {speaking && !paused ? "⏸ 暂停" : paused ? "▶ 继续" : "🔊 朗读"}
                </button>
                {(speaking || paused) && (
                  <button
                    onClick={handleStop}
                    className="rounded-lg bg-red-500/15 px-3 py-1.5 text-sm text-red-300 hover:bg-red-500/25"
                  >
                    ⏹ 停止
                  </button>
                )}
                <select
                  value={rate}
                  onChange={e => { setRate(Number(e.target.value)); handleStop(); }}
                  className="rounded-lg bg-bg-soft px-2 py-1 text-xs text-text outline-none"
                >
                  <option value={0.8}>慢速</option>
                  <option value={1}>正常</option>
                  <option value={1.2}>快速</option>
                  <option value={1.5}>极速</option>
                </select>
                <button
                  onClick={handleExtract}
                  disabled={extracting}
                  className="rounded-lg bg-emerald-500/15 px-2 py-1 text-xs text-emerald-300 hover:bg-emerald-500/25 disabled:opacity-50"
                  title="重新识别文字"
                >
                  {extracting ? "⏳ 识别中..." : "🔄 重新识别"}
                </button>
                {isSpeechSupported() ? null : (
                  <span className="text-xs text-amber-400">浏览器不支持语音</span>
                )}
              </>
            ) : (
              <button
                onClick={handleExtract}
                disabled={extracting}
                className="flex items-center gap-1.5 rounded-lg bg-emerald-500/15 px-3 py-1.5 text-sm text-emerald-300 hover:bg-emerald-500/25 disabled:opacity-50"
              >
                {extracting ? (
                  <>
                    <div className="animate-spin w-3.5 h-3.5 border-2 border-emerald-400 border-t-transparent rounded-full" />
                    提取中...
                  </>
                ) : (
                  <>📝 提取文字</>
                )}
              </button>
            )}
          </div>

          {/* 文字内容 */}
          <div ref={textRef} className="flex-1 overflow-y-auto px-4 py-4">
            {page?.text_content ? (
              <div className="space-y-1.5 text-sm leading-relaxed text-text">
                {sentences.map((s, i) => (
                  <span
                    key={i}
                    className={`block cursor-pointer rounded px-1 -mx-1 transition-colors ${
                      i === highlightIdx
                        ? "bg-violet-500/20 text-violet-200"
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
              <div className="flex flex-col items-center justify-center h-full text-text-muted gap-3">
                <span className="text-4xl opacity-30">📄</span>
                <p className="text-sm">点击上方"提取文字"按钮</p>
                <p className="text-xs">AI 会识别图片中的文字内容用于朗读</p>
              </div>
            )}
            {error && (
              <p className="mt-3 text-xs text-red-400">{error}</p>
            )}
          </div>

          {/* 翻页 */}
          <div className="shrink-0 flex items-center justify-between gap-3 border-t border-bg-soft px-4 py-2.5">
            <button
              onClick={handlePrev}
              disabled={pageIdx === 0}
              className="rounded-lg bg-bg-soft px-3 py-1.5 text-sm text-text disabled:opacity-30"
            >
              ← 上一页
            </button>
            {speaking && !paused && (
              <button
                onClick={handleAutoNext}
                className="text-xs text-violet-300"
              >
                下一页 ▶
              </button>
            )}
            <button
              onClick={handleNext}
              disabled={pageIdx >= data.pages.length - 1}
              className="rounded-lg bg-bg-soft px-3 py-1.5 text-sm text-text disabled:opacity-30"
            >
              下一页 →
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
