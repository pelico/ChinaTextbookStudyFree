"use client";

/**
 * SyncStatusIcon — 顶栏云端同步状态小图标。
 *
 * 与红心/连胜/宝石同排展示，直观告诉用户数据是否最新：
 *   - ✓ 已同步（绿）：本地与服务端一致
 *   - ⟳ 同步中（蓝，旋转）：正在上传/拉取
 *   - … 待同步（琥珀）：有本地变更还没传上去
 *   - ✗ 未连接（灰/红）：断网，稍后自动重试
 */

import { memo } from "react";
import { motion } from "framer-motion";
import { cn } from "@/lib/cn";
import { useSyncStatus, type SyncStatus } from "@/store/syncStatus";

const META: Record<SyncStatus, { label: string; chip: string; icon: string }> = {
  synced: {
    label: "已同步",
    chip: "border-primary/40 text-primary bg-primary/10",
    icon: "text-primary",
  },
  syncing: {
    label: "同步中",
    chip: "border-secondary/40 text-secondary bg-secondary/10",
    icon: "text-secondary",
  },
  pending: {
    label: "待同步",
    chip: "border-warning/50 text-warning bg-warning/10",
    icon: "text-warning",
  },
  offline: {
    label: "未连接",
    chip: "border-danger/40 text-danger bg-danger/10",
    icon: "text-danger/80",
  },
};

export const SyncStatusIcon = memo(function SyncStatusIcon() {
  const status = useSyncStatus(s => s.status);
  const meta = META[status];

  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.8 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={{ delay: 0.15 }}
      title={`云端数据：${meta.label}`}
      aria-label={`云端数据：${meta.label}`}
      className={cn(
        "h-8 w-8 inline-flex items-center justify-center rounded-full border-2 select-none",
        meta.chip,
        status === "syncing" && "cursor-default",
      )}
    >
      {status === "synced" && <CloudCheck className={cn("w-[18px] h-[18px]", meta.icon)} />}
      {status === "syncing" && <Spinner className="w-[18px] h-[18px]" />}
      {status === "pending" && <CloudPending className={cn("w-[18px] h-[18px]", meta.icon)} />}
      {status === "offline" && <CloudOffline className={cn("w-[18px] h-[18px]", meta.icon)} />}
    </motion.div>
  );
});

// ---- 图标（统一 24×24 line，参考 icons.tsx 风格） ----

/** 已同步：云 + 对勾 */
function CloudCheck({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 24 24"
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.75}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      aria-hidden
    >
      <path d="M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z" />
      <path d="M8.5 13.5l2.2 2.2 4.3-4.4" />
    </svg>
  );
}

/** 待同步：云 + 圆点 */
function CloudPending({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 24 24"
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.75}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      aria-hidden
    >
      <path d="M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z" />
      <circle cx="12" cy="13" r="1.1" fill="currentColor" stroke="none" />
    </svg>
  );
}

/** 未连接：云 + 斜杠 + 断口 */
function CloudOffline({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 24 24"
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.75}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      aria-hidden
    >
      <path d="M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 .08 9H20.5h.76" />
      <path d="M5 5l14 14" />
    </svg>
  );
}

/** 同步中：旋转的刷新箭头 */
function Spinner({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 24 24"
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.9}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={cn("animate-spin", className)}
      aria-hidden
    >
      <path d="M21 12a9 9 0 1 1-2.64-6.36" />
      <path d="M21 3v6h-6" />
    </svg>
  );
}