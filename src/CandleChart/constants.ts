import type { ChartPadding, PanConfig, ThemeConfig, TimingConfig } from "./types";

export const DEFAULT_THEME: ThemeConfig = {
  background: "#0a0a0a",
  gridColor: "#1a1a1a",
  bullishColor: "#26a69a",
  bearishColor: "#ef5350",
  textColor: "#555555",
  trendLineColor: "#FFD700",
  channelFillColor: "#FFD700",
  annotationColor: "#ffffff",
  fontFamily: "monospace",
};

export const DEFAULT_TIMING: TimingConfig = {
  candleInterval: 4,
  trendLineDelay: 5,
  trendLineDuration: 20,
  annotationDelay: 10,
};

export const DEFAULT_PADDING: ChartPadding = {
  top: 60,
  right: 80,
  bottom: 60,
  left: 20,
};

export const DEFAULT_PAN: PanConfig = {
  enabled: true,
  visibleCandles: 12,
  leadCandles: 3,
};

export const CANDLE_WIDTH_RATIO = 0.6;
export const WICK_WIDTH = 2;
export const PRICE_PADDING_RATIO = 0.05;
