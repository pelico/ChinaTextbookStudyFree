import { promises as fs } from "fs";
import path from "path";
import { AppShell } from "@/components/layout/AppShell";
import { InnerHeader } from "@/components/InnerHeader";
import { SoundLink } from "@/components/SoundLink";
import { BookOpen, Bookmark, Volume } from "@/components/icons";
import type { SiteIndex, Book } from "@/types";
import { SUBJECTS } from "@/lib/subjects";

async function getIndex(): Promise<SiteIndex> {
  const p = path.join(process.cwd(), "public", "data", "index.json");
  return JSON.parse(await fs.readFile(p, "utf-8"));
}

const GRADE_LABELS: Record<number, string> = {
  1: "一年级",
  2: "二年级",
  3: "三年级",
  4: "四年级",
  5: "五年级",
  6: "六年级",
};

const SEMESTER_LABELS: Record<string, string> = {
  up: "上册",
  down: "下册",
};

export default async function ReadingHomePage() {
  const index = await getIndex();

  const passageBooks = index.books.filter(b => b.hasPassages);
  const storyBooks = index.books.filter(b => b.hasStories);

  // 按年级排序
  const sortedPassage = [...passageBooks].sort((a, b) => {
    if (a.grade !== b.grade) return a.grade - b.grade;
    return a.semester === "up" ? -1 : 1;
  });
  const sortedStories = [...storyBooks].sort((a, b) => {
    if (a.grade !== b.grade) return a.grade - b.grade;
    return a.semester === "up" ? -1 : 1;
  });

  return (
    <AppShell>
      <main className="max-w-3xl mx-auto px-4 md:px-6 py-6">
        <InnerHeader title="阅读中心" subtitle="课文听读 · 故事阅读" backHref="/" />

        {/* 课文听读 */}
        <section className="mt-8">
          <div className="flex items-center gap-2 mb-4">
            <div className="w-8 h-8 rounded-xl bg-primary/10 text-primary inline-flex items-center justify-center">
              <Volume className="w-4 h-4" />
            </div>
            <h2 className="text-lg font-extrabold text-ink">课文听读</h2>
            <span className="text-xs text-ink-light ml-1">
              {sortedPassage.length} 本教材
            </span>
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            {sortedPassage.map(book => (
              <SoundLink
                key={book.id}
                href={`/reading/${book.id}/`}
                className="block rounded-2xl bg-white border-2 border-bg-softer p-4 hover:border-primary/40 hover:bg-primary/[0.02] transition-colors"
              >
                <div className="flex items-center gap-3">
                  <div className="shrink-0 w-11 h-11 rounded-2xl bg-primary/10 text-primary inline-flex items-center justify-center">
                    <BookOpen className="w-5 h-5" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="text-sm font-extrabold text-ink truncate">
                      {(SUBJECTS[book.subject]?.label ?? book.subject) + GRADE_LABELS[book.grade] + (SEMESTER_LABELS[book.semester] || "")}
                    </div>
                    <div className="text-xs text-ink-light mt-0.5 truncate">
                      {book.textbookName}
                    </div>
                  </div>
                </div>
              </SoundLink>
            ))}
          </div>
        </section>

        {/* 故事阅读 */}
        <section className="mt-10">
          <div className="flex items-center gap-2 mb-4">
            <div className="w-8 h-8 rounded-xl bg-gold/15 text-gold inline-flex items-center justify-center">
              <Bookmark className="w-4 h-4" />
            </div>
            <h2 className="text-lg font-extrabold text-ink">故事阅读</h2>
            <span className="text-xs text-ink-light ml-1">
              {sortedStories.length} 本教材
            </span>
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            {sortedStories.map(book => (
              <SoundLink
                key={book.id}
                href={`/stories/${book.id}/`}
                className="block rounded-2xl bg-white border-2 border-bg-softer p-4 hover:border-gold/40 hover:bg-gold/[0.05] transition-colors"
              >
                <div className="flex items-center gap-3">
                  <div className="shrink-0 w-11 h-11 rounded-2xl bg-gold/15 text-gold inline-flex items-center justify-center">
                    <BookMarked className="w-5 h-5" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="text-sm font-extrabold text-ink truncate">
                      {(SUBJECTS[book.subject]?.label ?? book.subject) + GRADE_LABELS[book.grade] + (SEMESTER_LABELS[book.semester] || "")}
                    </div>
                    <div className="text-xs text-ink-light mt-0.5 truncate">
                      {book.textbookName}
                    </div>
                  </div>
                </div>
              </SoundLink>
            ))}
          </div>
        </section>
      </main>
    </AppShell>
  );
}
