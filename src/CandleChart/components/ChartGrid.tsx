import React from "react";
import type { ScaleContext, ThemeConfig } from "../types";

const getNiceStep = (range: number, targetLines: number): number => {
  const rough = range / targetLines;
  const magnitude = Math.pow(10, Math.floor(Math.log10(rough)));
  const residual = rough / magnitude;
  if (residual <= 1.5) return magnitude;
  if (residual <= 3) return 2 * magnitude;
  if (residual <= 7) return 5 * magnitude;
  return 10 * magnitude;
};

export const ChartGrid: React.FC<{
  scale: ScaleContext;
  theme: ThemeConfig;
  compositionWidth: number;
  compositionHeight: number;
  viewBox?: string;
}> = ({ scale, theme, compositionWidth, compositionHeight, viewBox }) => {
  const { chartArea, priceMin, priceMax } = scale;

  const step = getNiceStep(priceMax - priceMin, 8);
  const firstPrice = Math.ceil(priceMin / step) * step;

  const hLines: number[] = [];
  for (let p = firstPrice; p <= priceMax; p += step) {
    hLines.push(p);
  }

  const vb = viewBox ?? `0 0 ${compositionWidth} ${compositionHeight}`;

  return (
    <svg
      viewBox={vb}
      style={{ position: "absolute", top: 0, left: 0, width: "100%", height: "100%" }}
    >
      {hLines.map((price) => {
        const y = scale.yScale(price);
        return (
          <React.Fragment key={price}>
            <line
              x1={chartArea.x}
              y1={y}
              x2={chartArea.x + chartArea.width}
              y2={y}
              stroke={theme.gridColor}
              strokeWidth={1}
            />
            <text
              x={chartArea.x + chartArea.width + 8}
              y={y + 4}
              fill={theme.textColor}
              fontSize={13}
              fontFamily={theme.fontFamily}
            >
              {price.toFixed(step < 1 ? 2 : 0)}
            </text>
          </React.Fragment>
        );
      })}
    </svg>
  );
};
