/**
 * backup.ts —— 存档备份中立信封（BackupEnvelope v1，双端互通）
 *
 * 设计目标：
 *   - web / iOS 导出、导入都走同一个 JSON 信封，字段命名与平台无关；
 *   - 零依赖手写校验（validateBackup），不引入 zod 等库；
 *   - 瞬态状态（红心恢复计时、进行中的课程会话、今日 XP 等）不进信封，
 *     hearts 本身允许携带（导入后即时可用），缺省时回满；
 *   - 前向兼容策略（见 validateBackup 注释）。
 *
 * 校验契约：
 *   - ok === false ⇔ 信封结构性不可用（非对象 / schema 不符 / version 非正整数 /
 *     data 非对象）。此时 data 为 undefined，errors 说明致命原因。
 *   - ok === true 时 data 一定是补全默认值后的完整 BackupEnvelope；
 *     errors 记录被丢弃或替换为默认值的字段（作为可展示的"修复日志"，可为空数组）。
 */

import type { Question } from "./types";
import { DEFAULT_EQUIPPED } from "./cosmetics";
import { MAX_HEARTS, DEFAULT_DAILY_GOAL, INITIAL_FREEZES } from "./economy";

// ============================================================
// 类型
// ============================================================

export const BACKUP_SCHEMA = "cstf-backup" as const;
export const BACKUP_VERSION = 1;

export type BackupPlatform = "ios" | "web";

/** completedLessons 里单条课程结果（与 LessonResult 对齐，但完全自包含）。 */
export interface BackupLessonResult {
  stars: 1 | 2 | 3;
  accuracy: number; // 0-1
  completedAt: string; // ISO
}

/**
 * 错题本条目 —— 只导可跨端复原 SRS 状态的最小字段。
 * question 是题面快照（可选）：iOS/web 本地题库齐全时可省略，
 * 携带时导入端优先使用快照展示。
 */
export interface BackupMistake {
  lessonId: string;
  questionId: number;
  box?: 1 | 2 | 3;
  correctCount?: number;
  nextReviewDate?: string; // YYYY-MM-DD
  graduated?: boolean;
  question?: Question;
}

/** 已装扮项（key 与 cosmetics.DEFAULT_EQUIPPED 一致）。 */
export interface BackupEquipped {
  mascotSkin: string;
  uiTheme: string;
  lessonBackdrop: string;
}

export interface BackupData {
  xp: number;
  streak: number;
  lastActiveDate: string; // YYYY-MM-DD
  streakFreezes: number;
  gems: number;
  lifetimeGems: number;
  hearts: number;
  dailyGoal: number;
  joinedDate?: string; // YYYY-MM-DD
  completedLessons: Record<string, BackupLessonResult>;
  /** 阅读完成表：id → 完成日期（YYYY-MM-DD） */
  completedReadings: Record<string, string>;
  perfectedLessons?: Record<string, true>;
  mistakesBank: BackupMistake[];
  claimedChests: Record<string, true>;
  /** key 为里程碑天数的字符串形式（JSON 键天然是字符串） */
  claimedStreakRewards: Record<string, true>;
  lastDailyRewardDate: string; // YYYY-MM-DD，"" = 从未领取
  unlockedAchievements: Record<string, true>;
  claimedAchievements?: Record<string, true>;
  ownedCosmetics: Record<string, true>;
  equipped: BackupEquipped;
  /** 日期 → 当日 XP */
  xpHistory: Record<string, number>;
  /** 联赛段位 id（"bronze" 等）。宽松保留为 string，未知段位由导入端降级 */
  leagueTier?: string;
  leagueWeekKey?: string;
}

export interface BackupEnvelope {
  schema: typeof BACKUP_SCHEMA;
  version: number;
  exportedAt: string; // ISO
  platform: BackupPlatform;
  data: BackupData;
}

export interface BackupValidationResult {
  ok: boolean;
  /** ok 时为规整后的完整信封；否则 undefined */
  data?: BackupEnvelope;
  /** ok=false：致命原因；ok=true：字段级修复日志（可为空） */
  errors: string[];
}

// ============================================================
// buildBackup —— 导出端构造信封（缺字段自动补默认）
// ============================================================

