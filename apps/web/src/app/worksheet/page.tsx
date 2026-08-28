import { promises as fs } from "fs";
import path from "path";
import type { SiteIndex, SubjectId, Outline } from "@/types";
import { SUBJECTS } from "@/lib/subjects";
import { WorksheetClient } from "./WorksheetClient";
import type { BookInfo } from "@/lib/worksheet";

async function getIndex(): Promise<SiteIndex> {
  const p = path.join(process.cwd(), "public", "data", "index.json");
  return JSON.parse(await fs.readFile(p, "utf-8"));
}

async function getOutline(bookId: string): Promise<Outline | null> {
  const p = path.join(process.cwd(), "public", "data", "books", bookId, "outline.json");
  try {
    return JSON.parse(await fs.readFile(p, "utf-8"));
  } catch {
    return null;
  }
}

export default async function WorksheetPage() {
  const index = await getIndex();
  const books: BookInfo[] = [];

  for (const b of index.books) {
    const subject: SubjectId = b.subject ?? "math";
    const outline = await getOutline(b.id);
    if (!outline) continue;
    books.push({
      id: b.id,
      subject,
      grade: b.grade,
      semester: b.semester,
      textbookName: b.textbookName,
      subjectName: SUBJECTS[subject]?.label ?? subject,
      outline,
    });
  }

  books.sort((a, b) => {
    if (a.subject !== b.subject) return a.subject.localeCompare(b.subject);
    if (a.grade !== b.grade) return a.grade - b.grade;
    return a.semester === "up" ? -1 : 1;
  });

  return <WorksheetClient books={books} />;
}
