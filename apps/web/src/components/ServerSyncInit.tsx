"use client";

import { useEffect } from "react";
import { initServerSync } from "@/store/progress";

export function ServerSyncInit() {
  useEffect(() => {
    initServerSync();
  }, []);
  return null;
}