function defaultData(): BackupData {
  return {
    xp: 0,
    streak: 0,
    lastActiveDate: "",
    streakFreezes: INITIAL_FREEZES,
    gems: 0,
    lifetimeGems: 0,
    hearts: MAX_HEARTS,
    dailyGoal: DEFAULT_DAILY_GOAL,
    completedLessons: {},
    completedReadings: {},
    mistakesBank: [],
    claimedChests: {},
    claimedStreakRewards: {},
    lastDailyRewardDate: "",
    unlockedAchievements: {},
    ownedCosmetics: {},
    equipped: { ...DEFAULT_EQUIPPED },
    xpHistory: {},
  };
}

export interface BuildBackupInput {
  platform: BackupPlatform;
  /** 缺省用当前时刻 ISO */
  exportedAt?: string;
  /** 进度字段（可部分给出，缺失补默认） */
  data?: Partial<BackupData>;
}

/** 构造一个合法的 v1 信封。传入的 data 可以只给部分字段。 */
export function buildBackup(input: BuildBackupInput): BackupEnvelope {
  return {
    schema: BACKUP_SCHEMA,
    version: BACKUP_VERSION,
    exportedAt: input.exportedAt ?? new Date().toISOString(),
    platform: input.platform,
    data: { ...defaultData(), ...stripUndefined(input.data ?? {}) },
  };
}

function stripUndefined<T extends object>(obj: T): Partial<T> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(obj)) {
    if (v !== undefined) out[k] = v;
  }
  return out as Partial<T>;
}

// ============================================================
// validateBackup —— 导入端零依赖校验
// ============================================================

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function isFiniteNumber(v: unknown): v is number {
  return typeof v === "number" && Number.isFinite(v);
}

/** 非负数字，坏类型/负数 → fallback，并记一条修复日志。 */
function readNonNegNumber(
  obj: Record<string, unknown>,
  key: string,
  fallback: number,
  log: string[],
): number {
  const v = obj[key];
  if (v === undefined) return fallback;
  if (!isFiniteNumber(v) || v < 0) {
    log.push(`data.${key} 类型或取值非法，已重置为默认值 ${fallback}`);
    return fallback;
  }
  return v;
}

function readString(
  obj: Record<string, unknown>,
  key: string,
  fallback: string,
  log: string[],
): string {
  const v = obj[key];
  if (v === undefined) return fallback;
  if (typeof v !== "string") {
    log.push(`data.${key} 不是字符串，已重置为默认值`);
    return fallback;
  }
  return v;
}

function readOptionalString(
  obj: Record<string, unknown>,
  key: string,
  log: string[],
): string | undefined {
  const v = obj[key];
  if (v === undefined) return undefined;
  if (typeof v !== "string") {
    log.push(`data.${key} 不是字符串，已忽略`);
    return undefined;
  }
  return v;
}

/** Record<string, true>：只保留值为 truthy 的键。 */
function readFlagRecord(
  obj: Record<string, unknown>,
  key: string,
  log: string[],
): Record<string, true> {
  const v = obj[key];
  if (v === undefined) return {};
  if (!isRecord(v)) {
    log.push(`data.${key} 不是对象，已重置为空`);
    return {};
  }
  const out: Record<string, true> = {};
  for (const [k, val] of Object.entries(v)) {
    if (val) out[k] = true;
  }
  return out;
}

/** Record<string, string>（completedReadings）。 */
function readStringRecord(
  obj: Record<string, unknown>,
  key: string,
  log: string[],
): Record<string, string> {
  const v = obj[key];
  if (v === undefined) return {};
  if (!isRecord(v)) {
    log.push(`data.${key} 不是对象，已重置为空`);
    return {};
  }
  const out: Record<string, string> = {};
  for (const [k, val] of Object.entries(v)) {
    if (typeof val === "string") out[k] = val;
    else log.push(`data.${key}["${k}"] 不是字符串，已丢弃`);
  }
  return out;
}

