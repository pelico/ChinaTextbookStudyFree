"use client";

import { useState, useEffect } from "react";
import {
  getActiveKidId, setActiveKidId, listKids, type Kid,
} from "@/lib/kidProfile";

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
    const k = await listKids();
    setKids(k);
    setLoaded(true);
    if (k.length === 0 && getActiveKidId() === "default") {
      setShowPicker(false);
    }
  }

  // No kids configured yet — don't show picker
  if (loaded && kids.length === 0) return null;

  const currentKid = kids.find(k => k.id === activeKid);
  if (!currentKid && activeKid === "default") {
    // No kid selected and no default — show minimal picker
  }

  function pickKid(kidId: string) {
    setActiveKidId(kidId);
    setActiveKid(kidId);
    setShowPicker(false);
    // Reload page to rehydrate store with new kid's data
    window.location.reload();
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
      className="fixed bottom-4 right-4 z-50 h-12 w-12 rounded-full bg-primary text-white shadow-lg flex items-center justify-center text-xl hover:scale-105 transition-transform"
      title="切换学习者"
    >
      {currentKid ? AVATARS[(currentKid.sort_order || 0) % AVATARS.length] : "👤"}
    </button>
  );
}
