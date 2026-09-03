"use client";

import type { Outline, SubjectId, Unit } from "@cstf/core";

// ============================================================
// 类型
// ============================================================

export interface WorksheetQuestion {
  type: string; // 题型标识，如 true_false / choice / fill_blank_text / calculation / application 等
  score: number;
  difficulty: number;
  knowledge_point: string;
  question: string;
  options: string[];
  answer: string;
  explanation: string;
  section_index?: number; // 属于第几大题（真题仿真模式用）
}

export interface ExamStructureSection {
  name: string;          // 大题名称，如"一、填空题"
  type: string;          // 题型标识（英文）
  count: number;         // 小题数量
  score_each: number;    // 每小题分值（0 表示分值不固定）
  total_score: number;   // 该大题总分
  description?: string;  // 题型说明
}

export interface ExamStructure {
  total_score: number;
  duration_minutes: number;
  sections: ExamStructureSection[];
}

export type WorksheetMode = "unit_practice" | "exam_simulation";

export interface WorksheetConfig {
  mode: WorksheetMode;
  subject: SubjectId;
  bookId: string;
  textbookName: string;
  unitNumbers: number[];
  questionTypes: {
    true_false: number;
    choice: number;
    fill_blank_text: number;
    short_answer: number;
  };
  difficultyMax: number;
  includeAnswerKey: boolean;
  examReference?: string;       // 真题文本内容（风格参考）
  examStructure?: ExamStructure; // 真题结构（真题仿真模式用）
}

export interface AIConfig {
  baseURL: string;
  apiKey: string;
  model: string;
}

export const DEFAULT_AI_CONFIG: AIConfig = {
  baseURL: "https://aiapi.fonken.net/v1",
  apiKey: "",
  model: "gemini-3.1-flash-lite",
};

const STORAGE_KEY = "csf-worksheet-ai-config";

export function loadAIConfig(): AIConfig {
  if (typeof window === "undefined") return DEFAULT_AI_CONFIG;
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) return { ...DEFAULT_AI_CONFIG, ...JSON.parse(raw) };
  } catch {}
  return DEFAULT_AI_CONFIG;
}

export function saveAIConfig(cfg: AIConfig) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(cfg));
  } catch {}
}

// ============================================================
// 题型标签
// ============================================================

export const QUESTION_TYPE_LABELS: Record<string, string> = {
  true_false: "判断题",
  choice: "选择题",
  fill_blank_text: "填空题",
  short_answer: "简答题",
  calculation: "计算题",
  application: "应用题",
  word_problem: "解决问题",
  reading_comprehension: "阅读理解",
  cloze: "完形填空",
  composition: "作文",
  matching: "连线题",
  fill_in_the_blanks: "选词填空",
  sentence: "句子练习",
};

export const SUBJECT_LABELS: Record<SubjectId, string> = {
  math: "数学",
  chinese: "语文",
  english: "英语",
  science: "科学",
};

// ============================================================
// AI Prompt 构建
// ============================================================

function buildSystemPrompt(mode: WorksheetMode): string {
  if (mode === "exam_simulation") {
    return `你是一位资深的中国小学教师，擅长模仿真实考试试卷的风格和难度出题。

要求：
1. 严格按照给定的试卷结构（大题顺序、题型、题数、分值）生成题目
2. 题目内容必须符合中国小学课程标准，适合对应年级学生的认知水平
3. 题目用词简洁清晰，小学生能独立理解题意
4. 每道题必须有明确的标准答案和解析
5. 选择题必须提供4个选项（A/B/C/D）
6. 判断题答案为"对"或"错"
7. 填空题用"____"表示空缺处
8. 计算题、应用题等需要写出解题过程
9. 允许综合题——一道题可以考察多个知识点
10. 整体难度要与真题相当，有梯度变化

输出格式为 JSON 数组，每个元素代表一道题，不要包含任何其他文字：
[
  {
    "section_index": 0,
    "type": "fill_blank",
    "score": 2,
    "difficulty": 1,
    "knowledge_point": "知识点名称",
    "question": "题目内容",
    "options": [],
    "answer": "答案",
    "explanation": "解析说明"
  }
]

注意：
- section_index 从 0 开始，对应试卷结构中的大题索引
- 每道题的 type 字段与大题的 type 保持一致
- 严格按大题顺序和题数生成，不能多也不能少`;
  }

  return `你是一位资深的中国小学教师，擅长根据课程标准和知识点设计练习试卷。

要求：
1. 题目内容必须符合中国小学课程标准，适合对应年级学生的认知水平
2. 题目用词简洁清晰，小学生能独立理解题意
3. 每道题必须有明确的标准答案和解析
4. 选择题必须提供4个选项（A/B/C/D）
5. 判断题答案为"对"或"错"
6. 填空题用"____"表示空缺处
7. 简答题答案要简明扼要

输出格式为 JSON 数组，不要包含任何其他文字：
[
  {
    "type": "true_false",
    "score": 2,
    "difficulty": 1,
    "knowledge_point": "知识点名称",
    "question": "题目内容",
    "options": [],
    "answer": "对",
    "explanation": "解析说明"
  },
  {
    "type": "choice",
    "score": 5,
    "difficulty": 2,
    "knowledge_point": "知识点名称",
    "question": "题目内容",
    "options": ["选项A", "选项B", "选项C", "选项D"],
    "answer": "选项B",
    "explanation": "解析说明"
  },
  {
    "type": "fill_blank_text",
    "score": 2,
    "difficulty": 1,
    "knowledge_point": "知识点名称",
    "question": "太阳从____方升起，从____方落下。",
    "options": [],
    "answer": "东;西",
    "explanation": "太阳东升西落是自然规律。"
  },
  {
    "type": "short_answer",
    "score": 8,
    "difficulty": 3,
    "knowledge_point": "知识点名称",
    "question": "请简述...",
    "options": [],
    "answer": "参考答案...",
    "explanation": "解析说明"
  }
]`;
}

