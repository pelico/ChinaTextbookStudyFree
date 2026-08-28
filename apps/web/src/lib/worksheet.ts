"use client";

import type { Outline, SubjectId, Unit } from "@cstf/core";

// ============================================================
// 类型
// ============================================================

export interface WorksheetQuestion {
  type: "true_false" | "choice" | "fill_blank_text" | "short_answer";
  score: number;
  difficulty: number;
  knowledge_point: string;
  question: string;
  options: string[];
  answer: string;
  explanation: string;
}

export interface WorksheetConfig {
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
}

export interface AIConfig {
  baseURL: string;
  apiKey: string;
  model: string;
}

export const DEFAULT_AI_CONFIG: AIConfig = {
  baseURL: "https://api.openai.com/v1",
  apiKey: "",
  model: "gpt-4o-mini",
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

function buildSystemPrompt(): string {
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
  if (config.questionTypes.true_false > 0)
    parts.push(`判断题 ${config.questionTypes.true_false} 道（每道2分）`);
  if (config.questionTypes.choice > 0)
    parts.push(`选择题 ${config.questionTypes.choice} 道（每道5分，4个选项）`);
  if (config.questionTypes.fill_blank_text > 0)
    parts.push(`填空题 ${config.questionTypes.fill_blank_text} 道（每空2分）`);
  if (config.questionTypes.short_answer > 0)
    parts.push(`简答题 ${config.questionTypes.short_answer} 道（每道8分）`);

  return `学科：${subjectLabel}
教材：${config.textbookName}
单元：${config.unitNumbers.length === 0 ? "全部单元" : config.unitNumbers.map(n => `第${n}单元`).join("、")}

知识点范围：
${unitTexts}

请生成以下题目：
${parts.join("\n")}

要求：
- 题目覆盖以上知识点
- 难度不超过 ${config.difficultyMax} 级
- 只输出 JSON 数组，不要包含 markdown 代码块标记或任何其他文字`;
}

// ============================================================
// AI 调用
// ============================================================

export async function generateWorksheet(
  config: WorksheetConfig,
  aiConfig: AIConfig,
  units: Unit[],
): Promise<WorksheetQuestion[]> {
  const system = buildSystemPrompt();
  const user = buildUserPrompt(config, units);

  const url = aiConfig.baseURL.replace(/\/+$/, "") + "/chat/completions";

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
    }),
  });

  if (!res.ok) {
    const text = await res.text().catch(() => "");
    throw new Error(`AI 接口错误 (${res.status}): ${text.slice(0, 200)}`);
  }

  const data = await res.json();
  const content = data?.choices?.[0]?.message?.content ?? "";

  return parseAIResponse(content);
}

function parseAIResponse(content: string): WorksheetQuestion[] {
  let text = content.trim();
  if (text.startsWith("```")) {
    text = text.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "");
  }
  const arr = JSON.parse(text);
  if (!Array.isArray(arr)) throw new Error("AI 返回格式错误：不是数组");

  const validTypes = ["true_false", "choice", "fill_blank_text", "short_answer"] as const;

  return arr.map((q: Record<string, unknown>, i: number) => {
    const rawType = (q.type as string) || "short_answer";
    return {
      type: (validTypes as readonly string[]).includes(rawType) ? rawType : "short_answer",
      score: Number(q.score) || 2,
      difficulty: Number(q.difficulty) || 1,
      knowledge_point: (q.knowledge_point as string) || "",
      question: (q.question as string) || "",
      options: Array.isArray(q.options) ? (q.options as string[]) : [],
      answer: (q.answer as string) || "",
      explanation: (q.explanation as string) || "",
      id: i + 1,
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
