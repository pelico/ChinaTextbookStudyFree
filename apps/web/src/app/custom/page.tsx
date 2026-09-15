"use client";

import { useState, useEffect, useCallback } from "react";
import { navigate } from "@/lib/customApi";
import { AppShell } from "@/components/layout/AppShell";
import { PageHeader } from "@/components/PageHeader";
import { CustomHome } from "./CustomHome";
import { CustomCreate } from "./CustomCreate";
import { CustomBook } from "./CustomBook";
import { CustomLesson } from "./CustomLesson";
import { CustomFolderCreate } from "./CustomFolderCreate";
import { CustomReader } from "./CustomReader";
import { CustomExamHome } from "./CustomExamHome";
import { CustomExamCreate } from "./CustomExamCreate";
import { CustomExamDetail } from "./CustomExamDetail";

/**
 * /custom/* SPA-style 路由分发：所有子页共享一个 <AppShell>，外层左侧栏
 * （logo + StatsBar + GradeSwitcher + 导航项）一直保持显示，子页只渲染在中列。
 * 由于 AppShell 内 children 互斥，遍历 /custom 内部链接（navigate("...")）时
 * 不会触发整页 remount，也不会闪屏跳侧栏。
 */
export default function CustomPage() {
  const [path, setPath] = useState<string>("");

  useEffect(() => {
    setPath(window.location.pathname);
    const onPop = () => setPath(window.location.pathname);
    window.addEventListener("popstate", onPop);
    return () => window.removeEventListener("popstate", onPop);
  }, []);

  const parts = path.replace(/\/+$/, "").split("/").filter(Boolean);

  return (
    <AppShell>
      <main className="min-h-screen bg-bg-soft pb-20 md:pb-8">
        <PageHeader
          backHref="/custom/"
          title="自定义学习"
          subtitle="拍照上传教材 · AI 出题 · 真题库"
        />
        <div className="px-4 py-6 space-y-6 md:px-6">
          {parts.length <= 1 ? (
            <CustomHome />
          ) : parts[1] === "create" ? (
            <CustomCreate />
          ) : parts[1] === "folder-create" ? (
            <CustomFolderCreate />
          ) : parts[1] === "book" && parts.length === 3 ? (
            <CustomBook bookId={parts[2]} />
          ) : parts[1] === "book" && parts.length === 4 && parts[3] === "read" ? (
            <CustomReader bookId={parts[2]} />
          ) : parts[1] === "book" && parts.length === 4 ? (
            <CustomLesson bookId={parts[2]} lessonId={parts[3]} />
          ) : parts[1] === "exams" ? (
            <CustomExamHome />
          ) : parts[1] === "exam" && parts.length === 3 && parts[2] === "create" ? (
            <CustomExamCreate />
          ) : parts[1] === "exam" && parts.length === 3 ? (
            <CustomExamDetail examId={parts[2]} />
          ) : (
            <CustomHome />
          )}
        </div>
      </main>
    </AppShell>
  );
}
