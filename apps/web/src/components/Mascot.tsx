"use client";

/**
 * 乌萨奇 — 吉祥物
 * viewBox 0 -15 120 135（顶部留出长耳空间）
 *
 * 特征（对齐 chiikawa 原作）：
 *   - 高耸直立的长耳朵
 *   - 弯弯的长眉毛，弧线围绕眼睛
 *   - 小圆点眼睛
 *   - 粉色腮红（常驻）
 *   - 突出的下嘴唇（噘嘴感）
 *   - 细小的手脚
 *   - 黄色圆润身体
 */

import { motion, useAnimation, useReducedMotion } from "framer-motion";
import { useEffect, useState } from "react";
import { MascotSkinOverlay } from "./MascotSkinOverlay";
import { useProgressStore } from "@/store/progress";
import type { MascotMood, MascotReaction } from "@cstf/core";

export type { MascotMood, MascotReaction };

export interface MascotProps {
  mood?: MascotMood;
  size?: number;
  animate?: boolean;
  reactTo?: MascotReaction;
  reactKey?: number;
  skinOverride?: string | null;
}

const CREAM = "#EFD9A8";
const SHADE = "#D4BE86";
const EAR_INNER = "#EEAABB";
const INK = "#3B2B1F";
const BLUSH = "#FF8A9B";
const MOUTH_C = "#8A6A4A";

