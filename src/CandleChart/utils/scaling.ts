import {
  CANDLE_WIDTH_RATIO,
  DEFAULT_PADDING,
  PRICE_PADDING_RATIO,
} from "../constants";
import type { CandleData, ChartPadding, PanConfig, ScaleContext } from "../types";

export const computeScale = (
  candles: CandleData[],
  compositionWidth: number,
  compositionHeight: number,
  padding: ChartPadding = DEFAULT_PADDING,
  pan?: PanConfig,
): ScaleContext => {
  let rawMin = Infinity;
  let rawMax = -Infinity;

  for (const c of candles) {
    if (c.low < rawMin) rawMin = c.low;
    if (c.high > rawMax) rawMax = c.high;
  }

  const range = rawMax - rawMin;
  const pricePadding = range * PRICE_PADDING_RATIO;
  const priceMin = rawMin - pricePadding;
  const priceMax = rawMax + pricePadding;

  const chartHeight = compositionHeight - padding.top - padding.bottom;
  const viewableWidth = compositionWidth - padding.left - padding.right;

  // Pan mode: slot width = screen width / visibleCandles
  //   → total chart is wider than screen, camera pans across
  // Normal mode: fit all candles in screen
  const usePan = pan?.enabled ?? false;
  const candleSlotWidth = usePan
    ? viewableWidth / pan!.visibleCandles
    : viewableWidth / candles.length;

  const totalChartWidth = candleSlotWidth * candles.length;
  const candleBodyWidth = candleSlotWidth * CANDLE_WIDTH_RATIO;

  const chartArea = {
    x: padding.left,
    y: padding.top,
    width: totalChartWidth,
    height: chartHeight,
  };

  const xScale = (index: number): number =>
    chartArea.x + (index + 0.5) * candleSlotWidth;

  const yScale = (price: number): number =>
    chartArea.y +
    chartArea.height -
    ((price - priceMin) / (priceMax - priceMin)) * chartArea.height;

  return {
    xScale,
    yScale,
    candleSlotWidth,
    candleBodyWidth,
    priceMin,
    priceMax,
    chartArea,
  };
};
