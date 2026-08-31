import { promises as fs } from "fs";
import path from "path";
import { notFound } from "next/navigation";
import type { BookPassages, SiteIndex } from "@/types";
import { PassageReader } from "@/components/PassageReader";

async function getIndex(): Promise<SiteIndex | null> {
  try {
    const p = path.join(process.cwd(), "public", "data", "index.json");
    return JSON.parse(await fs.readFile(p, "utf-8"));
  } catch {
    return null;
  }
}

async function getPassages(bookId: string): Promise<BookPassages | null> {
  const p = path.join(
    process.cwd(),
    "public",
    "data",
    "books",
    bookId,
    "passages.json",
  );
  try {
    return JSON.parse(await fs.readFile(p, "utf-8"));
  } catch {
    return null;
  }
}

export async function generateStaticParams() {
  const index = await getIndex();
  if (!index) return [];
  const params: { book: string; passage: string }[] = [];
  for (const book of index.books) {
    if (!book.hasPassages) continue;
    const doc = await getPassages(book.id);
    if (!doc) continue;
    for (const p of doc.passages) {
      params.push({ book: book.id, passage: p.id });
    }
  }
  return params;
}

export default async function ReadingPage({
  params,
}: {
  params: Promise<{ book: string; passage: string }>;
}) {
  const { book: bookId, passage: passageId } = await params;
  const doc = await getPassages(bookId);
  if (!doc) notFound();
  const idx = doc.passages.findIndex(p => p.id === passageId);
  if (idx < 0) notFound();
  const passage = doc.passages[idx];
  const prev = idx > 0 ? doc.passages[idx - 1] : null;
  const next = idx < doc.passages.length - 1 ? doc.passages[idx + 1] : null;

  return (
    <PassageReader
      passage={passage}
      backHref={`/reading/${bookId}/`}
      prevHref={prev ? `/reading/${bookId}/${prev.id}/` : null}
      prevTitle={prev?.title ?? null}
      nextHref={next ? `/reading/${bookId}/${next.id}/` : null}
      nextTitle={next?.title ?? null}
    />
  );
}
