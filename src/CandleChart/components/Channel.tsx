import React from "react";
import { interpolate, useCurrentFrame } from "remotion";
import type { ChannelData, ScaleContext, ThemeConfig } from "../types";
import { TrendLine } from "./TrendLine";

export const Channel: React.FC<{
  channel: ChannelData;
  scale: ScaleContext;
  theme: ThemeConfig;
  appearFrame: number;
  duration: number;
}> = ({ channel, scale, theme, appearFrame, duration }) => {
  const frame = useCurrentFrame();
  const localFrame = frame - appearFrame;

  const fillProgress =
    localFrame < 0
      ? 0
      : interpolate(localFrame, [0, duration], [0, 1], {
          extrapolateRight: "clamp",
        });

  const fillColor = channel.fillColor ?? theme.channelFillColor;
  const fillOpacity = (channel.fillOpacity ?? 0.08) * fillProgress;

  const points = [
    `${scale.xScale(channel.upper.startIndex)},${scale.yScale(channel.upper.startPrice)}`,
    `${scale.xScale(channel.upper.endIndex)},${scale.yScale(channel.upper.endPrice)}`,
    `${scale.xScale(channel.lower.endIndex)},${scale.yScale(channel.lower.endPrice)}`,
    `${scale.xScale(channel.lower.startIndex)},${scale.yScale(channel.lower.startPrice)}`,
  ].join(" ");

  return (
    <>
      <polygon points={points} fill={fillColor} opacity={fillOpacity} />
      <TrendLine
        line={channel.upper}
        scale={scale}
        theme={theme}
        appearFrame={appearFrame}
        duration={duration}
      />
      <TrendLine
        line={channel.lower}
        scale={scale}
        theme={theme}
        appearFrame={appearFrame}
        duration={duration}
      />
    </>
  );
};
