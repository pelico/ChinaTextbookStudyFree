"use client";

/**
 * RightRail —— 桌面端右侧 rail（仿 Duolingo web）
 *
 * 顺序：StatsBar HUD / DailyQuestsCard / LeaderboardTeaserCard / CreateProfilePromptCard / 页脚
 */

import { useEffect, useState } from "react";
import { StatsBar } from "@/components/StatsBar";
import { useProgressStore } from "@/store/progress";
import { Lightning, Trophy } from "@/components/icons";

export function RightRail() {
  return (
    <div className="flex flex-col gap-4 w-full">
      <div className="flex justify-end">
        <StatsBar compact />
      </div>
      <LeaderboardTeaserCard />
      <DailyQuestsCard />
      <CreateProfilePromptCard />
      <FooterLinks />
    </div>
  );
}

function CardShell({ children }: { children: React.ReactNode }) {
  return (
    <div
      className="rounded-2xl border-2 border-bg-softer bg-white p-4"
      style={{ boxShadow: "0 2px 0 0 #e5e5e5" }}
    >
      {children}
    </div>
  );
}

function LeaderboardTeaserCard() {
  const completed = useProgressStore(s => Object.keys(s.completedLessons).length);
  const NEED = 10;
  const remaining = Math.max(0, NEED - completed);
  if (remaining === 0) return null;
  return (
    <CardShell>
      <div className="flex items-center gap-3">
        <div className="w-10 h-10 rounded-xl bg-bg-soft border-2 border-bg-softer flex items-center justify-center shrink-0">
          <Trophy className="w-5 h-5 text-ink-softer" />
        </div>
        <div className="flex-1 min-w-0">
          <div className="text-sm font-extrabold text-ink">解锁排行榜</div>
          <div className="text-xs text-ink-light mt-0.5">还差 {remaining} 节课</div>
        </div>
      </div>
    </CardShell>
  );
}

function DailyQuestsCard() {
  const todayXp = useProgressStore(s => s.todayXp);
  const target = useProgressStore(s => s.dailyGoal);
  const lastXpDate = useProgressStore(s => s.lastXpDate);

  const [hydrated, setHydrated] = useState(false);
  useEffect(() => setHydrated(true), []);

  // 分钟级 tick：驱动"距刷新还有 N 小时/分钟"倒计时
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 60 * 1000);
    return () => clearInterval(t);
  }, []);

  // 与 DailyGoalRing 同口径：lastXpDate 非今日则今日 XP 显示为 0
  const displayXp = hydrated && lastXpDate === todayStr() ? todayXp : 0;
  const pct = Math.min(100, Math.round((displayXp / target) * 100));

  return (
    <CardShell>
      <div className="flex items-baseline justify-between mb-2">
        <div className="text-sm font-extrabold text-ink">每日目标</div>
        {/* SSR 首帧没有可靠的本地时间，hydrate 后再显示倒计时，避免水合不一致 */}
        {hydrated && (
          <div className="text-[10px] font-extrabold text-ink-softer">
            距刷新还有 {formatUntilMidnight(now)}
          </div>
        )}
      </div>
      <div className="flex items-center gap-3">
        <div className="w-10 h-10 rounded-xl bg-warning/20 flex items-center justify-center shrink-0">
          <Lightning className="w-5 h-5 text-warning" />
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2">
            <div className="flex-1 h-3 rounded-full bg-bg-softer overflow-hidden">
              <div
                className="h-full bg-warning rounded-full transition-all"
                style={{ width: `${pct}%` }}
              />
            </div>
            <div className="text-[10px] font-extrabold text-ink-softer tabular-nums shrink-0">
              {Math.min(displayXp, target)}/{target}
            </div>
          </div>
        </div>
      </div>
    </CardShell>
  );
}

/** 本地时区的今天，YYYY-MM-DD（与 store / DailyGoalRing 同实现） */
function todayStr(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

/** 到今晚午夜的剩余时间文案：≥1 小时显示"N 小时"，否则显示"N 分钟" */
function formatUntilMidnight(now: number): string {
  const d = new Date(now);
  const midnight = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1);
  const ms = Math.max(0, midnight.getTime() - now);
  const hours = Math.floor(ms / (60 * 60 * 1000));
  if (hours >= 1) return `${hours} 小时`;
  const minutes = Math.max(1, Math.ceil(ms / (60 * 1000)));
  return `${minutes} 分钟`;
}

function CreateProfilePromptCard() {
  return null;
}

function FooterLinks() {
  return null;
}
