"use client";

const TOKEN_KEY = "csf-parent-token";

export function getParentToken(): string | null {
  if (typeof window === "undefined") return null;
  return sessionStorage.getItem(TOKEN_KEY);
}

export function clearParentToken() {
  if (typeof window === "undefined") return;
  sessionStorage.removeItem(TOKEN_KEY);
}

export async function getParentStatus(): Promise<{ is_setup: boolean }> {
  const res = await fetch("/api/custom/parent/status");
  if (!res.ok) return { is_setup: false };
  return res.json();
}

export async function setupParent(
  password: string,
  settings?: {
    ai_api_key?: string;
    ai_base_url?: string;
    ai_model?: string;
    daily_limit_ms?: number;
    session_limit_ms?: number;
  }
): Promise<boolean> {
  const res = await fetch("/api/custom/parent/setup", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ password, ...settings }),
  });
  if (!res.ok) return false;
  const { token } = await res.json();
  sessionStorage.setItem(TOKEN_KEY, token);
  return true;
}

export async function verifyParentPassword(password: string): Promise<boolean> {
  const res = await fetch("/api/custom/parent/verify", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ password }),
  });
  if (!res.ok) return false;
  const { token } = await res.json();
  sessionStorage.setItem(TOKEN_KEY, token);
  return true;
}

export async function getParentSettings(): Promise<{
  is_setup: boolean;
  ai_key_set: boolean;
  ai_base_url: string;
  ai_model: string;
  daily_limit_ms: number;
  session_limit_ms: number;
} | null> {
  const token = getParentToken();
  if (!token) return null;
  const res = await fetch("/api/custom/parent/settings", {
    headers: { "X-Parent-Auth": token },
  });
  if (!res.ok) return null;
  return res.json();
}

export async function updateParentSettings(settings: {
  ai_api_key?: string;
  ai_base_url?: string;
  ai_model?: string;
  daily_limit_ms?: number;
  session_limit_ms?: number;
}): Promise<boolean> {
  const token = getParentToken();
  if (!token) return false;
  const res = await fetch("/api/custom/parent/settings", {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Parent-Auth": token },
    body: JSON.stringify(settings),
  });
  return res.ok;
}

export async function getPublicSettings(): Promise<{
  daily_limit_ms: number;
  session_limit_ms: number;
}> {
  try {
    const res = await fetch("/api/custom/parent/public-settings");
    if (!res.ok) return { daily_limit_ms: 0, session_limit_ms: 0 };
    return res.json();
  } catch {
    return { daily_limit_ms: 0, session_limit_ms: 0 };
  }
}

export async function requireParentAuth(action: string): Promise<boolean> {
  if (getParentToken()) return true;
  const password = window.prompt(`此操作需要家长授权（${action}）\n请输入家长密码：`);
  if (!password) return false;
  return verifyParentPassword(password);
}
