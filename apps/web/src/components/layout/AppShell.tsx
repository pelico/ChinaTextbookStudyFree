"use client";

/**
 * AppShell —— 自适应两栏布局（左 SideNav 含 SideRail / 中央内容）
 *
 * 断点：
 *   - < md：单列，底部 BottomNav（BottomNav 自身 md:hidden）
 *   - md+：两栏布局，左 88px（icon-only）→ lg 260px（含 SideRail / 排行榜 + 每日任务）
 *   - 容器不设 max-w，沿 viewport 100% 宽度铺开，让中央列 1fr 自然撑到桌面宽度
 *
 * 之前是三栏（左 + 中 + 可选右），右侧 360px 占位过宽，被中间列挤压。
 * 现在简化为两栏：左 260px SideNav + 中 1fr 自适应。
 * 如果未来某个页面需要右栏，再显式给那个页面套个 flex 即可。
 *
 * 改动记录：
 *   - rail-left-1：RightRail 从右栏移到 SideNav 内部上方
 *   - rail-left-2：内容页去除内联 max-w-3xl 让中列跟随 grid 撑开
 *   - rail-left-3：中列 wrapper w-full，不再 mx-auto（mx-auto 在没有显式 max-w
 *     时会让 wrapper 居中、左右留白，看起来「右栏没东西占位」）
 *   - two-col-1：去掉外层 max-w-[1240px]，让 grid container 100% 宽度铺开；
 *     之前 max-w 限制了中列 1fr 的可分配空间，auto-fill 在 1240 内列数有限。
 *
 * 单树渲染：children 只挂载一次，靠 hidden md:block 控制左侧栏的显隐。
 *
 * 语义：AppShell 自身不再输出 <main>——由各页面的 children 提供唯一的
 * <main> 地标。
 */

import type { CSSProperties, ReactNode } from "react";
import { SideNav } from "./SideNav";
import { SideRail } from "./RightRail";

interface AppShellProps {
  children: ReactNode;
  /** 中央内容栏最大宽度（仅 md+ 生效），默认 1920。
   *  容器本身不设 max-w，沿 viewport 铺开；centerMaxWidth 是个软上限，
   *  用来防止极宽屏（4K）下文字行过长。 */
  centerMaxWidth?: number;
}

export function AppShell({ children, centerMaxWidth = 1920 }: AppShellProps) {
  const showLeftSlot = true;
  return (
    <div
      className={
        "min-h-screen w-full md:mx-auto md:grid md:gap-4 md:px-4 md:py-6 lg:gap-6 lg:px-6 " +
        "md:[grid-template-columns:88px_minmax(0,1fr)] " +
        "lg:[grid-template-columns:260px_minmax(0,1fr)]"
      }
    >
      <aside className="hidden md:flex md:flex-col md:sticky md:top-6 md:self-start md:h-[calc(100vh-3rem)] md:overflow-y-auto md:pb-6">
        {/* 把 SideRail 渲染交给 SideNav 内部，确保它出现在「悠悠学堂」logo 下方、
            导航项上方的固定位置（具体位置由 SideNav.tsx 决定）。 */}
        <SideNav leftSlot={showLeftSlot ? <SideRail /> : null} />
      </aside>

      <div className="min-w-0 w-full">
        {/* 中列 wrapper：md 640px / lg+ 撑满 grid 1fr，受 centerMaxWidth 软限。
            —— 见 rail-left-3：必须 w-full，否则在内容宽度 < track 时 mx-auto 会
            让 wrapper 居中、左右留白，看起来「右栏没东西占位」。 */}
        <div
          className="w-full md:max-w-[640px] lg:max-w-[var(--center-max)]"
          style={{ "--center-max": `${centerMaxWidth}px` } as CSSProperties}
        >
          {children}
        </div>
      </div>
    </div>
  );
}
