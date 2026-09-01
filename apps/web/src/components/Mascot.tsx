"use client";

/**
 * 乌萨奇 — 吉祥物
 * viewBox 0 0 120 120
 * 特征：长尖耳靠中间、两根长眉毛、点眼睛、腮红、ω 形小嘴
 *
 * mood:
 *   - happy / wave:  默认开心（眨眼睛）
 *   - cheer:          欢呼（眼睛弯成 ^ ^）
 *   - sad:            答错（眉毛下垂 + 倒嘴）
 *   - think:          思考（一只眼半闭）
 *   - surprise:       惊讶（眼睛变大）
 *   - proud:          骄傲（星星眼 + 挑眉）
 *   - embarrassed:    尴尬（脸更红 + 小斜眼）
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

// 乌萨奇配色
const CREAM = "#F0DDB0";
const SHADE = "#D9C294";
const EAR_INNER = "#F0B0B0";
const INK = "#3B2B1F";
const BLUSH = "#FF8A9B";
const MOUTH_C = "#7A5A44";

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
        viewBox="0 0 120 120"
        xmlns="http://www.w3.org/2000/svg"
        aria-label="乌萨奇"
        style={{ display: "block" }}
      >
        {/* ===== 耳朵（长、尖、靠中间） ===== */}
        {/* 左耳 */}
        <path
          d="M 46 32 Q 38 14 47 2 Q 56 6 53 32 Z"
          fill={CREAM}
          stroke={SHADE}
          strokeWidth="1.5"
          strokeLinejoin="round"
        />
        <path
          d="M 47 30 Q 41 16 47 6 Q 52 10 50 30 Z"
          fill={EAR_INNER}
          opacity="0.65"
        />
        {/* 右耳 */}
        <path
          d="M 74 32 Q 82 14 73 2 Q 64 6 67 32 Z"
          fill={CREAM}
          stroke={SHADE}
          strokeWidth="1.5"
          strokeLinejoin="round"
        />
        <path
          d="M 73 30 Q 79 16 73 6 Q 68 10 70 30 Z"
          fill={EAR_INNER}
          opacity="0.65"
        />

        {/* ===== 手臂 ===== */}
        <motion.ellipse
          cx="24"
          cy="82"
          rx="7"
          ry="12"
          fill={CREAM}
          stroke={SHADE}
          strokeWidth="1.5"
          style={{ originX: "60px", originY: "82px" } as React.CSSProperties}
          animate={armControls}
          transform={mood === "wave" ? "rotate(-40 24 82)" : undefined}
        />
        <ellipse
          cx="96"
          cy="82"
          rx="7"
          ry="12"
          fill={CREAM}
          stroke={SHADE}
          strokeWidth="1.5"
        />

        {/* ===== 脚 ===== */}
        <ellipse cx="48" cy="108" rx="9" ry="6" fill={CREAM} stroke={SHADE} strokeWidth="1.5" />
        <ellipse cx="72" cy="108" rx="9" ry="6" fill={CREAM} stroke={SHADE} strokeWidth="1.5" />

        {/* ===== 身体 + 头（圆润土豆形） ===== */}
        <ellipse cx="60" cy="84" rx="30" ry="26" fill={CREAM} stroke={SHADE} strokeWidth="1.5" />
        <ellipse cx="60" cy="54" rx="34" ry="36" fill={CREAM} stroke={SHADE} strokeWidth="1.5" />
        {/* 腹部淡影 */}
        <ellipse cx="60" cy="88" rx="16" ry="14" fill={SHADE} opacity={0.3} />

        {/* ===== 腮红（常驻） ===== */}
        <ellipse cx="33" cy="60" rx="6" ry="4.5" fill={BLUSH} opacity={mood === "embarrassed" ? 0.85 : 0.5} />
        <ellipse cx="87" cy="60" rx="6" ry="4.5" fill={BLUSH} opacity={mood === "embarrassed" ? 0.85 : 0.5} />

        {/* ===== 眉毛（两根长眉，根据 mood 变化） ===== */}
        <Eyebrows mood={mood} />

        {/* ===== 眼睛 ===== */}
        {blinkClose && (mood === "happy" || mood === "think" || mood === "wave") ? (
          <>
            <path d="M 40 52 Q 48 56 56 52" fill="none" stroke={INK} strokeWidth="2.2" strokeLinecap="round" />
            <path d="M 64 52 Q 72 56 80 52" fill="none" stroke={INK} strokeWidth="2.2" strokeLinecap="round" />
          </>
        ) : (
          <Eyes mood={mood} />
        )}

        {/* ===== 嘴（乌萨奇 ω 形） ===== */}
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

