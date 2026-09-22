"use client";

import { useState, useEffect } from "react";
import {
  getActiveKidId, listKidsCached, type Kid,
} from "@/lib/kidProfile";
import { switchKid } from "@/store/progress";

const AVATARS = ["🦊", "🐼", "🐱", "🐰", "🐯", "🦁", "🐨", "🐸"];

export function KidPicker() {
  const [kids, setKids] = useState<Kid[]>([]);
  const [activeKid, setActiveKid] = useState(getActiveKidId());
  const [showPicker, setShowPicker] = useState(false);
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    loadKids();
    const handler = () => setActiveKid(getActiveKidId());
    window.addEventListener("kid-changed", handler);
    return () => window.removeEventListener("kid-changed", handler);
  }, []);

  async function loadKids() {
    // 用缓存版拉取名单：服务端连不上/离线时也能拿到账号，避免回退 default 访客桶
    const k = await listKidsCached();
    setKids(k);

    const active = getActiveKidId();

    if (k.length === 0) {
      // 没有任何学习者 → 维持 default 访客，不打扰
      setShowPicker(false);
      setLoaded(true);
      return;
    }

    // 「是否已确认身份」：当前 csf-active-kid 是否对应一个名单里真实存在的学习者。
    // 同机切换场景天然满足 —— csf-active-kid 就是这台机器最后一次选的账号，直接恢复。
    const activeIsReal = k.some(kid => kid.id === active);
    if (!activeIsReal) {
      // 未确认身份：当前是 default 或指向已删除账号 → 需要补一次确认，别默默用访客桶
      if (k.length === 1) {
        // 只有一个账号 → 自动选中并持久化（switchKid 写 csf-active-kid 后 reload）
        switchKid(k[0].id);
        return;
      }
      // 多个账号、无已确认身份 → 强制弹选择器，让用户明确挑一个
      setShowPicker(true);
    }

    setLoaded(true);
  }

  // Not loaded yet or no kids configured — don't show picker
  if (!loaded || kids.length === 0) return null;

  const currentKid = kids.find(k => k.id === activeKid);
  if (!currentKid && activeKid === "default") {
    // No kid selected and no default — show minimal picker
  }

  function pickKid(kidId: string) {
    setActiveKid(kidId);
    setShowPicker(false);
    // Reload page to rehydrate store with new kid's data.
    // The store-side switchKid ensures the *previous* kid's local state is
    // pushed to the server *before* csf-active-kid flips and reload happens,
    // closing the gem-contamination race (old fix had store data leak into
    // the new kid's row_id).
    switchKid(kidId);
  }

  if (showPicker) {
    return (
      <div className="fixed inset-0 z-[100] bg-black/50 flex items-center justify-center p-4" onClick={() => setShowPicker(false)}>
        <div
          className="bg-white rounded-3xl p-6 max-w-sm w-full shadow-2xl"
          onClick={e => e.stopPropagation()}
        >
          <h2 className="text-lg font-extrabold text-center mb-4 text-ink">选择学习者</h2>
          <div className="space-y-2">
            {kids.map(kid => {
              const active = kid.id === activeKid;
              const avatar = AVATARS[(kid.sort_order || 0) % AVATARS.length];
              return (
                <button
                  key={kid.id}
                  onClick={() => pickKid(kid.id)}
                  className={`w-full flex items-center gap-3 p-3 rounded-2xl border-2 transition-colors ${
                    active
                      ? "border-primary bg-primary/5"
                      : "border-bg-softer hover:border-primary/40"
                  }`}
                >
                  <span className="text-3xl">{avatar}</span>
                  <span className="flex-1 text-left font-bold text-ink">{kid.name}</span>
                  {active && <span className="text-primary text-sm">✓</span>}
                </button>
              );
            })}
          </div>
          <button
            onClick={() => setShowPicker(false)}
            className="w-full mt-4 h-9 rounded-xl bg-bg-soft text-ink-light text-sm font-bold"
          >
            取消
          </button>
        </div>
      </div>
    );
  }

  return (
    <button
      onClick={() => setShowPicker(true)}
      className="no-print fixed right-4 z-50 h-12 w-12 rounded-full bg-primary text-white shadow-lg flex items-center justify-center text-xl hover:scale-105 transition-transform"
      style={{ bottom: "calc(3.5rem + max(env(safe-area-inset-bottom), 0px) + 0.5rem)" }}
      title="切换学习者"
    >
      {currentKid ? AVATARS[(currentKid.sort_order || 0) % AVATARS.length] : "👤"}
    </button>
  );
}
