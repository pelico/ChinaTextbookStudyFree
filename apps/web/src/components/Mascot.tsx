"use client";

/**
 * 乌萨奇 — 吉祥物
 * viewBox 0 -18 120 138
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

const CREAM = "#F8E9C4";
const STROKE = "#2C2018";
const EAR_INNER = "#F7B8C4";
const BLUSH = "#FF9EAA";
const MOUTH_C = "#2C2018";

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
        viewBox="0 -18 120 138"
        xmlns="http://www.w3.org/2000/svg"
        aria-label="乌萨奇"
        style={{ display: "block" }}
      >
        {/* 左耳 */}
        <path d="M42 24 Q38 -8 48 -16 Q56 -12 54 24 Z" fill={CREAM} stroke={STROKE} strokeWidth="1.6" strokeLinejoin="round" />
        <path d="M44 22 Q41 -4 49 -11 Q54 -8 52 22 Z" fill={EAR_INNER} opacity="0.7" />
        {/* 右耳 */}
        <path d="M78 24 Q82 -8 72 -16 Q64 -12 66 24 Z" fill={CREAM} stroke={STROKE} strokeWidth="1.6" strokeLinejoin="round" />
        <path d="M76 22 Q79 -4 71 -11 Q66 -8 68 22 Z" fill={EAR_INNER} opacity="0.7" />

        {/* 小手 */}
        <motion.ellipse
          cx="32" cy="86" rx="4" ry="8"
          fill={CREAM} stroke={STROKE} strokeWidth="1.6"
          style={{ originX: "60px", originY: "86px" } as React.CSSProperties}
          animate={armControls}
          transform={mood === "wave" ? "rotate(-40 32 86)" : undefined}
        />
        <ellipse cx="88" cy="86" rx="4" ry="8" fill={CREAM} stroke={STROKE} strokeWidth="1.6" />

        {/* 小脚 */}
        <ellipse cx="46" cy="112" rx="5.5" ry="3.8" fill={CREAM} stroke={STROKE} strokeWidth="1.6" />
        <ellipse cx="74" cy="112" rx="5.5" ry="3.8" fill={CREAM} stroke={STROKE} strokeWidth="1.6" />

        {/* 身体 + 头 */}
        <ellipse cx="60" cy="90" rx="24" ry="20" fill={CREAM} stroke={STROKE} strokeWidth="1.6" />
        <ellipse cx="60" cy="54" rx="38" ry="39" fill={CREAM} stroke={STROKE} strokeWidth="1.6" />

        {/* 腮红 + 三道短线 */}
        <ellipse cx="30" cy="62" rx="6" ry="4.2" fill={BLUSH} opacity={mood === "embarrassed" ? 0.8 : 0.55} />
        <path d="M27 60 L30 63 M30 59 L33 62 M33 60 L36 63" stroke={STROKE} strokeWidth="1" strokeLinecap="round" />
        <ellipse cx="90" cy="62" rx="6" ry="4.2" fill={BLUSH} opacity={mood === "embarrassed" ? 0.8 : 0.55} />
        <path d="M87 60 L90 63 M90 59 L93 62 M93 60 L96 63" stroke={STROKE} strokeWidth="1" strokeLinecap="round" />

        {/* 眉毛 */}
        <Eyebrows mood={mood} />

        {/* 眼睛 */}
        {blinkClose && (mood === "happy" || mood === "think" || mood === "wave") ? (
          <>
            <path d="M44 54 Q48 57 52 54" fill="none" stroke={STROKE} strokeWidth="2" strokeLinecap="round" />
            <path d="M68 54 Q72 57 76 54" fill="none" stroke={STROKE} strokeWidth="2" strokeLinecap="round" />
          </>
        ) : (
          <Eyes mood={mood} />
        )}

        {/* 嘴 */}
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

        <MascotSkinOverlay skinId={skinId} />
      </motion.svg>
    </div>
  );
}

