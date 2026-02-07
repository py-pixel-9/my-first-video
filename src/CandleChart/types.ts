import { z } from "zod";

// --- Data Types ---

export interface CandleData {
  open: number;
  high: number;
  low: number;
  close: number;
}

export interface TrendLineData {
  startIndex: number;
  startPrice: number;
  endIndex: number;
  endPrice: number;
  color?: string;
  strokeWidth?: number;
  dashArray?: string;
}

export interface ChannelData {
  upper: TrendLineData;
  lower: TrendLineData;
  fillColor?: string;
  fillOpacity?: number;
}

export type AnnotationType = "text" | "arrow" | "circle";

export interface AnnotationData {
  type: AnnotationType;
  index: number;
  price: number;
  text?: string;
  color?: string;
  fontSize?: number;
  radius?: number;
  arrowDirection?: "up" | "down" | "left" | "right";
  arrowLength?: number;
  appearFrame?: number;
}

export interface TimingConfig {
  candleInterval: number;
  trendLineDelay: number;
  trendLineDuration: number;
  annotationDelay: number;
}

export interface PanConfig {
  enabled: boolean;
  visibleCandles: number;
  leadCandles: number;
}

export interface ThemeConfig {
  background: string;
  gridColor: string;
  bullishColor: string;
  bearishColor: string;
  textColor: string;
  trendLineColor: string;
  channelFillColor: string;
  annotationColor: string;
  fontFamily: string;
}

export interface ChartPadding {
  top: number;
  right: number;
  bottom: number;
  left: number;
}

export interface ScaleContext {
  xScale: (index: number) => number;
  yScale: (price: number) => number;
  candleSlotWidth: number;
  candleBodyWidth: number;
  priceMin: number;
  priceMax: number;
  chartArea: { x: number; y: number; width: number; height: number };
}

// --- Zod Schemas ---

const candleDataSchema = z.object({
  open: z.number(),
  high: z.number(),
  low: z.number(),
  close: z.number(),
});

const trendLineDataSchema = z.object({
  startIndex: z.number(),
  startPrice: z.number(),
  endIndex: z.number(),
  endPrice: z.number(),
  color: z.string().optional(),
  strokeWidth: z.number().optional(),
  dashArray: z.string().optional(),
});

const channelDataSchema = z.object({
  upper: trendLineDataSchema,
  lower: trendLineDataSchema,
  fillColor: z.string().optional(),
  fillOpacity: z.number().optional(),
});

const annotationDataSchema = z.object({
  type: z.enum(["text", "arrow", "circle"]),
  index: z.number(),
  price: z.number(),
  text: z.string().optional(),
  color: z.string().optional(),
  fontSize: z.number().optional(),
  radius: z.number().optional(),
  arrowDirection: z.enum(["up", "down", "left", "right"]).optional(),
  arrowLength: z.number().optional(),
  appearFrame: z.number().optional(),
});

const timingConfigSchema = z.object({
  candleInterval: z.number(),
  trendLineDelay: z.number(),
  trendLineDuration: z.number(),
  annotationDelay: z.number(),
});

const themeConfigSchema = z.object({
  background: z.string(),
  gridColor: z.string(),
  bullishColor: z.string(),
  bearishColor: z.string(),
  textColor: z.string(),
  trendLineColor: z.string(),
  channelFillColor: z.string(),
  annotationColor: z.string(),
  fontFamily: z.string(),
});

const panConfigSchema = z.object({
  enabled: z.boolean(),
  visibleCandles: z.number(),
  leadCandles: z.number(),
});

export const chartSceneSchema = z.object({
  candles: z.array(candleDataSchema),
  trendLines: z.array(trendLineDataSchema).optional(),
  channels: z.array(channelDataSchema).optional(),
  annotations: z.array(annotationDataSchema).optional(),
  timing: timingConfigSchema.partial().optional(),
  theme: themeConfigSchema.partial().optional(),
  pan: panConfigSchema.partial().optional(),
});

export type ChartSceneProps = z.infer<typeof chartSceneSchema>;
