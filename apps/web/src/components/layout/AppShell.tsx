"use client";

/**
 * AppShell —— 响应式三栏布局壳（左 SideNav / 中央内容 / 右 RightRail）
 *
 * 单树渲染：children 只挂载一次，靠 hidden lg:block 控制两侧栏的显隐，
 * 避免旧版「移动端 + 桌面端各渲染一份 children」带来的音效 / observer /
 * ticker 双跑与重复 <main> 问题。
 *
 * 语义：AppShell 自身不再输出 <main>——由各页面的 children 提供唯一的
 * <main> 地标（现有壳内页面均已自带）。
 */

import type { CSSProperties, ReactNode } from "react";
import { SideNav } from "./SideNav";
import { RightRail } from "./RightRail";

interface AppShellProps {
  children: ReactNode;
  /** 自定义右栏。传 null 显式隐藏；不传则显示默认 RightRail */
  right?: ReactNode | null;
  /** 中央内容栏最大宽度（仅 lg+ 生效），默认 640 */
  centerMaxWidth?: number;
}

export function AppShell({ children, right, centerMaxWidth = 640 }: AppShellProps) {
  const showRight = right !== null;
  return (
    <div
      className="min-h-screen w-full lg:mx-auto lg:grid lg:max-w-[1240px] lg:gap-6 lg:px-6 lg:py-6"
      style={{
        // 移动端 display:block，该属性不生效；lg+ 变 grid 后接管三栏
        gridTemplateColumns: showRight
          ? "260px minmax(0, 1fr) 360px"
          : "260px minmax(0, 1fr)",
      }}
    >
      <aside className="hidden lg:block lg:sticky lg:top-6 lg:self-start lg:h-[calc(100vh-3rem)]">
        <SideNav />
      </aside>

      <div className="min-w-0">
        <div
          className="mx-auto w-full lg:max-w-[var(--center-max)]"
          style={{ "--center-max": `${centerMaxWidth}px` } as CSSProperties}
        >
          {children}
        </div>
      </div>

      {showRight && (
        <aside className="hidden lg:block lg:sticky lg:top-6 lg:self-start lg:h-[calc(100vh-3rem)] overflow-y-auto pb-6">
          {right ?? <RightRail />}
        </aside>
      )}
    </div>
  );
}
