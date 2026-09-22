"use client";

import { useEffect } from "react";

/**
 * 容错路由：/grade/（不带年级数字）不直接展示教材目录，统一跳到 /grade/1/。
 *
 * 背景：静态导出 + nginx 下，/grade/[grade] 只生成 /grade/1/…/grade/6/ 的
 * index.html，/grade/ 目录本身没有 index.html，直接访问会 403 Forbidden。
 * 旧缓存 / 旧构建里的客户端路由偶尔会落在 /grade/，这里生成 /grade/index.html
 * 做一次客户端自动跳转，避免坏体验。
 */
export default function GradeRedirect() {
  useEffect(() => {
    window.location.replace("/grade/1/");
  }, []);

  return <div className="min-h-screen bg-bg" />;
}