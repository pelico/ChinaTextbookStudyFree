"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { useProgressStore } from "@/store/progress";
import { GradePicker } from "@/components/GradePicker";

interface HomeClientProps {
  grades: number[];
  byGrade: Record<number, number>;
  totalBooks: number;
  totalLessons: number;
  totalQuestions: number;
}

/**
 * 首页路由分发（打开即路径）：
 *   - 有当前教材（activeBookId）→ 软跳转到 /book/{id}/（router.replace，无整页白闪）
 *   - 只选过年级 → 软跳转到 /grade/{grade}/
 *   - 都没有（首访 / 刚点了「换年级」）→ 渲染 GradePicker 引导
 *
 * 换年级会把 selectedGrade 清空；此时残留的 activeBookId 已属于旧年级，
 * 在这里顺手清掉（自愈），避免下次打开又跳回旧教材。
 */
export function HomeClient(_props: HomeClientProps) {
  const selectedGrade = useProgressStore(s => s.selectedGrade);
  const activeBookId = useProgressStore(s => s.activeBookId);
  const setActiveBookId = useProgressStore(s => s.setActiveBookId);
  const router = useRouter();
  const [hydrated, setHydrated] = useState(false);

  useEffect(() => setHydrated(true), []);

  useEffect(() => {
    if (!hydrated) return;
    if (selectedGrade == null) {
      // 年级已重置 → 旧教材选择随之失效
      if (activeBookId != null) setActiveBookId(null);
      return;
    }
    if (activeBookId) {
      router.replace(`/book/${activeBookId}/`);
    } else {
      router.replace(`/grade/${selectedGrade}/`);
    }
  }, [hydrated, selectedGrade, activeBookId, setActiveBookId, router]);

  // 跳转前渲染空底色占位，避免闪 GradePicker
  if (!hydrated || selectedGrade != null) {
    return <div className="min-h-screen bg-bg" />;
  }

  return <GradePicker />;
}
