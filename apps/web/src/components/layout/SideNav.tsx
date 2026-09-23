"use client";

/**
 * SideNav —— 桌面端左侧导航
 *
 * 真实页面：学习 / 阅读 / 排行榜 / 错题本 / 商店 / 我的
 * 工具区：打印试卷 / 自定义学习
 *
 * 响应式（web-shell-14）：
 *   - md (768-1023)：icon-only 窄栏（AppShell 给 96px），文字隐藏
 *   - lg+：完整 296px，图标 + 文字
 * 激活态用粗填充图标（web-shell-19），视觉重量对齐 iOS。
 * 顶部 logo 右侧放 LightDarkToggle（二态日/夜切换）；三态切换保留在「我的」页。
 */

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useMemo, type ComponentType, type ReactNode } from "react";
import { useProgressStore } from "@/store/progress";
import {
  Home as HomeIcon,
  HomeFill,
  Trophy,
  TrophyFill,
  Bookmark,
  BookmarkFill,
  Gem,
  User,
  UserFill,
  Book,
  BookOpen,
  Sparkle,
  type IconProps,
} from "@/components/icons";
import { LightDarkToggle } from "@/components/LightDarkToggle";
import { StatsBar } from "@/components/StatsBar";
import { GradeSwitcher } from "@/components/GradeSwitcher";
import { cn } from "@/lib/cn";
import { playSfx } from "@/lib/sfx";
import { haptic } from "@/lib/haptic";

interface NavItem {
  href: string;
  label: string;
  Icon: ComponentType<IconProps>;
  /** 激活态的粗填充变体（Gem 本身已是填充图标，复用同款） */
  IconActive: ComponentType<IconProps>;
  matchPrefix: string;
}

const ITEMS: NavItem[] = [
  { href: "/", label: "学习", Icon: HomeIcon, IconActive: HomeFill, matchPrefix: "/learn-root" },
  { href: "/reading/", label: "阅读", Icon: BookOpen, IconActive: BookOpen, matchPrefix: "/reading" },
  { href: "/league/", label: "排行榜", Icon: Trophy, IconActive: TrophyFill, matchPrefix: "/league" },
  { href: "/review/", label: "错题本", Icon: Bookmark, IconActive: BookmarkFill, matchPrefix: "/review" },
  { href: "/shop/", label: "商店", Icon: Gem, IconActive: Gem, matchPrefix: "/shop" },
  { href: "/profile/", label: "我的", Icon: User, IconActive: UserFill, matchPrefix: "/profile" },
];

function isActiveLearn(pathname: string): boolean {
  return (
    pathname === "/" ||
    pathname.startsWith("/grade/") ||
    pathname.startsWith("/book/") ||
    pathname.startsWith("/lesson/")
  );
}

function isActive(pathname: string, item: NavItem): boolean {
  if (item.label === "学习") return isActiveLearn(pathname);
  if (item.label === "阅读") {
    return pathname.startsWith("/reading") || pathname.startsWith("/stories");
  }
  return pathname.startsWith(item.matchPrefix);
}

interface SideNavProps {
  /** 由 AppShell 注入：渲染在 logo 下方、导航项上方的可滚动容器内同滚动区域 */
  leftSlot?: React.ReactNode;
}

