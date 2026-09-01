"use client";

/**
 * 乌萨奇 — 吉祥物，替换原熊猫"聪聪"。
 * 保留完整的动画系统（呼吸、眨眼、反应），仅改变外观。
 * viewBox 0 0 120 120 保持不变。
 *
 * mood:
 *   - happy:       默认开心（眨眼睛）
 *   - cheer:       欢呼（眼睛弯成 ^ ^）
 *   - sad:         答错时（眉毛低下）
 *   - think:       思考中（一只眼半闭）
 *   - wave:        挥手打招呼
 *   - surprise:    惊讶（眼睛很大）
 *   - proud:       骄傲（眼睛闪光 + 抬头）
 *   - embarrassed: 尴尬（脸颊红晕 + 眼睛斜视）
 *
 * reactTo: 一次性动画触发器
 *   - 'correct':  scale 弹跳 + 挥手
 *   - 'wrong':    头摇摆 + 汗滴
 *   - 'levelup':  跳跃 + 金色光晕
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
const BODY_CREAM = "#F5E6C8";      // 奶油黄
const BODY_SHADE = "#E8D5A8";     // 阴影
const EAR_INNER = "#F4C2C2";       // 耳朵内侧粉
const EYE_COLOR = "#2E2E2E";       // 眼睛
const BLUSH = "#FF9AA8";           // 腮红
const MOUTH = "#5A4A3A";          // 嘴

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

  // 持续呼吸
  useEffect(() => {
    if (!animate || prefersReduced) return;
    controls.start({
      y: [0, -3, 0],
      scale: [1, 1.02, 1],
      transition: { duration: 2.6, repeat: Infinity, ease: "easeInOut" },
    });
  }, [animate, prefersReduced, controls]);

  // 随机眨眼
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

  // 一次性反应动画
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
        {/* 左耳朵（长尖耳） */}
        <path
          d="M 38 38 Q 28 10 38 5 Q 48 8 44 38 Z"
          fill={BODY_CREAM}
          stroke={BODY_SHADE}
          strokeWidth="1.5"
        />
        <path
          d="M 38 35 Q 32 15 38 10 Q 42 14 40 35 Z"
          fill={EAR_INNER}
          opacity="0.7"
        />
        {/* 右耳朵 */}
        <path
          d="M 82 38 Q 92 10 82 5 Q 72 8 76 38 Z"
          fill={BODY_CREAM}
          stroke={BODY_SHADE}
          strokeWidth="1.5"
        />
        <path
          d="M 82 35 Q 88 15 82 10 Q 78 14 80 35 Z"
          fill={EAR_INNER}
          opacity="0.7"
        />

        {/* 左手臂（挥手动画） */}
        <motion.ellipse
          cx="22"
          cy="80"
          rx="8"
          ry="13"
          fill={BODY_CREAM}
          stroke={BODY_SHADE}
          strokeWidth="1.5"
          style={{ originX: "60px", originY: "80px" } as React.CSSProperties}
          animate={armControls}
          transform={mood === "wave" ? "rotate(-40 22 80)" : undefined}
        />
        {/* 右手臂 */}
        <ellipse
          cx="98"
          cy="80"
          rx="8"
          ry="13"
          fill={BODY_CREAM}
          stroke={BODY_SHADE}
          strokeWidth="1.5"
        />

        {/* 脚 */}
        <ellipse cx="46" cy="106" rx="10" ry="7" fill={BODY_CREAM} stroke={BODY_SHADE} strokeWidth="1.5" />
        <ellipse cx="74" cy="106" rx="10" ry="7" fill={BODY_CREAM} stroke={BODY_SHADE} strokeWidth="1.5" />

        {/* 身体 + 头（圆润团子） */}
        <ellipse cx="60" cy="84" rx="32" ry="28" fill={BODY_CREAM} stroke={BODY_SHADE} strokeWidth="1.5" />
        <ellipse cx="60" cy="52" rx="36" ry="34" fill={BODY_CREAM} stroke={BODY_SHADE} strokeWidth="1.5" />
        {/* 腹部阴影 */}
        <ellipse cx="60" cy="86" rx="18" ry="16" fill={BODY_SHADE} opacity={0.35} />

        {/* 眼睛（按 mood 切换；blinkClose 时盖上眼皮） */}
        {blinkClose && (mood === "happy" || mood === "think" || mood === "wave") ? (
          <>
            <path d="M 38 50 Q 46 54 54 50" fill="none" stroke={EYE_COLOR} strokeWidth="2.5" strokeLinecap="round" />
            <path d="M 66 50 Q 74 54 82 50" fill="none" stroke={EYE_COLOR} strokeWidth="2.5" strokeLinecap="round" />
          </>
        ) : (
          <Eyes mood={mood} />
        )}

        {/* 嘴（小微笑，根据 mood 变化） */}
        <path
          d={mood === "sad" ? "M 54 72 Q 60 66 66 72" : "M 54 70 Q 60 76 66 70"}
          fill="none"
          stroke={MOUTH}
          strokeWidth="2.5"
          strokeLinecap="round"
        />

        {/* 尴尬红晕 */}
        {mood === "embarrassed" && (
          <>
            <ellipse cx="30" cy="60" rx="7" ry="4" fill={BLUSH} opacity={0.7} />
            <ellipse cx="90" cy="60" rx="7" ry="4" fill={BLUSH} opacity={0.7} />
          </>
        )}

        {/* 汗滴（答错时） */}
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

        {/* 皮肤叠加层（帽子 / 眼镜 / 配饰） */}
        <MascotSkinOverlay skinId={skinId} />
      </motion.svg>
    </div>
  );
}

