"use client";

/**
 * tts.ts — 播放 build-data 注入的预生成 TTS mp3。
 *
 * 设计：
 *   - 单例 HTMLAudioElement，同一时间只有一段 TTS 在播
 *   - 受全局 muted 状态控制
 *   - 简单 LRU 预加载（避免重复 fetch）
 *
 * Promise 完成语义（tts-playall-resolve-1）：
 *   - 只在 audio `ended` 或 `error` 时 resolve。
 *   - `pause` 事件不 resolve（ios/Safari/某些 Android WebView 在 src 切换、
 *     buffer 不足、网络中断时会发 pause，提前 resolve 会让上游
 *     playAll 误以为"播完了"而触发 grant XP + 连播跳转）。
 *   - 显式打断靠 `pendingResolve()`：stopTTS() / 切换 src / 调用 stopAllTTS()
 *     时都主动调一次，让上游 Promise 干净退出。
 */

import { isMuted } from "./sfx";

let el: HTMLAudioElement | null = null;
let currentSrc: string | null = null;

/** 当前 playTTS() 返回的 Promise 的 resolver；切换 src 时主动调一次清旧句柄 */
let pendingResolve: (() => void) | null = null;
/** 当前 playTTS() 注册到 audio 上的 ended/error 监听器；切换 src 时也要摘掉 */
let pendingListeners: Array<[string, EventListener]> = [];

const preloaded = new Map<string, HTMLAudioElement>();
const PRELOAD_MAX = 16;

function getEl(): HTMLAudioElement | null {
  if (typeof window === "undefined") return null;
  if (!el) {
    el = new Audio();
    el.preload = "auto";
  }
  return el;
}

export function preloadTTS(src: string | undefined | null) {
  if (!src || typeof window === "undefined") return;
  if (preloaded.has(src)) return;
  const a = new Audio();
  a.preload = "auto";
  a.src = src;
  preloaded.set(src, a);
  if (preloaded.size > PRELOAD_MAX) {
    const first = preloaded.keys().next().value as string | undefined;
    if (first) preloaded.delete(first);
  }
}

/** 强制结束当前正在进行的 playTTS 的 await —— 上游 await 干净退出 */
function finishPending() {
  if (!el) {
    pendingResolve = null;
    pendingListeners = [];
    return;
  }
  // 先摘掉旧 listener（避免后续 audio 自然 ended 触到旧 finish）
  for (const [type, fn] of pendingListeners) {
    el.removeEventListener(type, fn);
  }
  pendingListeners = [];
  const r = pendingResolve;
  pendingResolve = null;
  if (r) r();
}

export function stopTTS() {
  finishPending();
  const a = getEl();
  if (!a) return;
  a.pause();
  a.currentTime = 0;
  currentSrc = null;
}

/**
 * 播放并在结束时 resolve（出错立即 resolve；显式 stopTTS 也 resolve）。
 * pause 事件不会触发 resolve，避免上游连播误判"已播完"。
 */
export function playTTS(src: string | undefined | null): Promise<void> {
  if (!src || isMuted()) return Promise.resolve();
  const a = getEl();
  if (!a) return Promise.resolve();

  // 同一段再次点击 → 停止；如果已结束则重新播
  if (currentSrc === src && !a.paused) {
    a.pause();
    a.currentTime = 0;
    currentSrc = null;
    finishPending();
    return Promise.resolve();
  }

  // 切 src 之前先显式结束上一次 playTTS 的等待，
  // 避免 src 切换触发的 pause 事件被忽略导致旧 Promise 永不 resolve（连播不跳转）。
  finishPending();

  a.pause();
  a.src = src;
  a.currentTime = 0;
  currentSrc = src;

  return new Promise<void>(resolve => {
    // 把这次 resolve 放进 pendingResolve，让 stopTTS / 下次 playTTS 能主动打断
    pendingResolve = resolve;
    pendingListeners = [];
    const finish = (kind: "ended" | "error") => () => {
      // 只让本轮 resolve 来解锁；后到的 ended/error 是新一句的，无害
      if (pendingResolve !== resolve) return;
      pendingResolve = null;
      a.removeEventListener("ended", onEnded);
      a.removeEventListener("error", onError);
      pendingListeners = [];
      resolve();
    };
    const onEnded = finish("ended");
    const onError = finish("error");
    a.addEventListener("ended", onEnded);
    a.addEventListener("error", onError);
    pendingListeners.push(["ended", onEnded as EventListener]);
    pendingListeners.push(["error", onError as EventListener]);
    a.play().catch(() => {
      // autoplay policy violation / NotAllowedError / network error：
      // 立刻结束，不阻塞上游（playAll 会 catch 这个走 fallback）。
      if (pendingResolve === resolve) {
        pendingResolve = null;
        a.removeEventListener("ended", onEnded);
        a.removeEventListener("error", onError);
        pendingListeners = [];
        resolve();
      }
    });
  });
}

export function isPlayingTTS(src: string): boolean {
  const a = getEl();
  return !!a && currentSrc === src && !a.paused;
}
