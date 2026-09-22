"use client";

/**
 * 云端同步状态 — 给顶栏同步图标提供数据源。
 * 纯运行时状态（不持久化）：由 progress.ts 的同步流程写入，
 * StatsBar 里的同步图标消费。
 *
 * 取值：
 *   - "synced"  已是最新（无待同步变更）
 *   - "pending" 有本地变更待上传（离线/失败会回到这个或 offline）
 *   - "syncing" 正在上传/拉取中
 *   - "offline" 断网
 */

import { create } from "zustand";

export type SyncStatus = "pending" | "syncing" | "synced" | "offline";

interface SyncStatusState {
  status: SyncStatus;
  setStatus: (s: SyncStatus) => void;
}

export const useSyncStatus = create<SyncStatusState>(set => ({
  status: "synced",
  setStatus: status => set({ status }),
}));