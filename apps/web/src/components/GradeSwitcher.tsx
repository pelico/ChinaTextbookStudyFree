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
        // compact variant：6 颗按钮均分容器宽度，无 wraps
        // full variant：标题 label + 按钮组，按钮内等分
        variant === "full"
          ? "grid grid-cols-[auto_1fr] items-center gap-x-2 gap-y-1.5 w-full"
          : "grid grid-cols-6 items-center gap-1.5 w-full",
      )}
      role="group"
      aria-label="切换年级"
    >
      {variant === "full" && (
        <span className="text-xs font-extrabold text-ink-light select-none">年级</span>
      )}
      <div
        className={cn(
          variant === "full"
            ? "grid grid-cols-6 gap-1.5 col-start-2"
            : "contents",
        )}
      >
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
                // grid 中用 w-full 替代 min-w，让所有按钮均分列宽；h-8 + 圆角保持紧凑风格
                "h-8 w-full rounded-lg text-sm font-extrabold leading-none transition-colors select-none",
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
    </div>
  );
}
