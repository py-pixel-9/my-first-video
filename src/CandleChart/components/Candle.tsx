import React from "react";
import { spring, useCurrentFrame, useVideoConfig } from "remotion";
import { WICK_WIDTH } from "../constants";
import type { CandleData, ScaleContext, ThemeConfig } from "../types";

export const Candle: React.FC<{
  candle: CandleData;
  index: number;
  scale: ScaleContext;
  theme: ThemeConfig;
  appearFrame: number;
}> = ({ candle, index, scale, theme, appearFrame }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const localFrame = frame - appearFrame;
  if (localFrame < 0) return null;

  const progress = spring({
    frame: localFrame,
    fps,
    config: { damping: 15, mass: 0.4, stiffness: 120 },
  });

  const isBullish = candle.close >= candle.open;
  const color = isBullish ? theme.bullishColor : theme.bearishColor;

  const cx = scale.xScale(index);
  const bodyTop = scale.yScale(Math.max(candle.open, candle.close));
  const bodyBottom = scale.yScale(Math.min(candle.open, candle.close));
  const bodyHeight = bodyBottom - bodyTop;
  const bodyMid = bodyTop + bodyHeight / 2;

  const wickTop = scale.yScale(candle.high);
  const wickBottom = scale.yScale(candle.low);

  const halfWidth = scale.candleBodyWidth / 2;

  return (
    <g
      style={{
        transform: `scaleY(${progress})`,
        transformOrigin: `0px ${bodyMid}px`,
        transformBox: "fill-box" as const,
      }}
      transform={`translate(0, 0)`}
    >
      {/* Upper wick */}
      <line
        x1={cx}
        y1={wickTop}
        x2={cx}
        y2={bodyTop}
        stroke={color}
        strokeWidth={WICK_WIDTH}
        opacity={progress}
      />
      {/* Lower wick */}
      <line
        x1={cx}
        y1={bodyBottom}
        x2={cx}
        y2={wickBottom}
        stroke={color}
        strokeWidth={WICK_WIDTH}
        opacity={progress}
      />
      {/* Body */}
      <rect
        x={cx - halfWidth}
        y={bodyTop}
        width={scale.candleBodyWidth}
        height={Math.max(bodyHeight, 1)}
        fill={color}
        opacity={progress}
      />
    </g>
  );
};
