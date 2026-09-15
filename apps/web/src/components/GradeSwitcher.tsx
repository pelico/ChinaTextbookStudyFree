"use client";

/**
 * GradeSwitcher —— 年级页 / 全局顶部的"快速切换年级"6 颗按钮
 *
 * 当前年级：高亮 + 较深底色
 * 其它：浅灰底，点击直接切到对应年级页
 * 设计风格对齐 SideNav / StatsBar：圆角胶囊、紧凑、可触达 44px+
 */

import { useRouter } from "next/navigation";
import { cn } from "@/lib/cn";
import { playSfx } from "@/lib/sfx";
import { haptic } from "@/lib/haptic";
import { useProgressStore } from "@/store/progress";

const GRADE_NUMBERS = [1, 2, 3, 4, 5, 6] as const;
const GRADE_NAMES = ["", "一", "二", "三", "四", "五", "六"] as const;

interface Props {
  /** 当前年级（用于高亮）。未选年级时传 0 或不传。 */
  current?: number | null;
  /** "full" 渲染包含"年级"提示；"compact" 只渲染 6 颗按钮 */
  variant?: "full" | "compact";
}

export function GradeSwitcher({ current = null, variant = "full" }: Props) {
  const router = useRouter();
  const setSelectedGrade = useProgressStore(s => s.setSelectedGrade);

  return (
    <div
      className={cn(
        "flex items-center gap-1.5",
        variant === "full" && "flex-wrap",
      )}
      role="group"
      aria-label="切换年级"
    >
      {variant === "full" && (
        <span className="hidden lg:inline text-xs font-extrabold text-ink-light mr-1 select-none">
          年级
        </span>
      )}
      {GRADE_NUMBERS.map(g => {
        const active = current != null && g === current;
        return (
          <button
            key={g}
            type="button"
            onClick={() => {
              if (active) return;
              playSfx("tap");
              haptic("light");
              setSelectedGrade(g);
              router.push(`/grade/${g}/`);
            }}
            aria-current={active ? "page" : undefined}
            aria-label={`${GRADE_NAMES[g]}年级`}
            className={cn(
              "min-w-[36px] h-9 px-2.5 rounded-xl text-sm font-extrabold leading-none transition-colors select-none",
              active
                ? "bg-secondary text-white cursor-default"
                : "bg-bg-softer text-ink-light hover:bg-secondary/15 hover:text-secondary",
            )}
          >
            {GRADE_NAMES[g]}
          </button>
        );
      })}
    </div>
  );
}
