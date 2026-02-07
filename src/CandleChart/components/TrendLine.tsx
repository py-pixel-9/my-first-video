import React from "react";
import { interpolate, useCurrentFrame } from "remotion";
import type { ScaleContext, ThemeConfig, TrendLineData } from "../types";

export const TrendLine: React.FC<{
  line: TrendLineData;
  scale: ScaleContext;
  theme: ThemeConfig;
  appearFrame: number;
  duration: number;
}> = ({ line, scale, theme, appearFrame, duration }) => {
  const frame = useCurrentFrame();
  const localFrame = frame - appearFrame;
  if (localFrame < 0) return null;

  const progress = interpolate(localFrame, [0, duration], [0, 1], {
    extrapolateRight: "clamp",
  });

  const x1 = scale.xScale(line.startIndex);
  const y1 = scale.yScale(line.startPrice);
  const x2 = scale.xScale(line.endIndex);
  const y2 = scale.yScale(line.endPrice);

  const length = Math.sqrt((x2 - x1) ** 2 + (y2 - y1) ** 2);
  const color = line.color ?? theme.trendLineColor;
  const strokeWidth = line.strokeWidth ?? 2;

  return (
    <line
      x1={x1}
      y1={y1}
      x2={x2}
      y2={y2}
      stroke={color}
      strokeWidth={strokeWidth}
      strokeDasharray={length}
      strokeDashoffset={length * (1 - progress)}
      strokeLinecap="round"
    />
  );
};