/** Record<string, number>（xpHistory）。 */
function readNumberRecord(
  obj: Record<string, unknown>,
  key: string,
  log: string[],
): Record<string, number> {
  const v = obj[key];
  if (v === undefined) return {};
  if (!isRecord(v)) {
    log.push(`data.${key} 不是对象，已重置为空`);
    return {};
  }
  const out: Record<string, number> = {};
  for (const [k, val] of Object.entries(v)) {
    if (isFiniteNumber(val) && val >= 0) out[k] = val;
    else log.push(`data.${key}["${k}"] 不是合法数字，已丢弃`);
  }
  return out;
}

function readCompletedLessons(
  obj: Record<string, unknown>,
  log: string[],
): Record<string, BackupLessonResult> {
  const v = obj["completedLessons"];
  if (v === undefined) return {};
  if (!isRecord(v)) {
    log.push("data.completedLessons 不是对象，已重置为空");
    return {};
  }
  const out: Record<string, BackupLessonResult> = {};
  for (const [lessonId, raw] of Object.entries(v)) {
    if (!isRecord(raw)) {
      log.push(`data.completedLessons["${lessonId}"] 不是对象，已丢弃`);
      continue;
    }
    const starsRaw = raw["stars"];
    const stars: 1 | 2 | 3 =
      starsRaw === 1 || starsRaw === 2 || starsRaw === 3 ? starsRaw : 1;
    if (stars !== starsRaw) {
      log.push(`data.completedLessons["${lessonId}"].stars 非法，已按 1 星处理`);
    }
    const accRaw = raw["accuracy"];
    const accuracy = isFiniteNumber(accRaw) ? Math.min(1, Math.max(0, accRaw)) : 0;
    const completedAt = typeof raw["completedAt"] === "string" ? raw["completedAt"] : "";
    out[lessonId] = { stars, accuracy, completedAt };
  }
  return out;
}

function readMistakesBank(
  obj: Record<string, unknown>,
  log: string[],
): BackupMistake[] {
  const v = obj["mistakesBank"];
  if (v === undefined) return [];
  if (!Array.isArray(v)) {
    log.push("data.mistakesBank 不是数组，已重置为空");
    return [];
  }
  const out: BackupMistake[] = [];
  v.forEach((raw, i) => {
    if (!isRecord(raw)) {
      log.push(`data.mistakesBank[${i}] 不是对象，已丢弃`);
      return;
    }
    const lessonId = raw["lessonId"];
    const questionId = raw["questionId"];
    if (typeof lessonId !== "string" || !isFiniteNumber(questionId)) {
      log.push(`data.mistakesBank[${i}] 缺少 lessonId/questionId，已丢弃`);
      return;
    }
    const entry: BackupMistake = { lessonId, questionId };
    const box = raw["box"];
    if (box === 1 || box === 2 || box === 3) entry.box = box;
    if (isFiniteNumber(raw["correctCount"]) && (raw["correctCount"] as number) >= 0) {
      entry.correctCount = raw["correctCount"] as number;
    }
    if (typeof raw["nextReviewDate"] === "string") {
      entry.nextReviewDate = raw["nextReviewDate"];
    }
    if (typeof raw["graduated"] === "boolean") entry.graduated = raw["graduated"];
    // 题面快照：宽松透传（只要求是对象且带数字 id），导入端展示前自行兜底
    const q = raw["question"];
    if (isRecord(q) && isFiniteNumber(q["id"])) {
      entry.question = q as unknown as Question;
    }
    out.push(entry);
  });
  return out;
}

function readEquipped(
  obj: Record<string, unknown>,
  log: string[],
): BackupEquipped {
  const fallback: BackupEquipped = { ...DEFAULT_EQUIPPED };
  const v = obj["equipped"];
  if (v === undefined) return fallback;
  if (!isRecord(v)) {
    log.push("data.equipped 不是对象，已重置为默认装扮");
    return fallback;
  }
  return {
    mascotSkin:
      typeof v["mascotSkin"] === "string" ? v["mascotSkin"] : fallback.mascotSkin,
    uiTheme: typeof v["uiTheme"] === "string" ? v["uiTheme"] : fallback.uiTheme,
    lessonBackdrop:
      typeof v["lessonBackdrop"] === "string"
        ? v["lessonBackdrop"]
        : fallback.lessonBackdrop,
  };
}