function Eyes({ mood }: { mood: MascotMood }) {
  switch (mood) {
    case "cheer":
      return (
        <>
          <path d="M 38 50 Q 46 42 54 50" fill="none" stroke={EYE_COLOR} strokeWidth="2.5" strokeLinecap="round" />
          <path d="M 66 50 Q 74 42 82 50" fill="none" stroke={EYE_COLOR} strokeWidth="2.5" strokeLinecap="round" />
        </>
      );
    case "sad":
      return (
        <>
          <circle cx="46" cy="52" r="3.5" fill={EYE_COLOR} />
          <circle cx="74" cy="52" r="3.5" fill={EYE_COLOR} />
          <path d="M 36 40 L 52 44" stroke={EYE_COLOR} strokeWidth="2" strokeLinecap="round" />
          <path d="M 84 40 L 68 44" stroke={EYE_COLOR} strokeWidth="2" strokeLinecap="round" />
        </>
      );
    case "think":
      return (
        <>
          <circle cx="46" cy="50" r="4" fill={EYE_COLOR} />
          <circle cx="47" cy="49" r="1.2" fill="#FFFFFF" />
          <path d="M 66 50 Q 74 48 82 50" fill="none" stroke={EYE_COLOR} strokeWidth="2" strokeLinecap="round" />
        </>
      );
    case "surprise":
      return (
        <>
          <circle cx="46" cy="50" r="6" fill={EYE_COLOR} />
          <circle cx="48" cy="48" r="1.8" fill="#FFFFFF" />
          <circle cx="74" cy="50" r="6" fill={EYE_COLOR} />
          <circle cx="76" cy="48" r="1.8" fill="#FFFFFF" />
        </>
      );
    case "proud":
      return (
        <>
          <circle cx="46" cy="50" r="4" fill={EYE_COLOR} />
          <circle cx="47.5" cy="48.5" r="1.5" fill="#FFFFFF" />
          <circle cx="44" cy="51" r="0.8" fill="#FFFFFF" />
          <circle cx="74" cy="50" r="4" fill={EYE_COLOR} />
          <circle cx="75.5" cy="48.5" r="1.5" fill="#FFFFFF" />
          <circle cx="72" cy="51" r="0.8" fill="#FFFFFF" />
          {/* 上扬眉毛 */}
          <path d="M 36 38 Q 44 34 54 40" stroke={EYE_COLOR} strokeWidth="2" strokeLinecap="round" fill="none" />
          <path d="M 84 38 Q 76 34 66 40" stroke={EYE_COLOR} strokeWidth="2" strokeLinecap="round" fill="none" />
        </>
      );
    case "embarrassed":
      return (
        <>
          <circle cx="46" cy="52" r="2.5" fill={EYE_COLOR} />
          <circle cx="74" cy="52" r="2.5" fill={EYE_COLOR} />
        </>
      );
    case "wave":
    case "happy":
    default:
      return (
        <>
          <circle cx="46" cy="50" r="4" fill={EYE_COLOR} />
          <circle cx="47.5" cy="48.5" r="1.2" fill="#FFFFFF" />
          <circle cx="74" cy="50" r="4" fill={EYE_COLOR} />
          <circle cx="75.5" cy="48.5" r="1.2" fill="#FFFFFF" />
        </>
      );
  }
}
