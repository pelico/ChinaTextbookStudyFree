"use client";

import { useState, useEffect, useCallback } from "react";
import { navigate } from "@/lib/customApi";
import { CustomHome } from "./CustomHome";
import { CustomCreate } from "./CustomCreate";
import { CustomBook } from "./CustomBook";
import { CustomLesson } from "./CustomLesson";
import { CustomFolderCreate } from "./CustomFolderCreate";
import { CustomReader } from "./CustomReader";
import { CustomExamHome } from "./CustomExamHome";
import { CustomExamCreate } from "./CustomExamCreate";
import { CustomExamDetail } from "./CustomExamDetail";

export default function CustomPage() {
  const [path, setPath] = useState<string>("");

  useEffect(() => {
    setPath(window.location.pathname);
    const onPop = () => setPath(window.location.pathname);
    window.addEventListener("popstate", onPop);
    return () => window.removeEventListener("popstate", onPop);
  }, []);

  const parts = path.replace(/\/+$/, "").split("/").filter(Boolean);

  if (parts.length <= 1) return <CustomHome />;
  if (parts[1] === "create") return <CustomCreate />;
  if (parts[1] === "folder-create") return <CustomFolderCreate />;
  if (parts[1] === "book" && parts.length === 3) return <CustomBook bookId={parts[2]} />;
  if (parts[1] === "book" && parts.length === 4 && parts[3] === "read") return <CustomReader bookId={parts[2]} />;
  if (parts[1] === "book" && parts.length === 4) return <CustomLesson bookId={parts[2]} lessonId={parts[3]} />;
  if (parts[1] === "exams") return <CustomExamHome />;
  if (parts[1] === "exam" && parts.length === 3 && parts[2] === "create") return <CustomExamCreate />;
  if (parts[1] === "exam" && parts.length === 3) return <CustomExamDetail examId={parts[2]} />;
  return <CustomHome />;
}
