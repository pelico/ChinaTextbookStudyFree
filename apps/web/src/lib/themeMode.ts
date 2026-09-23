"use client";

/**
 * themeMode.ts —— 免费深色模式的二态偏好（亮 / 暗），默认为亮。
 *
 * 与美妆主题（equippedTheme）互相独立：
 *   - 购买的暗色美妆主题（isDark）永远「强制暗色」，覆盖这里的偏好；
 *   - 其余情况按这里的二态决定是否挂 .theme-dark（night 色板）。
 *
 * 不再提供「跟随系统」自动档：
 *   - 避免 app（WebView 下 prefers-color-scheme 不稳定）或桌面系统切深色时
 *     页面自动换肤造成 白→深→浅 的闪烁；
 *   - 默认浅色，用户手动切暗后写入 localStorage（THEME_MODE_KEY）持久化。
 *   - 历史遗留的 "system" / 空值一律按浅色处理。
 */

import { useEffect, useState, useSyncExternalStore } from "react";

export type ThemeMode = "light" | "dark";

export const THEME_MODE_KEY = "csf-theme-mode";

const listeners = new Set<() => void>();

function emit() {
  listeners.forEach(l => l());
}

export function getThemeMode(): ThemeMode {
  if (typeof window === "undefined") return "light";
  // 仅当显式存了 "dark" 才是暗；其余（含历史 "system"）一律浅色
  return window.localStorage.getItem(THEME_MODE_KEY) === "dark" ? "dark" : "light";
}

/**
 * 同步把免费二态的亮/暗应用到 <html>（.theme-dark + colorScheme）。
 *
 * 不依赖 React effect 调度：`setThemeMode` 写入 localStorage 后立即调用本函数，
 * 保证「切一下立即生效」，彻底消除“点了要刷新才生效”。
 * 与 ThemeProvider 的 effect 幂等（都只 toggle 这个类 + colorScheme），重跑无害。
 */
function applyFreeDarkDom(mode: ThemeMode) {
  if (typeof window === "undefined") return;
  const root = document.documentElement;
  root.classList.toggle("theme-dark", mode === "dark");
  root.style.colorScheme = mode === "dark" ? "dark" : "light";
}

export function setThemeMode(mode: ThemeMode) {
  if (typeof window === "undefined") return;
  if (mode === "dark") window.localStorage.setItem(THEME_MODE_KEY, "dark");
  else window.localStorage.removeItem(THEME_MODE_KEY);
  // 同步即时生效，不等 React
  applyFreeDarkDom(mode);
  emit();
}

function subscribe(cb: () => void): () => void {
  listeners.add(cb);
  // 其他标签页改了偏好也同步
  const onStorage = (e: StorageEvent) => {
    if (e.key === THEME_MODE_KEY) cb();
  };
  window.addEventListener("storage", onStorage);
  return () => {
    listeners.delete(cb);
    window.removeEventListener("storage", onStorage);
  };
}

/** 响应式读取当前亮/暗偏好 */
export function useThemeMode(): ThemeMode {
  return useSyncExternalStore(subscribe, getThemeMode, () => "light" as ThemeMode);
}

/**
 * 主题版本号——每次 setThemeMode 都 +1。
 * 供 ThemeProvider 当作 effect 依赖，保证「切到暗/亮」即使 useSyncExternalStore
 * 的信号没被 React 如期消费，也一定能触发一次副作用把 .theme-dark 重新应用上，
 * 避免用户反馈的「切换后要刷新才生效」。
 */
export function useThemeVersion(): number {
  const [v, setV] = useState(0);
  useEffect(() => subscribe(() => setV(x => x + 1)), []);
  return v;
}

// 稳定引用，供 ThemeProvider 等显式订阅时复用
export { subscribe as subscribeThemeMode };