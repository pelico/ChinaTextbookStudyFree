"use client";

/**
 * LightDarkToggle —— 一键亮 / 暗切换，放在 SideNav logo 旁边。
 *
 * 老的 ThemeModeToggle 三态（跟随系统 / 亮 / 暗）保留在「我的」页外观设置里，
 * 这里只做常用二态快速切换，避免占用顶部空间。
 *
 * 装备了暗色美妆主题时强制暗色 —— 这时按钮 disabled，避免点击后表象变化让用户困惑。
 */

import { useEffect, useState } from "react";
import { useThemeMode, setThemeMode, type ThemeMode } from "@/lib/themeMode";
import { useProgressStore } from "@/store/progress";
import { getCosmeticById, type UiTheme } from "@/lib/cosmetics";
import { Sun, Moon } from "@/components/icons";
import { playSfx } from "@/lib/sfx";
import { haptic } from "@/lib/haptic";
import { cn } from "@/lib/cn";

/** 当前模式是不是「暗」展示口径：system + 系统暗 = 视为暗；light = 亮；dark = 暗 */
function isDarkMode(mode: ThemeMode): boolean {
  if (mode === "dark") return true;
  if (mode === "light") return false;
  // system：跟随 prefers-color-scheme
  if (typeof window === "undefined") return false;
  return window.matchMedia?.("(prefers-color-scheme: dark)").matches ?? false;
}

export function LightDarkToggle() {
  const mode = useThemeMode();
  const themeId = useProgressStore(s => s.equippedTheme);
  const [hydrated, setHydrated] = useState(false);
  useEffect(() => setHydrated(true), []);

  const equipped = getCosmeticById(themeId) as UiTheme | undefined;
  const forcedDark = hydrated && !!(equipped?.type === "ui_theme" && equipped.data.isDark);
  const dark = isDarkMode(mode);

  function toggle() {
    if (forcedDark) return;
    playSfx("tap");
    haptic("light");
    // 当前是暗 → 切到亮；当前是亮/跟随 → 切到暗。
    setThemeMode(dark ? "light" : "dark");
  }

  return (
    <button
      type="button"
      onClick={toggle}
      disabled={forcedDark}
      aria-label={dark ? "切换为亮色" : "切换为暗色"}
      title={forcedDark ? "当前装备了暗色主题，界面保持暗色" : dark ? "切换为亮色" : "切换为暗色"}
      className={cn(
        "inline-flex items-center justify-center w-10 h-10 rounded-full border-2 transition-colors select-none",
        dark
          ? "bg-bg-softer border-bg-softer text-fox hover:bg-bg-soft"
          : "bg-white border-bg-softer text-ink-light hover:text-primary hover:border-primary",
        forcedDark && "opacity-50 cursor-not-allowed",
      )}
    >
      {dark ? <Moon className="w-5 h-5" /> : <Sun className="w-5 h-5" />}
    </button>
  );
}
