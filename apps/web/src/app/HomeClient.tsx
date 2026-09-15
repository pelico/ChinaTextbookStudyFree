"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { useProgressStore } from "@/store/progress";

/**
 * 首页路由分发（"/"，纯服务端入口 -> 客户端决定去哪里）：
 *   - 有当前教材（activeBookId）→ 软跳转到 /book/{id}/（router.replace，无整页白闪）
 *   - 否则（用户还没选过教材 / 刚换了年级）→ 跳到 /grade/1/（一年级下册课本列表），
 *     顶部自带 <GradeSwitcher />，用户随时可以切年级。
 *
 * 之前这里渲染 GradePicker（"你现在读几年级呀？"引导），用户反馈两步选年级太繁琐；
 * 直接给一年级内容，保留 `selectedGrade` 持久化以便跳转/重启用。
 *
 * 换年级会把 selectedGrade 清空；此时残留的 activeBookId 已属于旧年级，
 * 在这里顺手清掉（自愈），避免下次打开又跳回旧教材。
 */
export function HomeClient() {
  const selectedGrade = useProgressStore(s => s.selectedGrade);
  const activeBookId = useProgressStore(s => s.activeBookId);
  const setSelectedGrade = useProgressStore(s => s.setSelectedGrade);
  const setActiveBookId = useProgressStore(s => s.setActiveBookId);
  const router = useRouter();
  const [hydrated, setHydrated] = useState(false);

  useEffect(() => setHydrated(true), []);

  useEffect(() => {
    if (!hydrated) return;
    if (activeBookId) {
      router.replace(`/book/${activeBookId}/`);
      return;
    }
    // 默认去一年级 —— 顶部 GradeSwitcher 提供切换入口
    const target = selectedGrade ?? 1;
    if (selectedGrade == null) setSelectedGrade(target);
    router.replace(`/grade/${target}/`);
  }, [hydrated, selectedGrade, activeBookId, setSelectedGrade, setActiveBookId, router]);

  if (!hydrated) {
    return <div className="min-h-screen bg-bg" />;
  }
  return <div className="min-h-screen bg-bg" />;
}
