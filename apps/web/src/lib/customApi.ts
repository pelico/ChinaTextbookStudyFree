"use client";

export function navigate(path: string) {
  window.history.pushState({}, "", path);
  window.dispatchEvent(new PopStateEvent("popstate"));
}

function getAIKey(): string {
  if (typeof window === "undefined") return "";
  try {
    const raw = localStorage.getItem("csf-worksheet-ai-config");
    if (raw) return (JSON.parse(raw).apiKey || "").trim();
  } catch {}
  return "";
}

function authHeaders(): Record<string, string> {
  const key = getAIKey();
  return key ? { "X-AI-Key": key } : {};
}

export async function apiGet<T = any>(path: string): Promise<T> {
  const res = await fetch(`/api/custom/${path}`, { headers: authHeaders() });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error || "请求失败");
  return data;
}

export async function apiPost<T = any>(path: string, body?: unknown): Promise<T> {
  const res = await fetch(`/api/custom/${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...authHeaders() },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error || "请求失败");
  return data;
}

export async function apiDelete(path: string): Promise<void> {
  const res = await fetch(`/api/custom/${path}`, {
    method: "DELETE",
    headers: authHeaders(),
  });
  if (!res.ok) throw new Error((await res.json()).error || "删除失败");
}

export interface FolderInfo {
  name: string;
  path: string;
  image_count: number;
}

export async function listFolders(): Promise<FolderInfo[]> {
  const data = await apiGet<{ folders: FolderInfo[] }>("folders");
  return data.folders;
}

export async function createBookFromFolder(
  title: string, subject: string, grade: number,
  semester: string, folderPath: string
): Promise<CustomBook & { total_pages?: number; batches?: number }> {
  return apiPost("books/from-folder", { title, subject, grade, semester, folder_path: folderPath });
}

export interface PageImage {
  filename: string;
  page_number: number;
  kp_id: string | null;
  unit_id: string | null;
  sort_idx: number;
}

export function imageUrl(bookId: string, filename: string): string {
  return `/custom-images/${bookId}/${filename}`;
}

export interface ReadPage {
  page_number: number;
  filename: string;
  kp_id: string | null;
  unit_id: string | null;
  text_content: string;
  has_text: boolean;
}

export interface BookReadData {
  book: {
    id: string;
    title: string;
    subject: string;
    grade: number;
    semester: string;
  };
  pages: ReadPage[];
  units: Array<{ id: string; unit_number: number; title: string }>;
  has_text: boolean;
}

export async function getBookRead(bookId: string): Promise<BookReadData> {
  return apiGet(`books/${bookId}/read`);
}

export async function extractBookText(bookId: string, force = false): Promise<{ status: string; message?: string }> {
  return apiPost(`books/${bookId}/extract-text`, { force });
}

export async function getExtractStatus(bookId: string): Promise<{ status: string; message?: string; result?: { total: number; extracted: number; skipped: number } }> {
  return apiGet(`books/${bookId}/extract-status`);
}

export async function updatePageText(
  bookId: string,
  pageNumber: number,
  text: string
): Promise<{ success: boolean }> {
  return apiPost(`books/${bookId}/pages/${pageNumber}/text`, { text });
}

export interface TextStatus {
  total_pages: number;
  text_pages: number;
  has_text: boolean;
  has_outline: boolean;
}

export async function getTextStatus(bookId: string): Promise<TextStatus> {
  return apiGet(`books/${bookId}/text-status`);
}

export async function generateOutlineFromTexts(bookId: string): Promise<CustomBook> {
  return apiPost(`books/${bookId}/generate-outline`);
}

export function compressImage(file: File, maxDim = 1080, quality = 0.7): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const img = new Image();
      img.onload = () => {
        const scale = Math.min(1, maxDim / Math.max(img.width, img.height));
        const w = Math.round(img.width * scale);
        const h = Math.round(img.height * scale);
        const canvas = document.createElement("canvas");
        canvas.width = w;
        canvas.height = h;
        const ctx = canvas.getContext("2d")!;
        ctx.drawImage(img, 0, 0, w, h);
        resolve(canvas.toDataURL("image/jpeg", quality));
      };
      img.onerror = reject;
      img.src = reader.result as string;
    };
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}

export interface CustomBook {
  id: string;
  title: string;
  subject: string;
  grade: number;
  semester: string;
  created_at: string;
  units?: Unit[];
}

export interface Unit {
  id: string;
  unit_number: number;
  title: string;
  knowledge_points: KnowledgePoint[];
}

export interface KnowledgePoint {
  id: string;
  name: string;
  description: string;
  difficulty: number;
  question_types: string[];
}

export interface QuestionSet {
  version: number;
  questions: any[];
  generated_at: string;
}


