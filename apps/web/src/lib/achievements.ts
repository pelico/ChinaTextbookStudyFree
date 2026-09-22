/**
 * achievements.ts —— Web 端 shim
 *
 * 解锁判定 / 成就定义 全部来自 @cstf/core/achievements（纯函数、跨端共享）。
 * 本文件只保留 Web 平台特定的 seen-tracking（基于 localStorage）。
 * RN 端会有自己的 seen-tracking 实现（AsyncStorage）。
 */

export {
  ALL_ACHIEVEMENTS,
  computeUnlockedAchievementIds,
  diffNewlyUnlocked,
} from "@cstf/core/achievements";
export type {
  Achievement,
  AchievementCategory,
  AchievementProgressSnapshot,
} from "@cstf/core/achievements";

import { computeUnlockedAchievementIds } from "@cstf/core/achievements";
import { useProgressStore } from "@/store/progress";
import { getStorageKey } from "@/lib/kidProfile";

// 🏷️ 已读台账（seen）按学习者隔离，key 形如 csf-achievements-seen-v1-{kidId}。
// 老的全局 key（无后缀）仅迁移到 default 桶一次，避免升级后被当成"从未看过"
// 而把历史成就再弹一遍。
const SEEN_KEY = getStorageKey("csf-achievements-seen-v1");

// 一次性迁移：老全局 key → default 桶（同一单调栈逻辑，防止跨端读到旧 key 残留）
if (typeof window !== "undefined") {
  const legacyKey = "csf-achievements-seen-v1";
  try {
    if (
      SEEN_KEY !== legacyKey &&
      !localStorage.getItem(SEEN_KEY) &&
      localStorage.getItem(legacyKey)
    ) {
      localStorage.setItem(SEEN_KEY, localStorage.getItem(legacyKey) as string);
    }
  } catch {
    /* noop */
  }
}

function readSeen(): Set<string> {
  if (typeof window === "undefined") return new Set();
  try {
    const raw = localStorage.getItem(SEEN_KEY);
    if (!raw) return new Set();
    return new Set(JSON.parse(raw) as string[]);
  } catch {
    return new Set();
  }
}

function writeSeen(set: Set<string>) {
  if (typeof window === "undefined") return;
  try {
    localStorage.setItem(SEEN_KEY, JSON.stringify(Array.from(set)));
  } catch {
    /* noop */
  }
}

/** 该成就是否已在（本学习者的）历史里被看过/弹过 —— 用于重挂载/整页刷新时去重 */
export function isAchievementSeen(id: string): boolean {
  if (typeof window === "undefined") return false;
  return readSeen().has(id);
}

/** 把成就标记为已看过（弹庆祝后立即落盘，刷新不再重播） */
export function markAchievementSeen(id: string): void {
  const seen = readSeen();
  seen.add(id);
  writeSeen(seen);
}

/** 解锁集合 = 永久账本 ∪ 实时计算（已入账本的永不"回锁"） */
function currentUnlockedIds(): string[] {
  const state = useProgressStore.getState();
  return [
    ...new Set([
      ...Object.keys(state.unlockedAchievements),
      ...computeUnlockedAchievementIds(state),
    ]),
  ];
}

/** 当前是否存在尚未被用户查看的已解锁成就 */
export function hasUnseenAchievements(): boolean {
  if (typeof window === "undefined") return false;
  const seen = readSeen();
  return currentUnlockedIds().some(id => !seen.has(id));
}

/** 把当前所有解锁标记为已读（用户进入成就墙时调用） */
export function markAllSeen(): void {
  const seen = readSeen();
  currentUnlockedIds().forEach(id => seen.add(id));
  writeSeen(seen);
}