export function SideNav({ leftSlot }: SideNavProps = {}) {
  const pathname = usePathname() ?? "/";
  const router = useRouter();
  // 当前所在年级：/grade/N/、/book/{id}/、/lesson/{unit}/{lesson}/ 三种路径都能反推到年级
  const activeGrade = useMemo(() => {
    const m = pathname.match(/^\/grade\/(\d+)/);
    if (m) return Number(m[1]);
    return null;
  }, [pathname]);
  const selectedGrade = useProgressStore(s => s.selectedGrade);
  // 学习 tab：有「当前教材」直接软跳该教材；否则直达所选年级（默认 1），
  // 避免经根页( / ) → 年级页的一次多余跳转造成连续网址变化/白屏。
  const activeBookId = useProgressStore(s => s.activeBookId);
  const learnHref = activeBookId ? `/book/${activeBookId}/` : `/grade/${selectedGrade ?? 1}/`;

  return (
    <nav className="flex flex-col gap-2 w-full h-full" aria-label="主导航">
      {/* Logo + 日/夜切换按钮 同行排列（md 与 lg 都显示） */}
      <div className="flex items-center gap-3 px-2 py-3 mb-2">
        <Link
          href="/"
          onClick={() => {
            playSfx("tap");
            haptic("light");
          }}
          className="flex-1 min-w-0 px-2"
          aria-label="悠悠学堂 · 回到首页"
        >
          <span className="hidden lg:inline text-4xl font-black text-primary tracking-tightest leading-none">
            悠悠学堂
          </span>
          <span className="lg:hidden inline-flex items-center justify-center w-10 h-10 rounded-2xl bg-primary/10 text-primary font-extrabold text-lg">
            聪
          </span>
        </Link>
        <LightDarkToggle />
      </div>

      {/* 桌面端状态条 —— 红心/连胜/宝石 移到左侧栏顶部，logo 下方、SideRail 上方。
         *   lg+ 完整宽 296px；三颗胶囊横向铺开，compact 模式省掉 XP / 音频开关。
         *   移动端 < md 不显示 SideNav，StatsBar 由各页面自己的 PageHeader / InnerHeader
         *   紧凑显示。 */}
      <div className="hidden lg:block mb-3">
        <StatsBar compact />
      </div>

      {/* 年级快速切换 —— 一排 6 颗紧凑按钮（无"年级"前缀），当前年级高亮
          md (768-1023) 96px 窄栏里隐藏，lg+ 完整宽 296px 时显示在导航区上方。
          用户在切换年级时无需先回首页选年级，顶部直接切。 */}
      <div className="hidden lg:flex justify-center mb-2">
        <GradeSwitcher current={activeGrade ?? selectedGrade ?? null} variant="compact" />
      </div>

      {/* 左列追加区（默认 SideRail：排行榜 + 每日任务）—— 紧贴 StatsBar 下方。
          注意：md (768-1023) 窄栏仅 96px，不显示 leftSlot（移动端由 BottomNav 之外的
          卡片各自承担），仅 lg+ 完整 296px 时显示。 */}
      {leftSlot && (
        <div className="hidden lg:block mb-3">{leftSlot}</div>
      )}

      {ITEMS.map(item => {
        const active = isActive(pathname, item);
        const Icon = active ? item.IconActive : item.Icon;
        return (
          <Link
            key={item.label}
            href={item.href === "/" ? learnHref : item.href}
            onClick={(e) => {
              // 强制走客户端路由（SPA），避免 WebView/老连接下动态路由退化为整页刷新
              const target = item.href === "/" ? learnHref : item.href;
              if (target && target !== pathname) {
                e.preventDefault();
                router.push(target);
              }
              playSfx("tap");
              haptic("light");
            }}
            className={cn(
              "group flex items-center justify-center lg:justify-start gap-3 px-3 h-14 rounded-2xl border-2 transition-colors select-none",
              active
                ? "border-secondary/50 bg-secondary/10 text-secondary-dark"
                : "border-transparent text-ink-light hover:bg-bg-soft"
            )}
            aria-current={active ? "page" : undefined}
            title={item.label}
          >
            <Icon
              className={cn(
                "w-7 h-7 shrink-0",
                active ? "text-secondary" : "text-ink-softer group-hover:text-ink-light"
              )}
            />
            <span
              className={cn(
                "hidden lg:inline text-base font-extrabold",
                active ? "text-secondary-dark" : "text-ink-light group-hover:text-ink"
              )}
            >
              {item.label}
            </span>
          </Link>
        );
      })}

      {/* 工具区：打印试卷 */}
      <div className="border-t-2 border-bg-softer my-2" />
      <Link
        href="/worksheet/"
        onClick={() => {
          playSfx("tap");
          haptic("light");
        }}
        className={cn(
          "group flex items-center justify-center lg:justify-start gap-3 px-3 h-14 rounded-2xl border-2 transition-colors select-none",
          pathname.startsWith("/worksheet")
            ? "border-primary/50 bg-primary/10 text-primary-dark"
            : "border-transparent text-ink-light hover:bg-bg-soft"
        )}
        aria-current={pathname.startsWith("/worksheet") ? "page" : undefined}
        title="打印试卷"
      >
        <div className="relative shrink-0">
          <Book
            className={cn(
              "w-7 h-7",
              pathname.startsWith("/worksheet") ? "text-primary" : "text-ink-softer group-hover:text-ink-light"
            )}
          />
          <Sparkle className="w-3.5 h-3.5 text-gold absolute -top-1 -right-1" />
        </div>
        <span
          className={cn(
            "hidden lg:inline text-base font-extrabold",
            pathname.startsWith("/worksheet") ? "text-primary-dark" : "text-ink-light group-hover:text-ink"
          )}
        >
          打印试卷
        </span>
      </Link>

      {/* 自定义学习入口 —— 拍课本/整理真题/跟读录入同链路 */}
      <Link
        href="/custom/"
        onClick={() => {
          playSfx("tap");
          haptic("light");
        }}
        className={cn(
          "group flex items-center justify-center lg:justify-start gap-3 px-3 h-14 rounded-2xl border-2 transition-colors select-none",
          pathname.startsWith("/custom/")
            ? "border-primary/50 bg-primary/10 text-primary-dark"
            : "border-transparent text-ink-light hover:bg-bg-soft"
        )}
        aria-current={pathname.startsWith("/custom/") ? "page" : undefined}
        title="自定义学习"
      >
        <BookOpen
          className={cn(
            "w-7 h-7 shrink-0",
            pathname.startsWith("/custom/") ? "text-primary" : "text-ink-softer group-hover:text-ink-light"
          )}
        />
        <span
          className={cn(
            "hidden lg:inline text-base font-extrabold",
            pathname.startsWith("/custom/") ? "text-primary-dark" : "text-ink-light group-hover:text-ink"
          )}
        >
          自定义学习
        </span>
      </Link>

      </nav>
  );
}
