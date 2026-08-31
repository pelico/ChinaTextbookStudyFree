"use client";

/**
 * speechTts.ts — 浏览器原生 Speech Synthesis API 封装
 *
 * 功能：
 *   - 按句子队列播放
 *   - 支持中文/英文语音选择
 *   - 播放/暂停/停止
 *   - 语速控制
 *   - 当前句高亮回调
 */

export interface SpeakOptions {
  lang?: string;
  rate?: number;
  onSentence?: (index: number) => void;
  onEnd?: () => void;
}

let currentUtterance: SpeechSynthesisUtterance | null = null;
let currentSentences: string[] = [];
let currentIndex = 0;
let currentOptions: SpeakOptions = {};
let isPaused = false;

function splitSentences(text: string): string[] {
  // 按中英文标点分句
  const parts = text.split(/(?<=[。！？.!?；;])/g).map(s => s.trim()).filter(Boolean);
  if (parts.length === 0 && text.trim()) return [text.trim()];
  return parts;
}

function getBestVoice(lang: string): SpeechSynthesisVoice | null {
  if (typeof window === "undefined" || !window.speechSynthesis) return null;
  const voices = window.speechSynthesis.getVoices();
  if (voices.length === 0) return null;

  // 优先精确匹配，其次语言前缀匹配
  const prefix = lang.split("-")[0];
  let voice = voices.find(v => v.lang === lang);
  if (!voice) voice = voices.find(v => v.lang.startsWith(prefix));
  return voice || voices[0];
}

function speakNext() {
  if (typeof window === "undefined" || !window.speechSynthesis) return;
  if (currentIndex >= currentSentences.length) {
    currentOptions.onEnd?.();
    return;
  }

  const text = currentSentences[currentIndex];
  currentOptions.onSentence?.(currentIndex);

  const u = new SpeechSynthesisUtterance(text);
  u.lang = currentOptions.lang || "zh-CN";
  u.rate = currentOptions.rate || 1;
  const voice = getBestVoice(u.lang);
  if (voice) u.voice = voice;

  u.onend = () => {
    if (isPaused) return;
    currentIndex++;
    speakNext();
  };
  u.onerror = () => {
    currentIndex++;
    speakNext();
  };

  currentUtterance = u;
  window.speechSynthesis.speak(u);
}

export function speakText(text: string, options: SpeakOptions = {}) {
  stopSpeaking();
  currentSentences = splitSentences(text);
  currentIndex = 0;
  currentOptions = options;
  isPaused = false;
  speakNext();
}

export function pauseSpeaking() {
  if (typeof window === "undefined" || !window.speechSynthesis) return;
  window.speechSynthesis.pause();
  isPaused = true;
}

export function resumeSpeaking() {
  if (typeof window === "undefined" || !window.speechSynthesis) return;
  window.speechSynthesis.resume();
  isPaused = false;
}

export function stopSpeaking() {
  if (typeof window === "undefined" || !window.speechSynthesis) return;
  window.speechSynthesis.cancel();
  currentUtterance = null;
  currentSentences = [];
  currentIndex = 0;
  isPaused = false;
}

export function isSpeaking(): boolean {
  if (typeof window === "undefined" || !window.speechSynthesis) return false;
  return window.speechSynthesis.speaking;
}

export function isPausedState(): boolean {
  return isPaused;
}

export function speakSentenceFrom(index: number) {
  if (index < 0 || index >= currentSentences.length) return;
  stopSpeaking();
  currentIndex = index;
  isPaused = false;
  speakNext();
}

export function getSentences(): string[] {
  return currentSentences;
}

export function getCurrentIndex(): number {
  return currentIndex;
}

export function isSpeechSupported(): boolean {
  return typeof window !== "undefined" && "speechSynthesis" in window;
}
