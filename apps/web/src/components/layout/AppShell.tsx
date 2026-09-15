"use client";

/**
 * AppShell —— 响应式三栏布局壳（左 SideNav + SideRail / 中央内容 / 右 right slot）
 *
 * 断点（web-shell-14 + rail-left-1）：
 *   - < md：单列，底部 BottomNav（BottomNav 自身 md:hidden）
 *   - md (768-1023)：icon-only 88px SideNav + 中央列（max ~640），无侧栏
 *   - lg+：260px SideNav（含 SideRail / 排行榜 + 每日任务）+ 中央列 + 可选 360px right
 *
 * 改动记录：
 *   - 把原来的 RightRail 默认挂载位置从「右栏」改为「左列 SideNav 下方」
 *   - 右栏保持可显式控制，传 right={...} 才出现
 *   - 这是为了腾出中央列的视觉空间（参考 /profile/ 的 right={null} centerMaxWidth=920 布局）
 *
 * 单树渲染：children 只挂载一次，靠 hidden md:block 控制两侧栏的显隐，
 * 避免旧版「移动端 + 桌面端各渲染一份 children」带来的音效 / observer /
 * ticker 双跑与重复 <main> 问题。
 *
 * 语义：AppShell 自身不再输出 <main>——由各页面的 children 提供唯一的
 * <main> 地标（现有壳内页面均已自带）。
 */

import type { CSSProperties, ReactNode } from "react";
import { SideNav } from "./SideNav";
import { SideRail } from "./RightRail";

interface AppShellProps {
  children: ReactNode;
  /** 自定义右栏。传 null 显式隐藏；传 JSX 显式替换默认；不传则默认无右栏 */
  right?: ReactNode | null;
  /** 自定义左栏（SideNav 下方追加区）。不传则显示默认 SideRail（排行榜 + 每日任务） */
  leftSlot?: ReactNode | null;
  /** 中央内容栏最大宽度（仅 md+ 生效），默认 1080。
   *  lg+ 时 grid 给的可用宽度通常 < 1080，因此 centerMaxWidth 是软上限。
   *  真正限制内容宽度的，是各页面在 main/div 上加的 max-w-* 类，
   *  —— 见 rail-left-2：内容页应去除内联 max-w-3xl 让中列跟随 grid 撑开。 */
  centerMaxWidth?: number;
}

export function AppShell({ children, right, leftSlot, centerMaxWidth = 1080 }: AppShellProps) {
  const showRight = right !== null;
  // leftSlot 默认显示 SideRail；null 显式隐藏；JSX 替换
  const showLeftSlot = leftSlot !== null;
  const resolvedLeftSlot = leftSlot === undefined ? <SideRail /> : leftSlot;
  return (
    <div
      className={
        "min-h-screen w-full md:mx-auto md:grid md:max-w-[1240px] md:gap-4 md:px-4 md:py-6 lg:gap-6 lg:px-6 " +
        "md:[grid-template-columns:88px_minmax(0,1fr)] " +
        (showRight
          ? "lg:[grid-template-columns:260px_minmax(0,1fr)_360px]"
          : "lg:[grid-template-columns:260px_minmax(0,1fr)]")
      }
    >
      <aside className="hidden md:flex md:flex-col md:sticky md:top-6 md:self-start md:h-[calc(100vh-3rem)] md:overflow-y-auto md:pb-6">
        {/* 把 SideRail 渲染交给 SideNav 内部，确保它出现在「悠悠学堂」logo 下方、
            导航项上方的固定位置（具体位置由 SideNav.tsx 决定）。 */}
        <SideNav leftSlot={showLeftSlot ? resolvedLeftSlot : null} />
      </aside>

      <div className="min-w-0">
        {/* 中列 wrapper：md 640px / lg+ 由 grid 1fr 自然撑满，受 centerMaxWidth 软限。 */}
        <div
          className="mx-auto w-full md:max-w-[640px] lg:max-w-[var(--center-max)]"
          style={{ "--center-max": `${centerMaxWidth}px` } as CSSProperties}
        >
          {children}
        </div>
      </div>

      {showRight && (
        <aside className="hidden lg:block lg:sticky lg:top-6 lg:self-start lg:h-[calc(100vh-3rem)] overflow-y-auto pb-6">
          {right}
        </aside>
      )}
    </div>
  );
}
