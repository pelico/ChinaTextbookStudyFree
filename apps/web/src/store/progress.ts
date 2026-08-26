"use client";

import { create } from "zustand";
import { persist, createJSONStorage } from "zustand/middleware";
import type { Question, LessonResult } from "@/types";
import { DEFAULT_EQUIPPED, getCosmeticById, getStarterCosmetics } from "@/lib/cosmetics";
import {
  starsFromAccuracy,
  lessonGemDrip,
  isWeekendXpActive,
  dailyRewardForStreak,
  MAX_HEARTS,
  HEART_REGEN_SECONDS,
  HEART_REFILL_COST,
  FREEZE_COST,
  MAX_FREEZES,
  INITIAL_FREEZES,
  STREAK_MAKEUP_COST,
  STREAK_MILESTONE_REWARDS,
  DAILY_GOAL_OPTIONS,
  DEFAULT_DAILY_GOAL,
  DAILY_GOAL_BONUS,
  FIRST_PERFECT_XP_BONUS,
} from "@cstf/core/economy";
import {
  ALL_ACHIEVEMENTS,
  computeUnlockedAchievementIds,
} from "@cstf/core/achievements";

/**
 * 错题条目，含 SRS（间隔重复）字段。
 * box / correctCount / lastReviewedAt / nextReviewDate 由 lib/srs.ts 维护。
 */
interface MistakeEntry {
  lessonId: string;
  lessonTitle?: string;
  question: Question;
  addedAt: string;
  /** SRS box（1=新错题/今天复习，2=明天，3=毕业级 7 天） */
  box?: 1 | 2 | 3;
  /** 累计答对次数 */
  correctCount?: number;
  /** 上次复习时间（ISO） */
  lastReviewedAt?: string;
  /** 下次复习日期（YYYY-MM-DD），<= today 即可复习 */
  nextReviewDate?: string;
}

/**
 * 未完成的课程会话。
 * 当用户关闭浏览器 / 切走 / 刷新时，这个对象被持久化，
 * 下次进入同一课程可以无缝恢复到上次答到的题目。
 */
export interface ActiveLessonSession {
  lessonId: string;
  index: number;
  correctCount: number;
  mistakeCount: number;
  combo: number;
  startedAt: number; // ms timestamp
}

interface ProgressState {
  // 核心进度
  xp: number;
  streak: number;
  lastActiveDate: string; // YYYY-MM-DD
  completedLessons: Record<string, LessonResult>;
  mistakesBank: MistakeEntry[];

  // 偏好
  muted: boolean;
  /** 自动朗读题干/讲解/知识卡（面向低龄）。默认 on。 */
  autoNarrate: boolean;

  // 心数系统（持久化，跨会话恢复）
  hearts: number;
  nextHeartAt: number | null; // ms timestamp

  // 每日目标
  dailyGoal: number;
  todayXp: number;
  lastXpDate: string;

  // 连胜护盾
  streakFreezes: number;

  // 未完成课程会话
  activeLesson: ActiveLessonSession | null;

  // 💎 宝石货币 / 宝箱 / 首次完美通关记录
  gems: number;
  lifetimeGems: number;
  claimedChests: Record<string, true>;
  perfectedLessons: Record<string, true>;

  // 🎨 美妆系统 v4
  /** 已解锁的 cosmetic id 集合 */
  ownedCosmetics: Record<string, true>;
  /** 当前装备的吉祥物皮肤 id */
  equippedMascotSkin: string;
  /** 当前装备的 UI 主题 id */
  equippedTheme: string;
  /** 当前装备的课程背景 id */
  equippedBackdrop: string;
  /** 已发放过的"连胜里程碑"礼物（防止重复发） */
  claimedStreakRewards: Record<number, true>;

  // ⏱️ 时间关怀（家长可选开启） v4
  /** 每日累计学习时间（毫秒，按 lastXpDate 重置） */
  todayTimeMs: number;
  /** 单日学习时间上限（毫秒），0 表示无限制 */
  dailyTimeLimitMs: number;
  /** 单次课程时长上限（毫秒），0 表示无限制 */
  sessionTimeLimitMs: number;

  // 📅 v5：每日 XP 历史 + 每日登陆奖励
  /** 每日 XP 历史 { "YYYY-MM-DD": xp }，最多保留近 60 天 */
  xpHistory: Record<string, number>;
  /** 每日完成课程数历史 { "YYYY-MM-DD": count } */
  lessonHistory: Record<string, number>;
  /** 上次领取每日登陆奖励的日期 */
  lastDailyRewardDate: string;

