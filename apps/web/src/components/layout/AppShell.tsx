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
  /** 中央内容栏最大宽度（仅 md+ 生效），默认 640 */
  centerMaxWidth?: number;
}

export function AppShell({ children, right, leftSlot, centerMaxWidth = 640 }: AppShellProps) {
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
      <aside className="hidden md:block md:sticky md:top-6 md:self-start md:h-[calc(100vh-3rem)] md:overflow-y-auto md:pb-6">
        <SideNav />
        {showLeftSlot && (
          <div className="mt-6">{resolvedLeftSlot}</div>
        )}
      </aside>

      <div className="min-w-0">
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