export function Mascot({
  mood = "happy",
  size = 120,
  animate = true,
  reactTo = null,
  reactKey = 0,
  skinOverride,
}: MascotProps) {
  const prefersReduced = useReducedMotion();
  const controls = useAnimation();
  const armControls = useAnimation();
  const [blinkClose, setBlinkClose] = useState(false);
  const [showSweat, setShowSweat] = useState(false);
  const [showGlow, setShowGlow] = useState(false);

  const equippedSkin = useProgressStore(s => s.equippedMascotSkin);
  const skinId = skinOverride !== undefined ? skinOverride : equippedSkin;

  useEffect(() => {
    if (!animate || prefersReduced) return;
    controls.start({
      y: [0, -3, 0],
      scale: [1, 1.02, 1],
      transition: { duration: 2.6, repeat: Infinity, ease: "easeInOut" },
    });
  }, [animate, prefersReduced, controls]);

  useEffect(() => {
    if (!animate || prefersReduced) return;
    let timer: ReturnType<typeof setTimeout>;
    const schedule = () => {
      const next = 2500 + Math.random() * 3500;
      timer = setTimeout(() => {
        setBlinkClose(true);
        setTimeout(() => setBlinkClose(false), 120);
        schedule();
      }, next);
    };
    schedule();
    return () => clearTimeout(timer);
  }, [animate, prefersReduced]);

  useEffect(() => {
    if (!reactTo || prefersReduced) return;
    setShowSweat(false);
    setShowGlow(false);
    if (reactTo === "correct") {
      controls.start({
        scale: [1, 1.18, 0.95, 1.05, 1],
        y: [0, -6, 0],
        transition: { duration: 0.55, ease: "easeOut" },
      });
      armControls.start({
        rotate: [0, -25, 0, -18, 0],
        transition: { duration: 0.55 },
      });
    } else if (reactTo === "wrong") {
      controls.start({
        rotate: [0, -8, 8, -6, 6, 0],
        x: [0, -2, 2, 0],
        transition: { duration: 0.55 },
      });
      setShowSweat(true);
      setTimeout(() => setShowSweat(false), 1200);
    } else if (reactTo === "levelup") {
      setShowGlow(true);
      controls.start({
        y: [0, -18, 0, -8, 0],
        scale: [1, 1.1, 1, 1.05, 1],
        transition: { duration: 0.9, ease: "easeOut" },
      });
      armControls.start({
        rotate: [0, -30, 0, -30, 0],
        transition: { duration: 0.9 },
      });
      setTimeout(() => setShowGlow(false), 1400);
    }
  }, [reactTo, reactKey, controls, armControls, prefersReduced]);

  return (
    <div style={{ width: size, height: size, position: "relative", display: "inline-block" }}>
      {showGlow && (
        <motion.div
          initial={{ opacity: 0, scale: 0.6 }}
          animate={{ opacity: [0, 0.8, 0], scale: [0.6, 1.4, 1.6] }}
          transition={{ duration: 1.2 }}
          style={{
            position: "absolute",
            inset: "-20%",
            borderRadius: "9999px",
            background: "radial-gradient(circle, rgba(255,200,0,0.55), rgba(255,200,0,0) 70%)",
            pointerEvents: "none",
          }}
        />
      )}
      <motion.svg
        animate={controls}
        width={size}
        height={size}
        viewBox="0 -15 120 135"
        xmlns="http://www.w3.org/2000/svg"
        aria-label="乌萨奇"
        style={{ display: "block" }}
      >
        {/* ===== 长耳朵（高耸直立、靠中间） ===== */}
        {/* 左耳 */}
        <path
          d="M 45 26 Q 35 -2 44 -14 Q 54 -10 52 26 Z"
          fill={CREAM}
          stroke={SHADE}
          strokeWidth="1.5"
          strokeLinejoin="round"
        />
        <path
          d="M 46 24 Q 38 0 45 -10 Q 51 -7 49 24 Z"
          fill={EAR_INNER}
          opacity="0.6"
        />
        {/* 右耳 */}
        <path
          d="M 75 26 Q 85 -2 76 -14 Q 66 -10 68 26 Z"
          fill={CREAM}
          stroke={SHADE}
          strokeWidth="1.5"
          strokeLinejoin="round"
        />
        <path
          d="M 74 24 Q 82 0 75 -10 Q 69 -7 71 24 Z"
          fill={EAR_INNER}
          opacity="0.6"
        />

        {/* ===== 细手臂 ===== */}
        <motion.ellipse
          cx="26"
          cy="82"
          rx="5"
          ry="11"
          fill={CREAM}
          stroke={SHADE}
          strokeWidth="1.5"
          style={{ originX: "60px", originY: "82px" } as React.CSSProperties}
          animate={armControls}
          transform={mood === "wave" ? "rotate(-40 26 82)" : undefined}
        />
        <ellipse
          cx="94"
          cy="82"
          rx="5"
          ry="11"
          fill={CREAM}
          stroke={SHADE}
          strokeWidth="1.5"
        />

        {/* ===== 细脚 ===== */}
        <ellipse cx="50" cy="110" rx="6" ry="4" fill={CREAM} stroke={SHADE} strokeWidth="1.5" />
        <ellipse cx="70" cy="110" rx="6" ry="4" fill={CREAM} stroke={SHADE} strokeWidth="1.5" />

        {/* ===== 身体 + 头 ===== */}
        <ellipse cx="60" cy="84" rx="28" ry="24" fill={CREAM} stroke={SHADE} strokeWidth="1.5" />
        <ellipse cx="60" cy="56" rx="33" ry="35" fill={CREAM} stroke={SHADE} strokeWidth="1.5" />
        {/* 腹部淡影 */}
        <ellipse cx="60" cy="88" rx="15" ry="12" fill={SHADE} opacity={0.25} />

        {/* ===== 腮红（常驻） ===== */}
        <ellipse cx="34" cy="62" rx="5.5" ry="4" fill={BLUSH} opacity={mood === "embarrassed" ? 0.85 : 0.5} />
        <ellipse cx="86" cy="62" rx="5.5" ry="4" fill={BLUSH} opacity={mood === "embarrassed" ? 0.85 : 0.5} />

        {/* ===== 弯弯眉毛（弧线围绕眼睛上方） ===== */}
        <Eyebrows mood={mood} />

        {/* ===== 眼睛 ===== */}
        {blinkClose && (mood === "happy" || mood === "think" || mood === "wave") ? (
          <>
            <path d="M 42 54 Q 48 58 54 54" fill="none" stroke={INK} strokeWidth="2" strokeLinecap="round" />
            <path d="M 66 54 Q 72 58 78 54" fill="none" stroke={INK} strokeWidth="2" strokeLinecap="round" />
          </>
        ) : (
          <Eyes mood={mood} />
        )}

        {/* ===== 嘴（突出下唇 / 噘嘴） ===== */}
        <Mouth mood={mood} />

        {/* 汗滴 */}
        {showSweat && (
          <motion.path
            initial={{ opacity: 0, y: -4 }}
            animate={{ opacity: [0, 1, 1, 0], y: [-4, 2, 8, 14] }}
            transition={{ duration: 1.1 }}
            d="M 96 24 Q 100 32 96 36 Q 92 32 96 24 Z"
            fill="#7EC4F0"
            stroke="#1CB0F6"
            strokeWidth="1.2"
          />
        )}

        {/* 皮肤叠加层 */}
        <MascotSkinOverlay skinId={skinId} />
      </motion.svg>
    </div>
  );
}