  // 🎒 v6：用户选择的年级（首次进入时引导选择，决定 home 显示哪一年级的教材）
  selectedGrade: number | null;

  // 📖 v7：阅读完成记录（课文听读/跟读、故事阅读），id → 完成时间 ISO。
  // 与课程记录彻底分离：阅读只发 XP、不发宝石、不算课时（对齐 iOS completeReading）
  completedReadings: Record<string, string>;

  // 🏆 v8：成就永久解锁账本（只进不出，防连胜回落"回锁"；奖励只发一次）
  unlockedAchievements: Record<string, true>;
  /** 最近一次发放但尚未庆祝的连胜里程碑（DailyRewardWatcher 消费后清空） */
  pendingStreakMilestone: { streak: number; gems: number } | null;

  // actions
  setSelectedGrade: (grade: number | null) => void;
  recordLessonComplete: (lessonId: string, lessonTitle: string, accuracy: number, xpGained: number) => void;
  /** 完成一篇阅读（课文听读/跟读/故事）：幂等，首次才发 XP，不发通关宝石、不写课程记录 */
  completeReading: (id: string, xp: number) => void;
  addMistake: (lessonId: string, lessonTitle: string, question: Question) => void;
  removeMistake: (lessonId: string, questionId: number) => void;
  clearMistakesForLesson: (lessonId: string) => void;
  bumpStreakIfNeeded: () => void;
  toggleMute: () => void;
  toggleAutoNarrate: () => void;

  loseHeart: () => void;
  refreshHearts: () => void;
  refillHeartsFull: () => void; // 调试/管理用
  /** 花 350 宝石立即补满红心（先刷新自然回复；已满不扣费返回 false） */
  buyHeartRefill: () => boolean;
  /** 花 200 宝石购买一枚连胜护盾（持有上限 2，满则返回 false） */
  buyStreakFreeze: () => boolean;
  setDailyGoal: (goal: number) => void;

  /** 更新/写入当前进行中的课程会话 */
  upsertLessonSession: (session: ActiveLessonSession) => void;
  /** 清除进行中的会话（通关/退出/失败时调用） */
  clearLessonSession: () => void;

  // 💎 宝石 / 宝箱 / 首次完美
  addGems: (n: number) => void;
  /** 花费宝石，成功返回 true，不够返回 false */
  spendGems: (n: number) => boolean;
  /** 标记某课为已首次完美通关（幂等），返回 true 表示是首次 */
  markPerfected: (lessonId: string) => boolean;
  /** 领取宝箱（幂等），返回 true 表示是首次领取 */
  claimChest: (chestId: string) => boolean;

  // 🎨 美妆系统 actions
  /** 拥有 cosmetic（不扣 gems，比如初始赠送 / 任务奖励） */
  unlockCosmetic: (id: string) => void;
  /** 购买 cosmetic：扣 gems → 加入 owned → 自动装备。失败返回 false（gems 不够 / 已拥有 / 道具不存在） */
  purchaseCosmetic: (id: string) => { ok: boolean; reason?: string };
  /** 切换装备（必须已拥有） */
  equipCosmetic: (id: string) => boolean;

  // ⏱️ 时间关怀 actions
  setDailyTimeLimit: (ms: number) => void;
  setSessionTimeLimit: (ms: number) => void;
  /** 课程过程中按秒累加学习时间 */
  addLearningTimeMs: (ms: number) => void;

  // 🔁 连胜补卡：花 50 gems 找回昨天的 streak（不让小朋友因为漏了一天就清零）
  makeUpYesterdayStreak: () => boolean;

  /**
   * 领取今日登陆奖励。数额按「有效连胜」折算（断签未救回按 0 档）。
   * 返回 { gems, effectiveStreak }；已领过返回 gems=0。
   */
  claimDailyReward: () => { gems: number; effectiveStreak: number };

  /** 按成就账本发放一枚成就的解锁奖励（幂等），返回发放的宝石数；已在账本返回 0 */
  claimAchievement: (id: string) => number;
  /** 里程碑庆祝已展示，清除 pending 标记 */
  clearPendingStreakMilestone: () => void;

  // 📚 SRS：复习答题后的更新
  reviewMistake: (lessonId: string, questionId: number, isCorrect: boolean) => void;
}

