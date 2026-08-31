"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { motion } from "framer-motion";
import { cn } from "@/lib/cn";
import { MathText } from "@/components/MathText";
import { TTSButton } from "@/components/TTSButton";
import { playSfx } from "@/lib/sfx";
import { haptic } from "@/lib/haptic";
import { playTTS } from "@/lib/tts";
import { speakText, stopSpeaking } from "@/lib/speechTts";
import { useAutoNarrate } from "@/lib/useAutoNarrate";
import { shouldIgnoreKey } from "./keyboard";
import type { QuestionRendererProps } from "./QuestionRenderer";

interface Ripple {
  id: number;
  x: number;
  y: number;
}

function normalizeOpt(s: string): string {
  return s.trim().toLowerCase().replace(/\s+/g, "");
}

/** Fisher-Yates 随机打乱 */
function shuffle<T>(arr: T[]): T[] {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

export function ChoiceQuestion({
  question,
  answer,
  phase,
  isCorrect,
  onChange,
  locked = false,
  speakLang,
}: QuestionRendererProps) {
  const rawCorrect = question.answer.trim();
  // 先找出正确选项在原始数组中的索引
  let correctIdx = 0;
  if (/^[A-D]$/.test(rawCorrect.toUpperCase().charAt(0))) {
    correctIdx = rawCorrect.toUpperCase().charCodeAt(0) - 65;
  } else if (question.options?.length) {
    const cn = normalizeOpt(rawCorrect);
    const idx = question.options.findIndex(o => {
      const stripped = o.replace(/^[A-D][.、]\s*/, "");
      return normalizeOpt(o) === cn || normalizeOpt(stripped) === cn;
    });
    if (idx >= 0) correctIdx = idx;
  }

  // 每次进入答题阶段时随机打乱选项顺序（检查阶段保持同一顺序，避免跳变）
  const [shuffleSeed, setShuffleSeed] = useState(0);
  useEffect(() => {
    if (phase === "answering") {
      setShuffleSeed(s => s + 1); // 每次进入答题阶段重新打乱
    }
  }, [phase, question.id]);

  const { shuffledOptions, shuffledAudioOptions, correctLetter, shuffledIndices } = useMemo(() => {
    const options = question.options ?? [];
    const audioOptions = question.audio?.options ?? [];
    const indices = options.map((_, i) => i);
    const shuffledIndices = shuffle(indices);
    const shuffledOptions = shuffledIndices.map(i => options[i]);
    const shuffledAudioOptions = audioOptions.length
      ? shuffledIndices.map(i => audioOptions[i] ?? null)
      : [];
    const newCorrectIdx = shuffledIndices.indexOf(correctIdx);
    const correctLetter = String.fromCharCode(65 + newCorrectIdx);
    return { shuffledOptions, shuffledAudioOptions, correctLetter, shuffledIndices };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [question.id, shuffleSeed]);

  // 把传入的 answer（原始字母）转换成打乱后的显示字母
  const displayAnswer = useMemo(() => {
    if (!answer) return "";
    const ansLetter = answer.trim().toUpperCase().charAt(0);
    if (!/^[A-D]$/.test(ansLetter)) return answer;
    const origIdx = ansLetter.charCodeAt(0) - 65;
    const displayIdx = shuffledIndices.indexOf(origIdx);
    if (displayIdx < 0) return answer;
    return String.fromCharCode(65 + displayIdx);
  }, [answer, shuffledIndices]);

  const [ripples, setRipples] = useState<Record<string, Ripple[]>>({});
  const idRef = useRef(0);

  // 自动朗读题干（只在进入该题时一次；点选项立即打断）
  const cancelNarrate = useAutoNarrate([question.audio?.question], question.id);

  /** 选中某个选项（点击 / 键盘共用）：朗读 + 音效 + 触感 + 写回 answer */
  function selectLetter(letter: string) {
    if (locked || phase === "checked") return;
    cancelNarrate();
    // 选中选项时自动朗读该选项
    const idx = letter.charCodeAt(0) - 65;
    const optAudio = shuffledAudioOptions[idx];
    if (speakLang) {
      stopSpeaking();
      const optText = shuffledOptions[idx]?.replace(/^[A-D][.、]\s*/, "").replace(/_{2,}/g, " ") || "";
      if (optText) {
        speakText(optText, { lang: speakLang, rate: 0.9 });
      }
    } else if (optAudio) {
      void playTTS(optAudio);
    }
    playSfx("tap");
    haptic("light");
    // 转换回原始选项的字母，保证上层判分逻辑正确
    const origIdx = shuffledIndices[idx];
    const origLetter = String.fromCharCode(65 + origIdx);
    onChange(origLetter);
  }

  function handleTap(letter: string, e: React.MouseEvent<HTMLButtonElement>) {
    if (locked || phase === "checked") return;
    const rect = (e.currentTarget as HTMLElement).getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;
    const id = ++idRef.current;
    setRipples(prev => ({ ...prev, [letter]: [...(prev[letter] ?? []), { id, x, y }] }));
    setTimeout(() => {
      setRipples(prev => ({
        ...prev,
        [letter]: (prev[letter] ?? []).filter(r => r.id !== id),
      }));
    }, 600);
    selectLetter(letter);
  }

  // 键盘快捷键（web-lesson-3）：数字 1-4 选选项
  useEffect(() => {
    if (locked || phase !== "answering") return; // 遮罩打开时不接管键盘（webrunner-5）
    const onKeyDown = (e: KeyboardEvent) => {
      if (shouldIgnoreKey(e)) return;
      const n = Number(e.key);
      if (!Number.isInteger(n) || n < 1 || n > Math.min(4, question.options.length)) return;
      e.preventDefault();
      selectLetter(String.fromCharCode(64 + n));
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [phase, question.id, locked]);

  return (
    <div className="w-full">
      <div className="flex items-start gap-3 mb-6">
        <div className="text-2xl font-bold text-ink leading-relaxed flex-1">
          <MathText text={question.question} />
        </div>
        <TTSButton src={question.audio?.question} className="mt-1" label="朗读题目" />
      </div>

      <div className="space-y-3">
        {shuffledOptions.map((opt, idx) => {
          const letter = String.fromCharCode(65 + idx); // A B C D
          const display = /^[A-D][.、]/.test(opt) ? opt.replace(/^[A-D][.、]\s*/, "") : opt;
          const selected = displayAnswer === letter;
          const isThisCorrect = letter === correctLetter;

          let cls = "option-card";
          if (phase === "checked") {
            if (isThisCorrect) cls = "option-card option-card-correct";
            else if (selected && !isCorrect) cls = "option-card option-card-wrong";
          } else if (selected) {
            cls = "option-card option-card-selected";
          }

          // 答错时在正确选项上播放脉冲高亮，引导用户注意
          const shouldPulse = phase === "checked" && !isCorrect && isThisCorrect;

          const optionAudio = shuffledAudioOptions[idx] ?? null;
          return (
            <div key={idx} className="flex items-stretch gap-2">
              <motion.button
                type="button"
                disabled={phase === "checked"}
                onClick={e => handleTap(letter, e)}
                className={cn("flex-1 text-left flex items-center gap-3 relative", cls)}
                whileTap={phase === "answering" ? { scale: 0.98 } : undefined}
                animate={
                  shouldPulse
                    ? {
                        boxShadow: [
                          "0 2px 0 0 #58a700, 0 0 0 0 rgba(88,204,2,0.6)",
                          "0 2px 0 0 #58a700, 0 0 0 12px rgba(88,204,2,0)",
                          "0 2px 0 0 #58a700, 0 0 0 0 rgba(88,204,2,0.6)",
                        ],
                      }
                    : undefined
                }
                transition={shouldPulse ? { duration: 1.3, repeat: Infinity } : undefined}
              >
                <span className="flex-1">
                  <MathText text={display} />
                </span>
                {/* Duolingo 风格：右下角数字角标（1/2/3/4）
                    仅在有物理键盘的桌面端（pointer:fine）显示 —— 触屏上是噪音 */}
                <motion.span
                  animate={
                    selected
                      ? { scale: [1, 1.18, 1], borderColor: "#1CB0F6", color: "#1CB0F6" }
                      : { scale: 1 }
                  }
                  transition={{ duration: 0.25 }}
                  className="ml-3 w-7 h-7 rounded-md border-2 border-bg-softer hidden [@media(pointer:fine)]:flex items-center justify-center font-extrabold text-ink-softer text-xs tabular-nums shrink-0"
                >
                  {idx + 1}
                </motion.span>

                {/* Ripple */}
                {(ripples[letter] ?? []).map(r => (
                  <span
                    key={r.id}
                    className="ripple-dot text-secondary"
                    style={{ left: r.x - 8, top: r.y - 8, width: 16, height: 16 }}
                  />
                ))}
              </motion.button>
              {optionAudio && (
                <div className="flex items-center">
                  <TTSButton
                    src={optionAudio}
                    size="sm"
                    label={`朗读选项 ${letter}`}
                  />
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