function Eyebrows({ mood }: { mood: MascotMood }) {
  const sw = 2.2;
  const sc = STROKE;
  const lc = "round";
  switch (mood) {
    case "sad":
      return (
        <>
          <path d="M 48 37 Q 41 42 34 46" fill="none" stroke={sc} strokeWidth={sw} strokeLinecap={lc} />
          <path d="M 72 37 Q 79 42 86 46" fill="none" stroke={sc} strokeWidth={sw} strokeLinecap={lc} />
        </>
      );
    case "proud":
      return (
        <>
          <path d="M 34 42 Q 41 36 48 38" fill="none" stroke={sc} strokeWidth={sw} strokeLinecap={lc} />
          <path d="M 72 38 Q 79 36 86 42" fill="none" stroke={sc} strokeWidth={sw} strokeLinecap={lc} />
        </>
      );
    case "surprise":
      return (
        <>
          <path d="M 34 42 Q 41 34 48 35" fill="none" stroke={sc} strokeWidth={sw} strokeLinecap={lc} />
          <path d="M 72 35 Q 79 34 86 42" fill="none" stroke={sc} strokeWidth={sw} strokeLinecap={lc} />
        </>
      );
    case "think":
      return (
        <>
          <path d="M 34 44 Q 41 38 48 38" fill="none" stroke={sc} strokeWidth={sw} strokeLinecap={lc} />
          <path d="M 72 36 Q 79 34 86 42" fill="none" stroke={sc} strokeWidth={sw} strokeLinecap={lc} />
        </>
      );
    default:
      return (
        <>
          <path d="M 34 44 Q 41 37 48 37" fill="none" stroke={sc} strokeWidth={sw} strokeLinecap={lc} />
          <path d="M 72 37 Q 79 37 86 44" fill="none" stroke={sc} strokeWidth={sw} strokeLinecap={lc} />
        </>
      );
  }
}

function Eyes({ mood }: { mood: MascotMood }) {
  const c = STROKE;
  switch (mood) {
    case "cheer":
      return (
        <>
          <path d="M44 54 Q48 48 52 54" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round" />
          <path d="M68 54 Q72 48 76 54" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round" />
        </>
      );
    case "sad":
      return (
        <>
          <circle cx="48" cy="56" r="2.8" fill={c} />
          <circle cx="72" cy="56" r="2.8" fill={c} />
        </>
      );
    case "think":
      return (
        <>
          <circle cx="48" cy="54" r="3.6" fill={c} />
          <circle cx="49.4" cy="52.6" r="1" fill="#FFFFFF" />
          <path d="M68 54 Q72 52 76 54" fill="none" stroke={c} strokeWidth="1.8" strokeLinecap="round" />
        </>
      );
    case "surprise":
      return (
        <>
          <circle cx="48" cy="54" r="5.5" fill={c} />
          <circle cx="50" cy="52" r="1.5" fill="#FFFFFF" />
          <circle cx="72" cy="54" r="5.5" fill={c} />
          <circle cx="74" cy="52" r="1.5" fill="#FFFFFF" />
        </>
      );
    case "proud":
      return (
        <>
          <circle cx="48" cy="54" r="3.6" fill={c} />
          <circle cx="49.4" cy="52.6" r="1" fill="#FFFFFF" />
          <circle cx="72" cy="54" r="3.6" fill={c} />
          <circle cx="73.4" cy="52.6" r="1" fill="#FFFFFF" />
        </>
      );
    case "embarrassed":
      return (
        <>
          <circle cx="48" cy="56" r="2" fill={c} />
          <circle cx="72" cy="56" r="2" fill={c} />
        </>
      );
    default:
      return (
        <>
          <circle cx="48" cy="54" r="3.6" fill={c} />
          <circle cx="49.4" cy="52.6" r="1" fill="#FFFFFF" />
          <circle cx="72" cy="54" r="3.6" fill={c} />
          <circle cx="73.4" cy="52.6" r="1" fill="#FFFFFF" />
        </>
      );
  }
}

function Mouth({ mood }: { mood: MascotMood }) {
  const c = MOUTH_C;
  switch (mood) {
    case "sad":
      return (
        <path d="M 53 72 C 53 66.5 59 66.5 60 71 C 61 66.5 67 66.5 67 72" fill="none" stroke={c} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
      );
    case "surprise":
      return (
        <ellipse cx="60" cy="69" rx="4" ry="5" fill="#D97A6C" stroke={c} strokeWidth="1.6" />
      );
    case "cheer":
      return (
        <path d="M 50 64 Q 60 76 70 64" fill="none" stroke={c} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
      );
    default:
      return (
        <path d="M 53 66 C 53 71.5 59 71.5 60 67 C 61 71.5 67 71.5 67 66" fill="none" stroke={c} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
      );
  }
}
