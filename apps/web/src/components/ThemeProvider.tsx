"use client";

/**
 * ThemeProvider —— 二态深色模式 + 美妆主题的统一应用层。
 *
 * 深色的来源（优先级从高到低）：
 *   1. 装备了暗色美妆主题（theme_midnight / theme_obsidian，isDark）
 *      → 「强制暗色」，用主题自带的色板覆盖同一套 --app-* token
 *   2. 手动偏好 = dark
 *   只挂 .theme-dark 类，night 色板（bg #131F24 / surface #202F36 /
 *   border #37464F）由 globals.css 提供缺省值。不再有「跟随系统」自动档，
 *   默认浅色 —— 避免 app/系统切深色时闪变。
 *
 * 亮色美妆主题只影响 --theme-primary / --theme-accent / --theme-bg 等
 * 强调色；处于深色时保留强调色、页面底色走 night token。
 *
 * .theme-dark 类挂在 <html> 上 —— layout.tsx 的首屏内联脚本会在水合前
 * 先挂好，防止白闪；这里负责水合后的响应式维护。
 *
 * 同时挂载全局 <MotionConfig reducedMotion="user">，让所有 framer-motion
 * 动画尊重系统「减少动态效果」设置。
 */

import { useEffect } from "react";
import { MotionConfig } from "framer-motion";
import { useProgressStore } from "@/store/progress";
import { getCosmeticById, type UiTheme } from "@/lib/cosmetics";
import { useThemeMode, getThemeMode, useThemeVersion } from "@/lib/themeMode";

const NIGHT_BG = "#131F24";

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const themeId = useProgressStore(s => s.equippedTheme);
  const mode = useThemeMode();
  // 每次 setThemeMode 都 +1：无论 useThemeMode 的同步信号是否被 React 消费，
  // 只要用户切了亮/暗，这里就重跑一次副作用把主题真正应用到 <html>。
  const themeTick = useThemeVersion();

  useEffect(() => {
    const item = getCosmeticById(themeId) as UiTheme | undefined;
    if (!item || item.type !== "ui_theme") return;
    const d = item.data;
    const root = document.documentElement;

    // 强调色永远跟随装备的美妆主题
    root.style.setProperty("--theme-primary", d.primary);
    root.style.setProperty("--theme-primary-dark", d.primaryDark);
    root.style.setProperty("--theme-accent", d.accent);
    root.style.setProperty("--theme-bg", d.bg);

    // freeDark：优先 reactive 偏好；额外用 getThemeMode() 兜底 ——
    // 水合首帧 useThemeMode 的 server snapshot 是 "light"，若仅看它，
    // 会把 bootScript 已挂好的 .theme-dark 先摘掉一帧再补上（WebView 下
    // 会画出一闪的亮帧 =「黑一下又立马变亮」）。直接读 localStorage 让
    // 已保存的暗色偏好立即生效，不再摘类。
    const freeDark = mode === "dark" || getThemeMode() === "dark";
    const isDark = !!d.isDark || freeDark;

    if (d.isDark) {
      // 购买的暗色主题：同一套 token，用主题自带色板覆盖 night 缺省值
      root.style.setProperty("--app-bg", d.bg);
      root.style.setProperty("--app-bg-soft", d.bgSoft ?? d.bg);
      root.style.setProperty("--app-bg-softer", d.bgSofter ?? d.cardBg ?? d.bg);
      root.style.setProperty("--app-card", d.cardBg ?? "#202F36");
      root.style.setProperty("--app-border", d.borderSoft ?? "#37464F");
      root.style.setProperty("--app-ink", d.ink ?? "#F1F5F9");
      root.style.setProperty("--app-ink-light", d.inkLight ?? "#CBD5E1");
      root.style.setProperty("--app-ink-softer", d.inkSofter ?? "#94A3B8");
    } else {
      // 免费深色 / 亮色：清掉内联覆盖，让 globals.css 的 night 缺省值生效
      for (const p of [
        "--app-bg",
        "--app-bg-soft",
        "--app-bg-softer",
        "--app-card",
        "--app-border",
        "--app-ink",
        "--app-ink-light",
        "--app-ink-softer",
      ]) {
        root.style.removeProperty(p);
      }
    }

    root.classList.toggle("theme-dark", isDark);
    root.style.colorScheme = isDark ? "dark" : "light";
    // 首屏 bootScript 会在 <html> 上内联深色底色防白闪 —— 这里接管：
    // 深色时保持同步，切回亮色时清掉，避免滚动越界处露出旧底色
    if (isDark) {
      root.style.backgroundColor = d.isDark ? d.bg : NIGHT_BG;
    } else {
      root.style.removeProperty("background-color");
    }
    document.body.dataset.theme = themeId;
    document.body.style.backgroundColor = d.isDark
      ? d.bg
      : freeDark
        ? NIGHT_BG
        : d.bg;
  }, [themeId, mode, themeTick]);

  return <MotionConfig reducedMotion="user">{children}</MotionConfig>;
}
