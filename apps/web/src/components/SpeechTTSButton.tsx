"use client";

import { useState, useEffect } from "react";
import { Volume } from "@/components/icons";
import { cn } from "@/lib/cn";
import { speakText, stopSpeaking, isSpeechSupported } from "@/lib/speechTts";

interface SpeechTTSButtonProps {
  text: string;
  lang?: string;
  rate?: number;
  size?: "sm" | "md";
  className?: string;
  label?: string;
}

export function SpeechTTSButton({
  text,
  lang = "zh-CN",
  rate = 1,
  size = "md",
  className,
  label = "朗读",
}: SpeechTTSButtonProps) {
  const [playing, setPlaying] = useState(false);

  useEffect(() => {
    return () => {
      if (playing) stopSpeaking();
    };
  }, [playing]);

  if (!isSpeechSupported() || !text) return null;

  function handleClick(e: React.MouseEvent) {
    e.stopPropagation();
    e.preventDefault();
    if (playing) {
      stopSpeaking();
      setPlaying(false);
      return;
    }
    setPlaying(true);
    speakText(text, {
      lang,
      rate,
      onEnd: () => setPlaying(false),
    });
  }

  const dim = size === "sm" ? "w-7 h-7" : "w-9 h-9";
  const icon = size === "sm" ? "w-4 h-4" : "w-5 h-5";

  return (
    <span
      role="button"
      tabIndex={0}
      aria-label={label}
      onClick={handleClick}
      onKeyDown={(e: React.KeyboardEvent) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          handleClick(e as unknown as React.MouseEvent);
        }
      }}
      className={cn(
        "inline-flex items-center justify-center rounded-full cursor-pointer",
        "bg-bg-soft text-primary hover:bg-primary/10 transition-colors shrink-0",
        dim,
        playing && "animate-pulse text-primary",
        className,
      )}
    >
      <Volume className={icon} />
    </span>
  );
}
