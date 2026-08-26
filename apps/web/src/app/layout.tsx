import type { Metadata } from "next";
import { Nunito } from "next/font/google";
import "./globals.css";
import { ThemeProvider } from "@/components/ThemeProvider";
import { BottomNav } from "@/components/BottomNav";
import { ToastProvider } from "@/components/Toast";
import { DailyRewardWatcher } from "@/components/DailyRewardWatcher";
import { AchievementWatcher } from "@/components/AchievementWatcher";

const nunito = Nunito({
  subsets: ["latin"],
  weight: ["600", "700", "800", "900"],
  variable: "--font-display",
  display: "swap",
});

export const metadata: Metadata = {
  title: "小猫头鹰课堂",
  description: "全科免费，人人可学的小学AI学习平台",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="zh-CN" className={nunito.variable}>
      {/* 底部导航的高度补偿由 BottomNav 自带的占位条负责（web-lesson-15）：
          课程 / 阅读器等沉浸页导航隐藏时不再留 64px 死空隙 */}
      <body className="min-h-screen bg-bg-soft">
        <ThemeProvider>
          <ToastProvider>
            <DailyRewardWatcher />
            <AchievementWatcher />
            {children}
            <BottomNav />
          </ToastProvider>
        </ThemeProvider>
      </body>
    </html>
  );
}
