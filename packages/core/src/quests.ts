/**
 * quests.ts —— 每日任务（Daily Quests）单一事实源
 *
 * 与 iOS `Domain/Quests.swift` 逐行对齐：同一天双端必须给出完全相同的
 * 三条任务（同 kind / 同 target / 同 reward / 同顺序）。
 *
 * 确定性来源：日期字符串（YYYY-MM-DD）→ djb2 滚动哈希 → SplitMix64
 * finalizer 雪崩 → 对候选池取模。TS 端用 BigInt 模拟 Swift 的 UInt64
 * 环绕运算（&+ / &*），位运算逐位一致；spec/golden-vectors.json 的
 * `quests` 组是双端对照的黄金向量。
 */

export type QuestKind = "earnXP" | "finishLessons" | "reviewMistakes" | "readTexts";

export interface Quest {
  kind: QuestKind;
  /** 目标计数（earnXP 为 XP 数，其余为次数） */
  target: number;
  /** 完成奖励（宝石） */
  reward: number;
  /** 当日内稳定的 id —— 领取账本以 `"${date}:${id}"` 记账 */
  id: string;
  /** 儿童友好中文标题（与 iOS 文案一致） */
  title: string;
}

function makeQuest(kind: QuestKind, target: number, reward: number): Quest {
  return { kind, target, reward, id: `${kind}-${target}`, title: questTitle(kind, target) };
}

/** 与 iOS `Quest.title` 完全一致的中文文案。 */
export function questTitle(kind: QuestKind, target: number): string {
  switch (kind) {
    case "earnXP":         return `获得 ${target} 点经验`;
    case "finishLessons":  return `完成 ${target} 节小课`;
    case "reviewMistakes": return `复习 ${target} 道错题`;
    case "readTexts":      return `读完 ${target} 篇课文或故事`;
  }
}

/**
 * 候选池 —— 与 iOS `Quests.pool` 逐项一致（顺序也一致，
 * 因为 pick 是「按 kind 过滤后取模」，顺序参与结果）。
 */
export const QUEST_POOL: readonly Quest[] = [
  makeQuest("earnXP", 30, 10),
  makeQuest("earnXP", 60, 15),
  makeQuest("earnXP", 100, 25),
  makeQuest("finishLessons", 1, 10),
  makeQuest("finishLessons", 2, 20),
  makeQuest("finishLessons", 3, 30),
  makeQuest("reviewMistakes", 1, 10),
  makeQuest("reviewMistakes", 3, 20),
  makeQuest("readTexts", 1, 15),
  makeQuest("readTexts", 2, 25),
];

const U64_MASK = (1n << 64n) - 1n;

/**
 * SplitMix64 finalizer —— 与 Swift 侧 `Quests.mix` 位运算逐位一致
 * （&+ / &* 用 BigInt + 64 位掩码模拟环绕）。
 */
function mix(value: bigint): bigint {
  let x = (value + 0x9e3779b97f4a7c15n) & U64_MASK;
  x = ((x ^ (x >> 30n)) * 0xbf58476d1ce4e5b9n) & U64_MASK;
  x = ((x ^ (x >> 27n)) * 0x94d049bb133111ebn) & U64_MASK;
  return x ^ (x >> 31n);
}

/** 字符串 → UTF-8 字节序列（日期串实为 ASCII，此处为通用兜底）。 */
function utf8Bytes(s: string): number[] {
  const bytes: number[] = [];
  for (let i = 0; i < s.length; i++) {
    let code = s.codePointAt(i)!;
    if (code > 0xffff) i++; // 代理对占两个 code unit
    if (code < 0x80) bytes.push(code);
    else if (code < 0x800) {
      bytes.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
    } else if (code < 0x10000) {
      bytes.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
    } else {
      bytes.push(
        0xf0 | (code >> 18),
        0x80 | ((code >> 12) & 0x3f),
        0x80 | ((code >> 6) & 0x3f),
        0x80 | (code & 0x3f),
      );
    }
  }
  return bytes;
}

/**
 * 给定日期（YYYY-MM-DD）的三条每日任务，确定性生成：
 *   - 第一条必为 earnXP；
 *   - 后两条从 finishLessons / reviewMistakes / readTexts 中不放回抽取，
 *     因此一天内三条任务 kind 两两不同；
 *   - 同一天任何时刻、任何端调用结果完全一致。
 */
export function dailyQuests(dateString: string): Quest[] {
  let hash = 5381n;
  for (const byte of utf8Bytes(dateString)) {
    hash = (hash * 33n + BigInt(byte)) & U64_MASK;
  }
  hash = mix(hash);

  const index = (count: number, salt: bigint): number => {
    if (count <= 0) return 0;
    return Number(mix((hash + salt) & U64_MASK) % BigInt(count));
  };
  const pick = (kind: QuestKind, salt: bigint): Quest => {
    const options = QUEST_POOL.filter(q => q.kind === kind);
    return options[index(options.length, salt)];
  };

  // 与 iOS 一致：先抽走 firstKind（不放回），再在剩余里抽 secondKind
  const rest: QuestKind[] = ["finishLessons", "reviewMistakes", "readTexts"];
  const [firstKind] = rest.splice(index(rest.length, 0x11n), 1);
  const secondKind = rest[index(rest.length, 0x22n)];

  return [pick("earnXP", 0x01n), pick(firstKind, 0x33n), pick(secondKind, 0x44n)];
}
