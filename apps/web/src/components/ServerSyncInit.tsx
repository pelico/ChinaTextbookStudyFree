"use client";

import { useEffect } from "react";
import { initServerSync, teardownServerSync } from "@/store/progress";

export function ServerSyncInit() {
  useEffect(() => {
    initServerSync();
    // #1: 卸载时清理定时器与事件监听器，避免 HMR / 路由切换后遗留运行
    return () => teardownServerSync();
  }, []);
  return null;
}
