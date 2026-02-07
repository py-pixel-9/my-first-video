import React, { useMemo } from "react";
import {
  AbsoluteFill,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import {
  DEFAULT_PADDING,
  DEFAULT_PAN,
  DEFAULT_THEME,
  DEFAULT_TIMING,
} from "../constants";
import type {
  ChartSceneProps,
  PanConfig,
  ThemeConfig,
  TimingConfig,
} from "../types";
import { computeScale } from "../utils/scaling";
import { Annotation, SvgAnnotation } from "./Annotation";
import { CandleChart } from "./CandleChart";
import { Channel } from "./Channel";
import { TrendLine } from "./TrendLine";

export const ChartScene: React.FC<ChartSceneProps> = ({
  candles,
  trendLines,
  channels,
  annotations,
  timing: timingOverride,
  theme: themeOverride,
  pan: panOverride,
}) => {
  const { width, height } = useVideoConfig();
  const frame = useCurrentFrame();

  const theme: ThemeConfig = useMemo(
    () => ({ ...DEFAULT_THEME, ...themeOverride }),
    [themeOverride],
  );

  const timing: TimingConfig = useMemo(
    () => ({ ...DEFAULT_TIMING, ...timingOverride }),
    [timingOverride],
  );

  const pan: PanConfig = useMemo(
    () => ({ ...DEFAULT_PAN, ...panOverride }),
    [panOverride],
  );

  const usePan = pan.enabled;

  const scale = useMemo(
    () => computeScale(candles, width, height, DEFAULT_PADDING, usePan ? pan : undefined),
    [candles, width, height, pan, usePan],
  );

  const getCandleAppearFrame = (index: number) => index * timing.candleInterval;

  const getLineAppearFrame = (startIdx: number, endIdx: number) =>
    getCandleAppearFrame(Math.max(startIdx, endIdx)) + timing.trendLineDelay;

  // --- Pan camera: viewBox X shifts to follow the latest candle ---
  const totalSvgWidth = scale.candleSlotWidth * candles.length + DEFAULT_PADDING.left + DEFAULT_PADDING.right;

  const cameraX = (() => {
    if (!usePan) return 0;

    // Which candle is currently appearing
    const currentCandleFloat = frame / timing.candleInterval;
    // We want the newest candle to be `leadCandles` slots from the right edge
    // So the left edge of the viewport shows candle at index: currentCandle - (visibleCandles - leadCandles)
    const leftEdgeCandle = currentCandleFloat - (pan.visibleCandles - pan.leadCandles);
    const targetX = DEFAULT_PADDING.left + leftEdgeCandle * scale.candleSlotWidth;

    // Clamp: don't scroll before chart start, don't scroll past chart end
    const maxScroll = totalSvgWidth - width;
    return Math.max(0, Math.min(targetX, Math.max(0, maxScroll)));
  })();

  const viewBoxStr = usePan
    ? `${cameraX} 0 ${width} ${height}`
    : `0 0 ${width} ${height}`;

  const textAnnotations = (annotations ?? []).filter((a) => a.type === "text");
  const svgAnnotations = (annotations ?? []).filter((a) => a.type !== "text");

  return (
    <AbsoluteFill style={{ backgroundColor: theme.background, overflow: "hidden" }}>
      {/* Layer 1: Grid + Candles */}
      <AbsoluteFill>
        <CandleChart
          candles={candles}
          scale={scale}
          theme={theme}
          timing={timing}
          compositionWidth={totalSvgWidth}
          compositionHeight={height}
          viewBox={viewBoxStr}
        />
      </AbsoluteFill>

      {/* Layer 2: Channels + TrendLines + SVG Annotations */}
      <AbsoluteFill>
        <svg
          viewBox={viewBoxStr}
          style={{ position: "absolute", top: 0, left: 0, width: "100%", height: "100%" }}
        >
          {(channels ?? []).map((ch, i) => (
            <Channel
              key={`ch-${i}`}
              channel={ch}
              scale={scale}
              theme={theme}
              appearFrame={getLineAppearFrame(
                Math.min(ch.upper.startIndex, ch.lower.startIndex),
                Math.max(ch.upper.endIndex, ch.lower.endIndex),
              )}
              duration={timing.trendLineDuration}
            />
          ))}
          {(trendLines ?? []).map((line, i) => (
            <TrendLine
              key={`tl-${i}`}
              line={line}
              scale={scale}
              theme={theme}
              appearFrame={getLineAppearFrame(line.startIndex, line.endIndex)}
              duration={timing.trendLineDuration}
            />
          ))}
          {svgAnnotations.map((ann, i) => (
            <SvgAnnotation
              key={`svgann-${i}`}
              annotation={ann}
              scale={scale}
              theme={theme}
              appearFrame={
                ann.appearFrame ??
                getCandleAppearFrame(ann.index) + timing.annotationDelay
              }
            />
          ))}
        </svg>
      </AbsoluteFill>

      {/* Layer 3: Text annotations (HTML) - translate with camera */}
      <AbsoluteFill style={{ overflow: "hidden" }}>
        <div
          style={{
            position: "absolute",
            top: 0,
            left: 0,
            width: totalSvgWidth,
            height: "100%",
            transform: `translateX(${-cameraX}px)`,
          }}
        >
          {textAnnotations.map((ann, i) => (
            <Annotation
              key={`ann-${i}`}
              annotation={ann}
              scale={scale}
              theme={theme}
              appearFrame={
                ann.appearFrame ??
                getCandleAppearFrame(ann.index) + timing.annotationDelay
              }
            />
          ))}
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
