"use client";

const ACTIVE_KID_KEY = "csf-active-kid";

export interface Kid {
  id: string;
  name: string;
  avatar: string;
  sort_order: number;
  created_at: string;
}

export function getActiveKidId(): string {
  if (typeof window === "undefined") return "default";
  return localStorage.getItem(ACTIVE_KID_KEY) || "default";
}

export function setActiveKidId(kidId: string) {
  if (typeof window === "undefined") return;
  localStorage.setItem(ACTIVE_KID_KEY, kidId);
  window.dispatchEvent(new CustomEvent("kid-changed", { detail: kidId }));
}

export function getStorageKey(baseKey: string): string {
  const kidId = getActiveKidId();
  return kidId === "default" ? baseKey : `${baseKey}-${kidId}`;
}

export async function listKids(): Promise<Kid[]> {
  try {
    const res = await fetch("/api/custom/kids");
    if (!res.ok) return [];
    const data = await res.json();
    return data.kids || [];
  } catch {
    return [];
  }
}

export async function createKid(name: string, avatar = "default"): Promise<Kid | null> {
  const token = sessionStorage.getItem("csf-parent-token");
  if (!token) return null;
  const res = await fetch("/api/custom/kids", {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Parent-Auth": token },
    body: JSON.stringify({ name, avatar }),
  });
  if (!res.ok) return null;
  return res.json();
}

export async function updateKid(kidId: string, name: string, avatar?: string): Promise<boolean> {
  const token = sessionStorage.getItem("csf-parent-token");
  if (!token) return false;
  const res = await fetch(`/api/custom/kids/${kidId}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Parent-Auth": token },
    body: JSON.stringify({ name, avatar }),
  });
  return res.ok;
}

export async function deleteKid(kidId: string): Promise<boolean> {
  const token = sessionStorage.getItem("csf-parent-token");
  if (!token) return false;
  const res = await fetch(`/api/custom/kids/${kidId}`, {
    method: "DELETE",
    headers: { "X-Parent-Auth": token },
  });
  return res.ok;
}
