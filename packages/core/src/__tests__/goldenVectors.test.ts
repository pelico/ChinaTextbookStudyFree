/**
 * goldenVectors.test.ts —— 逐组断言 spec/golden-vectors.json 与 TS 实现一致。
 *
 * 这份 JSON 是 web / iOS 双端的黄金向量：Swift 侧应读取同一文件跑等价断言。
 * 任何一端实现改动导致这里飘红，说明经济口径漂移，必须先改 spec 再改实现。
 */

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import vectors from "../../spec/golden-vectors.json";
import {
  advanceStreak,
  dailyRewardForStreak,
  lessonGemDrip,
  starsFromAccuracy,
  streakMilestoneReward,
  xpForLesson,
} from "../economy";
import { latchUnlocked } from "../achievements";
import { reviewSrsEntry, type SrsBox, type SrsMistakeEntry } from "../srs";
import { computeChestsForBook } from "../chestLogic";
import type { PathLessonMeta, Question } from "../types";

// ============================================================
// 黄金向量组
// ============================================================

describe("golden vectors: stars", () => {
  for (const v of vectors.stars) {
    it(`accuracy=${v.accuracy} → ${v.expStars} 星`, () => {
      expect(starsFromAccuracy(v.accuracy)).toBe(v.expStars);
    });
  }
});

describe("golden vectors: xp", () => {
  for (const v of vectors.xp) {
    it(`correct=${v.correctCount} perfect=${v.perfect} first=${v.firstPerfect} weekend=${v.isWeekend} → ${v.expXp}`, () => {
      expect(
        xpForLesson({
          correctCount: v.correctCount,
          perfect: v.perfect,
          firstPerfect: v.firstPerfect,
          isWeekend: v.isWeekend,
        }),
      ).toBe(v.expXp);
    });
  }
});

describe("golden vectors: gemDrip", () => {
  for (const v of vectors.gemDrip) {
    it(`stars=${v.stars} first=${v.isFirstPerfect} crossedGoal=${v.crossedDailyGoal} → ${v.expGems}`, () => {
      expect(
        lessonGemDrip({
          stars: v.stars as 1 | 2 | 3,
          isFirstPerfect: v.isFirstPerfect,
          crossedDailyGoal: v.crossedDailyGoal,
        }),
      ).toBe(v.expGems);
    });
  }
});

describe("golden vectors: streakAdvance", () => {
  for (const v of vectors.streakAdvance) {
    it(v.$case, () => {
      const result = advanceStreak({
        streak: v.streak,
        freezes: v.freezes,
        gapDays: v.gapDays,
        isMonday: v.isMonday,
      });
      expect(result.streak).toBe(v.expStreak);
      expect(result.freezes).toBe(v.expFreezes);
      expect(result.freezesConsumed).toBe(v.expConsumed);
    });
  }
});

describe("golden vectors: srsReview", () => {
  const FROZEN_NOW = new Date(2026, 7, 25, 10, 0, 0); // 2026-08-25（周二）

  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(FROZEN_NOW);
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  function localDateStr(daysFromNow: number): string {
    const d = new Date(FROZEN_NOW);
    d.setDate(d.getDate() + daysFromNow);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  }

  const dummyQuestion: Question = {
    id: 1,
    type: "choice",
    score: 1,
    difficulty: 1,
    knowledge_point: "kp",
    question: "q",
    options: ["A", "B", "C", "D"],
    answer: "A",
    explanation: "e",
  };

  for (const v of vectors.srsReview) {
    it(`box${v.box} ${v.isCorrect ? "答对" : "答错"} → box${v.expBox}，${v.expIntervalDays} 天后复习`, () => {
      const entry: SrsMistakeEntry = {
        lessonId: "lesson-1",
        question: dummyQuestion,
        addedAt: FROZEN_NOW.toISOString(),
        box: v.box as SrsBox,
        correctCount: 0,
      };
      const next = reviewSrsEntry(entry, v.isCorrect);
      expect(next.box).toBe(v.expBox);
      expect(next.nextReviewDate).toBe(localDateStr(v.expIntervalDays));
    });
  }
});

describe("golden vectors: dailyReward", () => {
  for (const v of vectors.dailyReward) {
    it(`streak=${v.streak} → ${v.expGems} 宝石`, () => {
      expect(dailyRewardForStreak(v.streak)).toBe(v.expGems);
    });
  }
});

describe("golden vectors: milestone", () => {
  for (const v of vectors.milestone) {
    it(`streakAfter=${v.streakAfter} → ${v.expGems} 宝石`, () => {
      expect(streakMilestoneReward(v.streakAfter)).toBe(v.expGems);
    });
  }
});

describe("golden vectors: chestSlot", () => {
  function makeLessons(count: number): PathLessonMeta[] {
    return Array.from({ length: count }, (_, i) => ({
      id: `book-u1-l${i + 1}`,
      title: `第 ${i + 1} 课`,
      unitNumber: 1,
      unitTitle: "第一单元",
      kpIndex: i + 1,
      kpTotal: count,
      questionCount: 10,
    }));
  }

  for (const v of vectors.chestSlot) {
    it(`单元内完成第 ${v.lessonsCompletedInUnit} 课后应有 ${v.expChests} 个宝箱`, () => {
      const slots = computeChestsForBook("book", makeLessons(v.lessonsCompletedInUnit));
      expect(slots.length).toBe(v.expChests);
    });
  }
});

// ============================================================
// 补充单测
// ============================================================

describe("latchUnlocked（只进不出账本）", () => {
  it("空账本 + 新解锁 = 新解锁", () => {
    expect(latchUnlocked([], ["a", "b"])).toEqual(["a", "b"]);
  });

  it("进度倒退（当前集合缩水）不会回锁", () => {
    expect(latchUnlocked(["streak-7", "streak-30"], ["streak-3"])).toEqual([
      "streak-7",
      "streak-30",
      "streak-3",
    ]);
  });

  it("重复 id 去重，且保持 prevLedger 原顺序", () => {
    expect(latchUnlocked(["a", "b"], ["b", "c", "a", "c"])).toEqual(["a", "b", "c"]);
  });

  it("不修改入参", () => {
    const prev = ["a"];
    const current = ["a", "b"];
    latchUnlocked(prev, current);
    expect(prev).toEqual(["a"]);
    expect(current).toEqual(["a", "b"]);
  });
});

describe("dailyRewardForStreak 边界", () => {
  it("负数连胜按 0 处理", () => {
    expect(dailyRewardForStreak(-5)).toBe(5);
  });

  it("超过 7 封顶在最后一档 30", () => {
    expect(dailyRewardForStreak(8)).toBe(30);
    expect(dailyRewardForStreak(365)).toBe(30);
  });

  it("6 天 → 25", () => {
    expect(dailyRewardForStreak(6)).toBe(25);
  });
});