function buildUserPrompt(
  config: WorksheetConfig,
  units: Unit[],
): string {
  const subjectLabel = SUBJECT_LABELS[config.subject] || config.subject;
  const unitTexts = units.map(u => {
    const kps = u.knowledge_points
      .filter(kp => kp.difficulty <= config.difficultyMax)
      .map(kp => `  - ${kp.name}：${kp.description}（难度${kp.difficulty}级，题型：${kp.question_types.join("、")}）`)
      .join("\n");
    return `第${u.unit_number}单元 ${u.title}\n${kps}`;
  }).join("\n\n");

  const parts: string[] = [];
  if (config.mode === "unit_practice") {
    if (config.questionTypes.true_false > 0)
      parts.push(`判断题 ${config.questionTypes.true_false} 道（每道2分）`);
    if (config.questionTypes.choice > 0)
      parts.push(`选择题 ${config.questionTypes.choice} 道（每道5分，4个选项）`);
    if (config.questionTypes.fill_blank_text > 0)
      parts.push(`填空题 ${config.questionTypes.fill_blank_text} 道（每空2分）`);
    if (config.questionTypes.short_answer > 0)
      parts.push(`简答题 ${config.questionTypes.short_answer} 道（每道8分）`);
  }

  let prompt = `学科：${subjectLabel}
教材：${config.textbookName}
单元：${config.unitNumbers.length === 0 ? "全部单元" : config.unitNumbers.map(n => `第${n}单元`).join("、")}

知识点范围（主要考察范围，真题仿真模式下允许跨单元综合题）：
${unitTexts}
`;

  if (config.mode === "exam_simulation" && config.examStructure) {
    const sectionsText = config.examStructure.sections
      .map((s, i) => `  ${i + 1}. ${s.name}（type: ${s.type}）：${s.count} 小题，每小题${s.score_each}分，共${s.total_score}分${s.description ? ` — ${s.description}` : ""}`)
      .join("\n");

    prompt += `
试卷结构（必须严格遵守，按顺序生成，题数和分值不能变）：
${sectionsText}

总分：${config.examStructure.total_score} 分
考试时长：${config.examStructure.duration_minutes} 分钟
`;
  }

  if (config.examReference) {
    prompt += `
参考真题试卷内容（请模仿其题型风格、难度和出题角度，但不要直接复制原题）：
${config.examReference}
`;
  }

  if (config.mode === "unit_practice") {
    prompt += `
请生成以下题目：
${parts.join("\n")}

要求：
- 题目覆盖以上知识点
- 难度不超过 ${config.difficultyMax} 级
${config.examReference ? "- 参考真题的风格和难度，但生成全新题目，不要直接复制原题\n" : ""}- 只输出 JSON 数组，不要包含 markdown 代码块标记或任何其他文字`;
  } else {
    prompt += `
要求：
- 严格按照上面的试卷结构生成题目，大题顺序、题型、题数、分值都不能变
- 每道题的 section_index 对应大题的索引（从 0 开始）
- 知识点以上面列出的范围为主，但允许出综合题，适当结合其他相关知识
- 整体难度与真题相当，要有梯度，从易到难
${config.examReference ? "- 参考真题的出题风格和难度水平，但生成全新题目，绝对不能直接复制原题\n" : ""}- 只输出 JSON 数组，不要包含 markdown 代码块标记或任何其他文字`;
  }

  return prompt;
}