/** 夸张弯弯眉毛 — 斜弧线围绕脸型 */
function Eyebrows({ mood }: { mood: MascotMood }) {
  const sw = 2;
  const sc = INK;
  const lc = "round";
  switch (mood) {
    case "sad":
      return (
        <>
          {/* 八字眉 — 内高外低 */}
          <path d="M 50 46 Q 38 52 24 55" fill="none" stroke={sc} strokeWidth={sw} strokeLinecap={lc} />
          <path d="M 70 46 Q 82 52 96 55" fill="none" stroke={sc} strokeWidth={sw} strokeLinecap={lc} />
        </>
      );
    case "proud":
      return (
        <>
          {/* 挑眉 — 内低外高 */}
          <path d="M 48 48 Q 34 38 22 42" fill="none" stroke={sc} strokeWidth={sw} strokeLinecap={lc} />
          <path d="M 72 48 Q 86 38 98 42" fill="none" stroke={sc} strokeWidth={sw} strokeLinecap={lc} />
        </>
      );
    case "surprise":
      return (
        <>
          {/* 高扬眉 */}
          <path d="M 48 46 Q 32 32 20 40" fill="none" stroke={sc} strokeWidth={sw} strokeLinecap={lc} />
          <path d="M 72 46 Q 88 32 100 40" fill="none" stroke={sc} strokeWidth={sw} strokeLinecap={lc} />
        </>
      );
    case "think":
      return (
        <>
          {/* 一高一低 */}
          <path d="M 48 47 Q 34 41 22 45" fill="none" stroke={sc} strokeWidth={sw} strokeLinecap={lc} />
          <path d="M 72 45 Q 86 37 98 41" fill="none" stroke={sc} strokeWidth={sw} strokeLinecap={lc} />
        </>
      );
    default:
      return (
        <>
          {/* 夸张斜弧线围绕脸型 — 从内眼上方斜向外下沿脸轮廓 */}
          <path d="M 48 47 Q 32 39 20 48" fill="none" stroke={sc} strokeWidth={sw} strokeLinecap={lc} />
          <path d="M 72 47 Q 88 39 100 48" fill="none" stroke={sc} strokeWidth={sw} strokeLinecap={lc} />
        </>
      );
  }
}

/** 眼睛 — 小圆点 */
function Eyes({ mood }: { mood: MascotMood }) {
  const c = INK;
  switch (mood) {
    case "cheer":
      return (
        <>
          <path d="M 42 54 Q 48 48 54 54" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round" />
          <path d="M 66 54 Q 72 48 78 54" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round" />
        </>
      );
    case "sad":
      return (
        <>
          <circle cx="48" cy="56" r="2.5" fill={c} />
          <circle cx="72" cy="56" r="2.5" fill={c} />
        </>
      );
    case "think":
      return (
        <>
          <circle cx="48" cy="54" r="3" fill={c} />
          <circle cx="49" cy="53" r="0.8" fill="#FFFFFF" />
          <path d="M 66 54 Q 72 52 78 54" fill="none" stroke={c} strokeWidth="1.8" strokeLinecap="round" />
        </>
      );
    case "surprise":
      return (
        <>
          <circle cx="48" cy="54" r="5" fill={c} />
          <circle cx="50" cy="52" r="1.3" fill="#FFFFFF" />
          <circle cx="72" cy="54" r="5" fill={c} />
          <circle cx="74" cy="52" r="1.3" fill="#FFFFFF" />
        </>
      );
    case "proud":
      return (
        <>
          <circle cx="48" cy="54" r="3" fill={c} />
          <circle cx="49.5" cy="52.5" r="1.1" fill="#FFFFFF" />
          <circle cx="72" cy="54" r="3" fill={c} />
          <circle cx="73.5" cy="52.5" r="1.1" fill="#FFFFFF" />
        </>
      );
    case "embarrassed":
      return (
        <>
          <circle cx="48" cy="56" r="1.8" fill={c} />
          <circle cx="72" cy="56" r="1.8" fill={c} />
        </>
      );
    default:
      return (
        <>
          <circle cx="48" cy="54" r="3" fill={c} />
          <circle cx="49" cy="53" r="0.8" fill="#FFFFFF" />
          <circle cx="72" cy="54" r="3" fill={c} />
          <circle cx="73" cy="53" r="0.8" fill="#FFFFFF" />
        </>
      );
  }
}

/** 嘴 — 三瓣嘴（三条弯弯线条组成） */
function Mouth({ mood }: { mood: MascotMood }) {
  const c = MOUTH_C;
  const sw = 2;
  const lc = "round";
  switch (mood) {
    case "sad":
      return (
        <path d="M 54 72 Q 60 76 66 72" fill="none" stroke={c} strokeWidth={sw} strokeLinecap={lc} />
      );
    case "surprise":
      return (
        <ellipse cx="60" cy="72" rx="3.5" ry="4.5" fill="#D97A6C" stroke={c} strokeWidth="1.8" />
      );
    case "cheer":
      return (
        <path d="M 52 68 Q 60 78 68 68" fill="none" stroke={c} strokeWidth={sw} strokeLinecap={lc} />
      );
    default:
      // 三瓣嘴：左弧 + 中凹 + 右弧（三条弯弯线条）
      return (
        <>
          <path d="M 53 69 Q 57 73 60 71" fill="none" stroke={c} strokeWidth={sw} strokeLinecap={lc} />
          <path d="M 60 71 Q 60 75 60 73" fill="none" stroke={c} strokeWidth={sw} strokeLinecap={lc} />
          <path d="M 60 73 Q 63 73 67 69" fill="none" stroke={c} strokeWidth={sw} strokeLinecap={lc} />
        </>
      );
  }
}