/** 眉毛组件 — 两根长眉，形状随 mood 变化 */
function Eyebrows({ mood }: { mood: MascotMood }) {
  const sw = 2.2;
  const sc = INK;
  switch (mood) {
    case "sad":
      return (
        <>
          {/* 八字眉（内侧高、外侧低） */}
          <path d="M 56 44 Q 50 48 40 46" fill="none" stroke={sc} strokeWidth={sw} strokeLinecap="round" />
          <path d="M 64 44 Q 70 48 80 46" fill="none" stroke={sc} strokeWidth={sw} strokeLinecap="round" />
        </>
      );
    case "proud":
      return (
        <>
          {/* 挑眉（内侧低、外侧高） */}
          <path d="M 40 42 Q 46 38 56 40" fill="none" stroke={sc} strokeWidth={sw} strokeLinecap="round" />
          <path d="M 80 42 Q 74 38 64 40" fill="none" stroke={sc} strokeWidth={sw} strokeLinecap="round" />
        </>
      );
    case "think":
      return (
        <>
          {/* 一高一低 */}
          <path d="M 40 44 Q 46 42 56 44" fill="none" stroke={sc} strokeWidth={sw} strokeLinecap="round" />
          <path d="M 64 42 Q 70 40 80 42" fill="none" stroke={sc} strokeWidth={sw} strokeLinecap="round" />
        </>
      );
    case "surprise":
      return (
        <>
          {/* 高高扬起 */}
          <path d="M 40 40 Q 48 36 56 40" fill="none" stroke={sc} strokeWidth={sw} strokeLinecap="round" />
          <path d="M 64 40 Q 72 36 80 40" fill="none" stroke={sc} strokeWidth={sw} strokeLinecap="round" />
        </>
      );
    default:
      return (
        <>
          {/* 平直长眉 */}
          <path d="M 38 44 Q 48 43 56 44" fill="none" stroke={sc} strokeWidth={sw} strokeLinecap="round" />
          <path d="M 64 44 Q 72 43 82 44" fill="none" stroke={sc} strokeWidth={sw} strokeLinecap="round" />
        </>
      );
  }
}

/** 眼睛 — 小黑点 */
function Eyes({ mood }: { mood: MascotMood }) {
  const c = INK;
  switch (mood) {
    case "cheer":
      return (
        <>
          <path d="M 40 52 Q 48 46 56 52" fill="none" stroke={c} strokeWidth="2.2" strokeLinecap="round" />
          <path d="M 64 52 Q 72 46 80 52" fill="none" stroke={c} strokeWidth="2.2" strokeLinecap="round" />
        </>
      );
    case "sad":
      return (
        <>
          <circle cx="48" cy="54" r="3" fill={c} />
          <circle cx="72" cy="54" r="3" fill={c} />
        </>
      );
    case "think":
      return (
        <>
          <circle cx="48" cy="52" r="3.5" fill={c} />
          <circle cx="49" cy="51" r="1" fill="#FFFFFF" />
          <path d="M 64 52 Q 72 50 80 52" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round" />
        </>
      );
    case "surprise":
      return (
        <>
          <circle cx="48" cy="52" r="5.5" fill={c} />
          <circle cx="50" cy="50" r="1.5" fill="#FFFFFF" />
          <circle cx="72" cy="52" r="5.5" fill={c} />
          <circle cx="74" cy="50" r="1.5" fill="#FFFFFF" />
        </>
      );
    case "proud":
      return (
        <>
          <circle cx="48" cy="52" r="3.5" fill={c} />
          <circle cx="49.5" cy="50.5" r="1.3" fill="#FFFFFF" />
          <circle cx="46" cy="53" r="0.7" fill="#FFFFFF" />
          <circle cx="72" cy="52" r="3.5" fill={c} />
          <circle cx="73.5" cy="50.5" r="1.3" fill="#FFFFFF" />
          <circle cx="70" cy="53" r="0.7" fill="#FFFFFF" />
        </>
      );
    case "embarrassed":
      return (
        <>
          <circle cx="48" cy="54" r="2" fill={c} />
          <circle cx="72" cy="54" r="2" fill={c} />
        </>
      );
    default:
      return (
        <>
          <circle cx="48" cy="52" r="3.5" fill={c} />
          <circle cx="49.5" cy="50.5" r="1" fill="#FFFFFF" />
          <circle cx="72" cy="52" r="3.5" fill={c} />
          <circle cx="73.5" cy="50.5" r="1" fill="#FFFFFF" />
        </>
      );
  }
}

/** 嘴 — 乌萨奇 ω 形 */
function Mouth({ mood }: { mood: MascotMood }) {
  const c = MOUTH_C;
  switch (mood) {
    case "sad":
      return (
        <path d="M 54 70 Q 60 76 66 70" fill="none" stroke={c} strokeWidth="2.5" strokeLinecap="round" />
      );
    case "surprise":
      return (
        <ellipse cx="60" cy="72" rx="4" ry="5" fill="#D97A6C" stroke={c} strokeWidth="2" />
      );
    case "cheer":
      return (
        <>
          <path d="M 52 66 Q 60 78 68 66" fill="none" stroke={c} strokeWidth="2.5" strokeLinecap="round" />
          <path d="M 52 66 Q 56 70 60 69" fill="none" stroke={c} strokeWidth="1.5" strokeLinecap="round" />
        </>
      );
    case "proud":
      return (
        <path d="M 52 68 Q 56 64 60 69 Q 64 64 68 68" fill="none" stroke={c} strokeWidth="2.5" strokeLinecap="round" />
      );
    default:
      // ω 形：两个小弧
      return (
        <path
          d="M 54 68 Q 57 73 60 70 Q 63 73 66 68"
          fill="none"
          stroke={c}
          strokeWidth="2.5"
          strokeLinecap="round"
        />
      );
  }
}