/**
 * 校验一段未知输入是否是可导入的备份信封。
 *
 * 前向兼容策略（重要，双端一致）：
 *   - version 是"数据格式代号"，只增不改语义；
 *   - version > BACKUP_VERSION（未来版本导给旧客户端）：不拒收——
 *     未知字段直接忽略，已知字段照常读取；v1 字段承诺永不改类型/语义，
 *     所以旧端读新档最多丢失新功能数据，不会损坏；
 *   - version < 1 或非正整数：视为结构损坏，拒收；
 *   - data 内任何未知字段一律忽略（不报错），缺失字段补默认值。
 */
export function validateBackup(input: unknown): BackupValidationResult {
  const fatal: string[] = [];

  if (!isRecord(input)) {
    return { ok: false, errors: ["备份内容不是 JSON 对象"] };
  }
  if (input["schema"] !== BACKUP_SCHEMA) {
    fatal.push(`schema 不是 "${BACKUP_SCHEMA}"，这不是本应用的备份文件`);
  }
  const version = input["version"];
  if (!isFiniteNumber(version) || !Number.isInteger(version) || version < 1) {
    fatal.push("version 缺失或不是正整数");
  }
  const rawData = input["data"];
  if (!isRecord(rawData)) {
    fatal.push("data 缺失或不是对象");
  }
  if (fatal.length > 0) {
    return { ok: false, errors: fatal };
  }

  const log: string[] = [];
  const d = rawData as Record<string, unknown>;

  // 平台是元数据，坏值不致命
  const platformRaw = input["platform"];
  const platform: BackupPlatform =
    platformRaw === "ios" || platformRaw === "web" ? platformRaw : "web";
  if (platform !== platformRaw) {
    log.push('platform 非法，已按 "web" 处理');
  }
  const exportedAt =
    typeof input["exportedAt"] === "string" ? input["exportedAt"] : "";
  if (exportedAt === "" && input["exportedAt"] !== undefined) {
    log.push("exportedAt 不是字符串，已置空");
  }

  const data: BackupData = {
    xp: readNonNegNumber(d, "xp", 0, log),
    streak: readNonNegNumber(d, "streak", 0, log),
    lastActiveDate: readString(d, "lastActiveDate", "", log),
    streakFreezes: readNonNegNumber(d, "streakFreezes", INITIAL_FREEZES, log),
    gems: readNonNegNumber(d, "gems", 0, log),
    lifetimeGems: readNonNegNumber(d, "lifetimeGems", 0, log),
    hearts: readNonNegNumber(d, "hearts", MAX_HEARTS, log),
    dailyGoal: readNonNegNumber(d, "dailyGoal", DEFAULT_DAILY_GOAL, log),
    completedLessons: readCompletedLessons(d, log),
    completedReadings: readStringRecord(d, "completedReadings", log),
    mistakesBank: readMistakesBank(d, log),
    claimedChests: readFlagRecord(d, "claimedChests", log),
    claimedStreakRewards: readFlagRecord(d, "claimedStreakRewards", log),
    lastDailyRewardDate: readString(d, "lastDailyRewardDate", "", log),
    unlockedAchievements: readFlagRecord(d, "unlockedAchievements", log),
    ownedCosmetics: readFlagRecord(d, "ownedCosmetics", log),
    equipped: readEquipped(d, log),
    xpHistory: readNumberRecord(d, "xpHistory", log),
  };

  // 可选字段：给了才带上
  const joinedDate = readOptionalString(d, "joinedDate", log);
  if (joinedDate !== undefined) data.joinedDate = joinedDate;
  if (d["perfectedLessons"] !== undefined) {
    data.perfectedLessons = readFlagRecord(d, "perfectedLessons", log);
  }
  if (d["claimedAchievements"] !== undefined) {
    data.claimedAchievements = readFlagRecord(d, "claimedAchievements", log);
  }
  const leagueTier = readOptionalString(d, "leagueTier", log);
  if (leagueTier !== undefined) data.leagueTier = leagueTier;
  const leagueWeekKey = readOptionalString(d, "leagueWeekKey", log);
  if (leagueWeekKey !== undefined) data.leagueWeekKey = leagueWeekKey;

  return {
    ok: true,
    data: {
      schema: BACKUP_SCHEMA,
      version: version as number,
      exportedAt,
      platform,
      data,
    },
    errors: log,
  };
}