// ============================================================
// AI 调用
// ============================================================

export async function generateWorksheet(
  config: WorksheetConfig,
  aiConfig: AIConfig,
  units: Unit[],
): Promise<WorksheetQuestion[]> {
  const system = buildSystemPrompt(config.mode);
  const user = buildUserPrompt(config, units);

  const baseUrl = aiConfig.baseURL.replace(/\/+$/, "");
  const isRelative = baseUrl.startsWith("/");
  const url = isRelative
    ? baseUrl + "/chat/completions"
    : baseUrl + "/chat/completions";

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 180000); // 真题仿真题量多，延长到 3 分钟

  try {
    const res = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${aiConfig.apiKey}`,
      },
      body: JSON.stringify({
        model: aiConfig.model,
        messages: [
          { role: "system", content: system },
          { role: "user", content: user },
        ],
        temperature: 0.7,
        stream: false,
      }),
      signal: controller.signal,
    });

    if (!res.ok) {
      const text = await res.text().catch(() => "");
      throw new Error(`AI 接口错误 (${res.status}): ${text.slice(0, 200)}`);
    }

    const contentType = res.headers.get("content-type") || "";
    if (!contentType.includes("application/json") && !contentType.includes("json")) {
      const text = await res.text().catch(() => "");
      const snippet = text.slice(0, 100).replace(/\s+/g, " ").trim();
      throw new Error(
        `AI 接口返回的不是 JSON（${contentType || "未知类型"}）。` +
        `请检查 Base URL 是否正确，应以 /v1 结尾，例如 https://api.openai.com/v1`,
      );
    }

    const data = await res.json();
    const content = data?.choices?.[0]?.message?.content ?? "";

    if (!content) {
      throw new Error("AI 未返回任何内容，请检查模型名称或 API Key 是否正确");
    }

    return parseAIResponse(content, config.mode);
  } catch (e) {
    if (e instanceof Error) {
      if (e.name === "AbortError") throw new Error("请求超时（3分钟），请检查网络或更换模型");
      if (e.message === "Failed to fetch") {
        throw new Error(
          isRelative
            ? "无法连接 AI 接口，请检查 Base URL 和 API Key"
            : "请求被浏览器拦截（CORS），请使用支持跨域的接口，或检查 Base URL 是否正确",
        );
      }
      // JSON 解析失败（接口返回 HTML 等非 JSON 内容）
      if (e.message.includes("Unexpected token") || e.message.includes("JSON")) {
        throw new Error(
          "AI 接口返回格式错误（不是 JSON）。请检查 Base URL 是否正确，" +
          "OpenAI 兼容接口的 Base URL 通常以 /v1 结尾，例如 https://api.openai.com/v1",
        );
      }
      throw e;
    }
    throw new Error("生成失败，请检查 AI 接口配置");
  } finally {
    clearTimeout(timeoutId);
  }
}

function parseAIResponse(content: string, mode: WorksheetMode = "unit_practice"): WorksheetQuestion[] {
  let text = content.trim();
  if (text.startsWith("```")) {
    text = text.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "");
  }
  const arr = JSON.parse(text);
  if (!Array.isArray(arr)) throw new Error("AI 返回格式错误：不是数组");

  const validLegacyTypes = ["true_false", "choice", "fill_blank_text", "short_answer"] as const;

  return arr.map((q: Record<string, unknown>, i: number) => {
    const rawType = (q.type as string) || "short_answer";
    // 兼容旧版：只有 4 种类型时做 fallback；真题仿真模式保留原始 type
    const type = mode === "unit_practice" && !(validLegacyTypes as readonly string[]).includes(rawType)
      ? "short_answer"
      : rawType;
    return {
      type,
      score: Number(q.score) || 2,
      difficulty: Number(q.difficulty) || 1,
      knowledge_point: (q.knowledge_point as string) || "",
      question: (q.question as string) || "",
      options: Array.isArray(q.options) ? (q.options as string[]) : [],
      answer: (q.answer as string) || "",
      explanation: (q.explanation as string) || "",
      section_index: q.section_index !== undefined ? Number(q.section_index) : undefined,
    } as WorksheetQuestion;
  });
}

// ============================================================
// 试卷数据辅助
// ============================================================

export interface BookInfo {
  id: string;
  subject: SubjectId;
  grade: number;
  semester: "up" | "down";
  textbookName: string;
  subjectName: string;
  outline: Outline;
  isCustom?: boolean;
}

export function groupBySubject(books: BookInfo[]) {
  const groups: Record<SubjectId, BookInfo[]> = {
    math: [],
    chinese: [],
    english: [],
    science: [],
  };
  for (const b of books) groups[b.subject]?.push(b);
  return groups;
}
