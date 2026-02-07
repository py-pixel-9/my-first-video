import React from "react";
import type { CandleData, ScaleContext, ThemeConfig, TimingConfig } from "../types";
import { Candle } from "./Candle";
import { ChartGrid } from "./ChartGrid";

export const CandleChart: React.FC<{
  candles: CandleData[];
  scale: ScaleContext;
  theme: ThemeConfig;
  timing: TimingConfig;
  compositionWidth: number;
  compositionHeight: number;
  viewBox?: string;
}> = ({ candles, scale, theme, timing, compositionWidth, compositionHeight, viewBox }) => {
  const vb = viewBox ?? `0 0 ${compositionWidth} ${compositionHeight}`;

  return (
    <>
      <ChartGrid
        scale={scale}
        theme={theme}
        compositionWidth={compositionWidth}
        compositionHeight={compositionHeight}
        viewBox={vb}
      />
      <svg
        viewBox={vb}
        style={{ position: "absolute", top: 0, left: 0, width: "100%", height: "100%" }}
      >
        {candles.map((candle, i) => (
          <Candle
            key={i}
            candle={candle}
            index={i}
            scale={scale}
            theme={theme}
            appearFrame={i * timing.candleInterval}
          />
        ))}
      </svg>
    </>
  );
};
