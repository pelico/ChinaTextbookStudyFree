"use client";

/**
 * RightRail —— 桌面端右侧 rail（仿 Duolingo web）
 *
 * 顺序：StatsBar HUD / LeaderboardTeaserCard / DailyQuestsPanel / 页脚
 * 每日目标环继续留在 profile；rail 上的目标卡已被「每日任务卡」取代。
 */

import { StatsBar } from "@/components/StatsBar";
import { DailyQuestsPanel } from "@/components/DailyQuestsPanel";
import { useProgressStore } from "@/store/progress";
import { Trophy } from "@/components/icons";

export function RightRail() {
  return (
    <div className="flex flex-col gap-4 w-full">
      <div className="flex justify-end">
        <StatsBar compact />
      </div>
      <LeaderboardTeaserCard />
      <DailyQuestsPanel />
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

function CreateProfilePromptCard() {
  return null;
}

function FooterLinks() {
  return null;
}
