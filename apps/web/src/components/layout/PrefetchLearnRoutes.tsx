"use client";

/**
 * PrefetchLearnRoutes —— 提前预取「学习」相关的动态路由 RSC 载荷。
 *
 * 动态路由（/grade/[grade]、/book/[book]）的 RSC 是独立 .txt，切换时才去拉，
 * 首次往往要等 chunk/RSC 回来才渲染，造成整页（含左栏）白屏。
 * 本组件在空闲时用 router.prefetch 把这些目标 RSC 提前拉进缓存，
 * 用户点「学习」切过去时直接命中缓存秒开。
 *
 * 预取范围：
 *   - 6 个年级页（学习入口会在 首页→/grade/{g} 二次跳转）
 *   - 当前教材书页（activeBookId 存在时，学习 tab 直接去 /book/{id}/）
 *   - 根路径（首页 /，若没有当前教材时经它再跳年级页）
 */
import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { useProgressStore } from "@/store/progress";

export function PrefetchLearnRoutes() {
  const router = useRouter();
  const activeBookId = useProgressStore(s => s.activeBookId);

  useEffect(() => {
    // 年级页只有 6 个，全预取（RSC 载荷很小）
    for (let g = 1; g <= 6; g++) {
      try {
        router.prefetch(`/grade/${g}/`);
      } catch {}
    }
    router.prefetch("/");
    if (activeBookId) {
      try {
        router.prefetch(`/book/${activeBookId}/`);
      } catch {}
    }
  }, [router, activeBookId]);

  return null;
}