/** 每多少课出现一个宝箱节点（真值在 @cstf/core/chestLogic 中，这里 re-export 保持向后兼容） */
export { CHEST_EVERY_N_LESSONS } from "@cstf/core/chestLogic";

// ============================================================
// 常量 —— 全部来自 @cstf/core/economy（经济单一事实源），这里只 re-export
// ============================================================

export {
  MAX_HEARTS,
  MAX_FREEZES,
  FREEZE_COST,
  HEART_REFILL_COST,
  STREAK_MILESTONE_REWARDS,
  STREAK_MAKEUP_COST,
  FIRST_PERFECT_XP_BONUS,
  DAILY_GOAL_OPTIONS,
  DEFAULT_DAILY_GOAL,
  dailyRewardForStreak,
  isWeekendXpActive as isWeekendBonusActive,
};

/** 一颗红心的回复时长（ms），由 core HEART_REGEN_SECONDS 折算 */
export const HEART_RECHARGE_MS = HEART_REGEN_SECONDS * 1000;

// ============================================================
// 工具函数
// ============================================================

function todayStr(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

function daysBetween(a: string, b: string): number {
  if (!a || !b) return Infinity;
  const da = new Date(a);
  const db = new Date(b);
  return Math.round((db.getTime() - da.getTime()) / (1000 * 60 * 60 * 24));
}

/** 当前是否为周一（用于连胜护盾补给） */
function isMonday(): boolean {
  return new Date().getDay() === 1;
}

/** 保留最近 60 天的历史，防止 localStorage 持续膨胀 */
function pruneHistory<T>(history: Record<string, T>): Record<string, T> {
  const keys = Object.keys(history).sort();
  if (keys.length <= 60) return history;
  const kept = keys.slice(-60);
  const out: Record<string, T> = {};
  for (const k of kept) out[k] = history[k];
  return out;
}

/**
 * 一次 XP 入账的通用记账：xp / todayXp / xpHistory 累加 + 每日目标首次达成的 +20 gems 判定。
 * recordLessonComplete 与 completeReading 共用，避免两份手抄的记账逻辑漂移。
 */
function applyXpGain(
  state: ProgressState,
  xpGained: number,
  today: string,
): {
  xp: number;
  todayXp: number;
  xpHistory: Record<string, number>;
  /** 首次跨过 dailyGoal 阈值的一次性奖励（未达成为 0） */
  goalBonusGems: number;
} {
  const isSameDay = state.lastXpDate === today;
  const prevTodayXp = isSameDay ? state.todayXp : 0;
  const newTodayXp = prevTodayXp + xpGained;
  const newXpHistory = pruneHistory({
    ...state.xpHistory,
    [today]: (state.xpHistory[today] ?? 0) + xpGained,
  });
  let goalBonusGems = 0;
  if (
    prevTodayXp < state.dailyGoal &&
    newTodayXp >= state.dailyGoal &&
    state.dailyGoal > 0
  ) {
    goalBonusGems = DAILY_GOAL_BONUS;
  }
  return {
    xp: state.xp + xpGained,
    todayXp: newTodayXp,
    xpHistory: newXpHistory,
    goalBonusGems,
  };
}

/**
 * 有效连胜（展示/结算口径）：
 * gap ≤ 1 或漏掉的天数能被护盾兜住 → 连胜仍有效；否则视为 0（已断签）。
 */
function effectiveStreakOf(
  streak: number,
  lastActiveDate: string,
  streakFreezes: number,
): number {
  if (streak <= 0 || !lastActiveDate) return 0;
  const gap = daysBetween(lastActiveDate, todayStr());
  const alive = gap <= 1 || gap - 1 <= streakFreezes;
  return alive ? streak : 0;
}

// ============================================================
// Store
// ============================================================

export const useProgressStore = create<ProgressState>()(
  persist(
    (set, get) => ({
      xp: 0,
      streak: 0,
      lastActiveDate: "",
      completedLessons: {},
      mistakesBank: [],
      muted: false,
      autoNarrate: true,

      hearts: MAX_HEARTS,
      nextHeartAt: null,

      dailyGoal: DEFAULT_DAILY_GOAL,
      todayXp: 0,
      lastXpDate: "",

      streakFreezes: INITIAL_FREEZES,

      activeLesson: null,

      gems: 0,
      lifetimeGems: 0,
      claimedChests: {},
      perfectedLessons: {},

      // 美妆系统初值（首次启动 = 仅持有 starter 道具）
      ownedCosmetics: Object.fromEntries(
        getStarterCosmetics().map(c => [c.id, true as const]),
      ),
      equippedMascotSkin: DEFAULT_EQUIPPED.mascotSkin,
      equippedTheme: DEFAULT_EQUIPPED.uiTheme,
      equippedBackdrop: DEFAULT_EQUIPPED.lessonBackdrop,
      claimedStreakRewards: {},

      // 时间关怀（默认全部关闭，家长在 profile 里手动开）
      todayTimeMs: 0,
      dailyTimeLimitMs: 0,
      sessionTimeLimitMs: 0,

      // v5
      xpHistory: {},
      lessonHistory: {},
      lastDailyRewardDate: "",

      // v6
      selectedGrade: null,
      setSelectedGrade: grade => set({ selectedGrade: grade }),

      // v7
      completedReadings: {},

      // v8
      unlockedAchievements: {},
      pendingStreakMilestone: null,

      recordLessonComplete: (lessonId, lessonTitle, accuracy, xpGained) => {
        // ⚠️ XP 公式（含周末 ×2）由调用方经 @cstf/core xpForLesson 算好传入，
        //    这里不再二次翻倍 —— 保证「结算展示值 == 入账值」。
        const stars = starsFromAccuracy(accuracy);
        const today = todayStr();
        const isFirstPerfect = stars === 3 && !get().perfectedLessons[lessonId];

        set(state => {
          // XP / todayXp / xpHistory 记账 + 每日目标首次达成判定
          const xpAccount = applyXpGain(state, xpGained, today);
          const newLessonHistory = pruneHistory({
            ...state.lessonHistory,
            [today]: (state.lessonHistory[today] ?? 0) + 1,
          });
          // 💎 每课宝石 drip —— 单一事实源 @cstf/core lessonGemDrip
          //（含每日目标 +20，不再叠加 goalBonusGems）
          const totalGems = lessonGemDrip({
            stars,
            isFirstPerfect,
            crossedDailyGoal: xpAccount.goalBonusGems > 0,
          });

          // === 只保留最好成绩：重玩得低星不回退（对齐 iOS ProgressStore）===
          // 仅当新星级 >= 旧星级时才覆盖；accuracy 取更优，completedAt 用最新
          const prior = state.completedLessons[lessonId];
          const result: LessonResult =
            prior && stars < prior.stars
              ? prior
              : {
                  lessonId,
                  stars,
                  accuracy: Math.max(accuracy, prior?.accuracy ?? 0),
                  completedAt: new Date().toISOString(),
                };

          return {
            xp: xpAccount.xp,
            completedLessons: { ...state.completedLessons, [lessonId]: result },
            todayXp: xpAccount.todayXp,
            lastXpDate: today,
            gems: state.gems + totalGems,
            lifetimeGems: state.lifetimeGems + totalGems,
            xpHistory: xpAccount.xpHistory,
            lessonHistory: newLessonHistory,
          };
        });

        if (isFirstPerfect) {
          get().markPerfected(lessonId);
        }

        get().bumpStreakIfNeeded();
        // 通关后：如当前课程的错题都已掌握（用户通过），自动移除该课的错题
        // 保守起见：准确率 100% 才清理，否则保留待复习
        if (accuracy >= 0.999) {
          get().clearMistakesForLesson(lessonId);
        }
        // 记录 lessonTitle 到最近结果（未使用但便于未来）
        void lessonTitle;
      },

      // 📖 阅读完成（课文听读/跟读、故事）——对齐 iOS completeReading：
      // 纯 XP，不发通关宝石、不写 completedLessons/lessonHistory，重复完成不再奖励
      completeReading: (id, xp) => {
        if (get().completedReadings[id]) return; // 已完成过，幂等
        const today = todayStr();
        set(state => {
          const xpAccount = applyXpGain(state, xp, today);
          return {
            xp: xpAccount.xp,
            todayXp: xpAccount.todayXp,
            lastXpDate: today,
            xpHistory: xpAccount.xpHistory,
            gems: state.gems + xpAccount.goalBonusGems,
            lifetimeGems: state.lifetimeGems + xpAccount.goalBonusGems,
            completedReadings: {
              ...state.completedReadings,
              [id]: new Date().toISOString(),
            },
          };
        });
        get().bumpStreakIfNeeded();
      },

      addMistake: (lessonId, lessonTitle, question) => {
        const today = todayStr();
        set(state => ({
          mistakesBank: [
            ...state.mistakesBank.filter(
              m => !(m.lessonId === lessonId && m.question.id === question.id),
            ),
            {
              lessonId,
              lessonTitle,
              question,
              addedAt: new Date().toISOString(),
              // SRS 初值：box 1，今天就该复习
              box: 1,
              correctCount: 0,
              nextReviewDate: today,
            },
          ],
        }));
      },

      removeMistake: (lessonId, questionId) => {
        set(state => ({
          mistakesBank: state.mistakesBank.filter(
            m => !(m.lessonId === lessonId && m.question.id === questionId),
          ),
        }));
      },

      clearMistakesForLesson: lessonId => {
        set(state => ({
          mistakesBank: state.mistakesBank.filter(m => m.lessonId !== lessonId),
        }));
      },

      bumpStreakIfNeeded: () => {
        const today = todayStr();
        const { lastActiveDate, streak, streakFreezes } = get();
        if (lastActiveDate === today) return;
        let newStreak = streak;
        if (lastActiveDate === "") {
          newStreak = 1;
          set({ streak: 1, lastActiveDate: today });
        } else {
          const gap = daysBetween(lastActiveDate, today);
          if (gap === 1) {
            // 正常连续
            newStreak = streak + 1;
            const newFreezes =
              isMonday() && streakFreezes < MAX_FREEZES ? streakFreezes + 1 : streakFreezes;
            set({ streak: newStreak, lastActiveDate: today, streakFreezes: newFreezes });
          } else if (gap > 1) {
            const missed = gap - 1;
            if (streakFreezes >= missed) {
              newStreak = streak + 1;
              set({
                streak: newStreak,
                lastActiveDate: today,
                streakFreezes: streakFreezes - missed,
              });
            } else {
              newStreak = 1;
              set({ streak: 1, lastActiveDate: today });
            }
          }
        }

        // === 💎 连胜里程碑奖励：3/7/14/30/60/100 天（每档一次） ===
        const reward = STREAK_MILESTONE_REWARDS[newStreak];
        if (reward && !get().claimedStreakRewards[newStreak]) {
          set(state => ({
            gems: state.gems + reward,
            lifetimeGems: state.lifetimeGems + reward,
            claimedStreakRewards: {
              ...state.claimedStreakRewards,
              [newStreak]: true,
            },
            // 留给 DailyRewardWatcher 弹「连续 N 天！+M💎」庆祝
            pendingStreakMilestone: { streak: newStreak, gems: reward },
          }));
        }
      },

      toggleMute: () => {
        set(state => ({ muted: !state.muted }));
      },

      toggleAutoNarrate: () => {
        set(state => ({ autoNarrate: !state.autoNarrate }));
      },

      // --------------------------------------------------------
      // 心数
      // --------------------------------------------------------

      loseHeart: () => {
        const { hearts, nextHeartAt } = get();
        if (hearts <= 0) return;
        const newHearts = hearts - 1;
        // 只有原本是满心时才开始充能；否则保留已有 nextHeartAt
        const newNext = nextHeartAt ?? Date.now() + HEART_RECHARGE_MS;
        set({ hearts: newHearts, nextHeartAt: newNext });
      },

      refreshHearts: () => {
        let { hearts, nextHeartAt } = get();
        if (hearts >= MAX_HEARTS || !nextHeartAt) {
          // 确保满心时 nextHeartAt 为空
          if (hearts >= MAX_HEARTS && nextHeartAt !== null) {
            set({ nextHeartAt: null });
          }
          return;
        }
        const now = Date.now();
        let changed = false;
        while (nextHeartAt && now >= nextHeartAt && hearts < MAX_HEARTS) {
          hearts += 1;
          changed = true;
          nextHeartAt = hearts < MAX_HEARTS ? nextHeartAt + HEART_RECHARGE_MS : null;
        }
        if (changed) set({ hearts, nextHeartAt });
      },

      refillHeartsFull: () => {
        set({ hearts: MAX_HEARTS, nextHeartAt: null });
      },

      buyHeartRefill: () => {
        // 先结算自然回复，避免"已经回满还扣费"
        get().refreshHearts();
        const { gems, hearts } = get();
        if (hearts >= MAX_HEARTS) return false;
        if (gems < HEART_REFILL_COST) return false;
        set(state => ({
          gems: state.gems - HEART_REFILL_COST,
          hearts: MAX_HEARTS,
          nextHeartAt: null,
        }));
        return true;
      },

      buyStreakFreeze: () => {
        const { gems, streakFreezes } = get();
        if (streakFreezes >= MAX_FREEZES) return false;
        if (gems < FREEZE_COST) return false;
        set(state => ({
          gems: state.gems - FREEZE_COST,
          streakFreezes: state.streakFreezes + 1,
        }));
        return true;
      },

      setDailyGoal: goal => {
        set({ dailyGoal: Math.max(10, Math.min(500, goal)) });
      },

      upsertLessonSession: session => {
        set({ activeLesson: session });
      },

      clearLessonSession: () => {
        set({ activeLesson: null });
      },

      // --------------------------------------------------------
      // 💎 宝石 / 宝箱 / 首次完美
      // --------------------------------------------------------

      addGems: n => {
        if (n <= 0) return;
        set(state => ({
          gems: state.gems + n,
          lifetimeGems: state.lifetimeGems + n,
        }));
      },

      spendGems: n => {
        if (n <= 0) return true;
        const { gems } = get();
        if (gems < n) return false;
        set({ gems: gems - n });
        return true;
      },

      markPerfected: lessonId => {
        const { perfectedLessons } = get();
        if (perfectedLessons[lessonId]) return false;
        set({ perfectedLessons: { ...perfectedLessons, [lessonId]: true } });
        return true;
      },

      claimChest: chestId => {
        const { claimedChests } = get();
        if (claimedChests[chestId]) return false;
        set({ claimedChests: { ...claimedChests, [chestId]: true } });
        return true;
      },

      // --------------------------------------------------------
      // 🎨 美妆系统
      // --------------------------------------------------------

      unlockCosmetic: id => {
        const item = getCosmeticById(id);
        if (!item) return;
        set(state => ({
          ownedCosmetics: { ...state.ownedCosmetics, [id]: true },
        }));
      },

      purchaseCosmetic: id => {
        const item = getCosmeticById(id);
        if (!item) return { ok: false, reason: "未找到道具" };
        const { ownedCosmetics, gems } = get();
        if (ownedCosmetics[id]) return { ok: false, reason: "已经拥有了" };
        if (gems < item.cost) return { ok: false, reason: "宝石不够" };
        set(state => ({
          gems: state.gems - item.cost,
          ownedCosmetics: { ...state.ownedCosmetics, [id]: true },
        }));
        // 自动装备购买的道具
        get().equipCosmetic(id);
        return { ok: true };
      },

      equipCosmetic: id => {
        const item = getCosmeticById(id);
        if (!item) return false;
        const { ownedCosmetics } = get();
        if (!ownedCosmetics[id]) return false;
        if (item.type === "mascot_skin") set({ equippedMascotSkin: id });
        else if (item.type === "ui_theme") set({ equippedTheme: id });
        else if (item.type === "lesson_backdrop") set({ equippedBackdrop: id });
        return true;
      },

      // --------------------------------------------------------
      // ⏱️ 时间关怀
      // --------------------------------------------------------

      setDailyTimeLimit: ms => {
        set({ dailyTimeLimitMs: Math.max(0, ms) });
      },

      setSessionTimeLimit: ms => {
        set({ sessionTimeLimitMs: Math.max(0, ms) });
      },

      addLearningTimeMs: ms => {
        if (ms <= 0) return;
        const today = todayStr();
        set(state => {
          const isSameDay = state.lastXpDate === today;
          const prev = isSameDay ? state.todayTimeMs : 0;
          return {
            todayTimeMs: prev + ms,
            lastXpDate: today,
          };
        });
      },

      // --------------------------------------------------------
      // 🔁 连胜补卡（消耗 50 gems 找回昨天的 streak）
      // --------------------------------------------------------

      // --------------------------------------------------------
      // 📚 SRS：复习答题后更新错题状态
      // --------------------------------------------------------

      reviewMistake: (lessonId, questionId, isCorrect) => {
        set(state => ({
          mistakesBank: state.mistakesBank
            .map(m => {
              if (m.lessonId !== lessonId || m.question.id !== questionId) return m;
              const today = new Date();
              const todayDateStr = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, "0")}-${String(today.getDate()).padStart(2, "0")}`;
              if (!isCorrect) {
                // 答错 → 重置回 box 1
                return {
                  ...m,
                  box: 1 as const,
                  correctCount: 0,
                  lastReviewedAt: today.toISOString(),
                  nextReviewDate: todayDateStr,
                };
              }
              const correctCount = (m.correctCount ?? 0) + 1;
              const currentBox = m.box ?? 1;
              const nextBox: 1 | 2 | 3 = currentBox >= 3 ? 3 : ((currentBox + 1) as 2 | 3);
              const intervalDays = nextBox === 2 ? 1 : nextBox === 3 ? 3 : 7;
              const next = new Date(today);
              next.setDate(next.getDate() + intervalDays);
              const nextDateStr = `${next.getFullYear()}-${String(next.getMonth() + 1).padStart(2, "0")}-${String(next.getDate()).padStart(2, "0")}`;
              return {
                ...m,
                box: nextBox,
                correctCount,
                lastReviewedAt: today.toISOString(),
                nextReviewDate: nextDateStr,
              };
            }),
        }));
      },

      claimDailyReward: () => {
        const today = todayStr();
        const { lastDailyRewardDate, streak, lastActiveDate, streakFreezes } = get();
        if (lastDailyRewardDate === today) return { gems: 0, effectiveStreak: 0 };
        // 数额按「有效连胜」折算：断签且护盾兜不住 → 按 0 档发（不谎报连续天数）
        const effectiveStreak = effectiveStreakOf(streak, lastActiveDate, streakFreezes);
        const reward = dailyRewardForStreak(effectiveStreak);
        set(state => ({
          gems: state.gems + reward,
          lifetimeGems: state.lifetimeGems + reward,
          lastDailyRewardDate: today,
        }));
        return { gems: reward, effectiveStreak };
      },

      claimAchievement: id => {
        const { unlockedAchievements } = get();
        if (unlockedAchievements[id]) return 0;
        const ach = ALL_ACHIEVEMENTS.find(a => a.id === id);
        if (!ach) return 0;
        set(state => ({
          unlockedAchievements: { ...state.unlockedAchievements, [id]: true },
          gems: state.gems + ach.reward,
          lifetimeGems: state.lifetimeGems + ach.reward,
        }));
        return ach.reward;
      },

      clearPendingStreakMilestone: () => {
        set({ pendingStreakMilestone: null });
      },

      makeUpYesterdayStreak: () => {
        const { gems, streak, lastActiveDate } = get();
        if (gems < STREAK_MAKEUP_COST) return false;
        const today = todayStr();
        // 必须是今天没活动过 + 昨天断了
        if (lastActiveDate === today) return false;
        const gap = daysBetween(lastActiveDate, today);
        if (gap < 2) return false;
        // 扣 gems + 把 lastActiveDate 设回昨天，下次 bumpStreakIfNeeded 会顺延
        set({
          gems: gems - STREAK_MAKEUP_COST,
          // 假装"昨天有学过" → 让 bumpStreakIfNeeded 看到 gap=1
          lastActiveDate: (() => {
            const d = new Date();
            d.setDate(d.getDate() - 1);
            return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
          })(),
          streak,
        });
        return true;
      },
    }),
    {
      name: "csf-progress-v1",
      storage: createJSONStorage(() => localStorage),
      // 版本迁移：
      //   v1 → v2：新增 hearts / dailyGoal / freezes / activeLesson
      //   v2 → v3：新增 gems / lifetimeGems / claimedChests / perfectedLessons + autoNarrate
      //   v3 → v4：新增美妆系统 ownedCosmetics / equippedXxx + claimedStreakRewards + 时间关怀
      //   v4 → v5：新增 xpHistory / lessonHistory / lastDailyRewardDate
      //   v5 → v6：新增 selectedGrade（首次进入引导选择年级）
      //   v6 → v7：阅读奖励从"伪课程"迁出 —— completedLessons/perfectedLessons 里
      //            passage-/story- 前缀的条目移入 completedReadings，课时统计尽力回退
      //   v7 → v8：成就永久解锁账本 unlockedAchievements（当前实时解锁集一次性写入，
      //            不补发奖励）+ pendingStreakMilestone + 护盾一次性迁移 max(现值, 2)
      version: 8,
      migrate: (persistedState: unknown) => {
        const state = (persistedState as Partial<ProgressState>) ?? {};
        const starterOwned = Object.fromEntries(
          getStarterCosmetics().map(c => [c.id, true as const]),
        );

        // === v7：把历史上以 recordLessonComplete 记录的阅读（passage-/story- 伪 id）
        //     移入 completedReadings，不再污染课程记录与成就统计 ===
        const isReadingId = (id: string) =>
          id.startsWith("passage-") || id.startsWith("story-");
        const completedLessons: Record<string, LessonResult> = {};
        const completedReadings: Record<string, string> = {
          ...(state.completedReadings ?? {}),
        };
        const lessonHistory: Record<string, number> = {
          ...(state.lessonHistory ?? {}),
        };
        for (const [id, result] of Object.entries(state.completedLessons ?? {})) {
          if (isReadingId(id)) {
            completedReadings[id] =
              completedReadings[id] ?? (result.completedAt || new Date().toISOString());
            // 课时统计尽力回退：按完成日期 -1（阅读不该算课时）
            const dayKey = (result.completedAt ?? "").slice(0, 10);
            if (dayKey && lessonHistory[dayKey]) {
              lessonHistory[dayKey] = Math.max(0, lessonHistory[dayKey] - 1);
            }
          } else {
            completedLessons[id] = result;
          }
        }
        const perfectedLessons = Object.fromEntries(
          Object.entries(state.perfectedLessons ?? {}).filter(
            ([id]) => !isReadingId(id),
          ),
        ) as Record<string, true>;

        // === v8：成就账本 —— 把当前按进度算出来的解锁集一次性写入（不补发奖励，
        //     这些是历史解锁；此后只有真正新解锁的成就才发宝石） ===
        const unlockedAchievements: Record<string, true> = {
          ...(state.unlockedAchievements ?? {}),
        };
        try {
          for (const id of computeUnlockedAchievementIds({
            xp: state.xp ?? 0,
            streak: state.streak ?? 0,
            lifetimeGems: state.lifetimeGems ?? 0,
            completedLessons,
            perfectedLessons,
            ownedCosmetics: state.ownedCosmetics ?? {},
            mistakesBank: state.mistakesBank ?? [],
          })) {
            unlockedAchievements[id] = true;
          }
        } catch {
          /* 快照字段异常时保守跳过，账本从空开始 */
        }

        return {
          ...state,
          hearts: state.hearts ?? MAX_HEARTS,
          nextHeartAt: state.nextHeartAt ?? null,
          dailyGoal: state.dailyGoal ?? DEFAULT_DAILY_GOAL,
          todayXp: state.todayXp ?? 0,
          lastXpDate: state.lastXpDate ?? "",
          // v8：护盾一次性迁移为 max(现值, 2)；超过 2 的不没收（只封新购）
          streakFreezes: Math.max(state.streakFreezes ?? INITIAL_FREEZES, INITIAL_FREEZES),
          activeLesson: state.activeLesson ?? null,
          autoNarrate: state.autoNarrate ?? true,
          gems: state.gems ?? 0,
          lifetimeGems: state.lifetimeGems ?? 0,
          claimedChests: state.claimedChests ?? {},
          completedLessons,
          perfectedLessons,
          // v4 新字段
          ownedCosmetics: { ...starterOwned, ...(state.ownedCosmetics ?? {}) },
          equippedMascotSkin: state.equippedMascotSkin ?? DEFAULT_EQUIPPED.mascotSkin,
          equippedTheme: state.equippedTheme ?? DEFAULT_EQUIPPED.uiTheme,
          equippedBackdrop: state.equippedBackdrop ?? DEFAULT_EQUIPPED.lessonBackdrop,
          claimedStreakRewards: state.claimedStreakRewards ?? {},
          todayTimeMs: state.todayTimeMs ?? 0,
          dailyTimeLimitMs: state.dailyTimeLimitMs ?? 0,
          sessionTimeLimitMs: state.sessionTimeLimitMs ?? 0,
          xpHistory: state.xpHistory ?? {},
          lessonHistory,
          lastDailyRewardDate: state.lastDailyRewardDate ?? "",
          // v6
          selectedGrade: state.selectedGrade ?? null,
          // v7
          completedReadings,
          // v8
          unlockedAchievements,
          pendingStreakMilestone: state.pendingStreakMilestone ?? null,
        } as ProgressState;
      },
    },
  ),
);
