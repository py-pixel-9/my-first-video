import type { ChartSceneProps } from "../types";

// 하방 채널 → 돌파 → 리테스트 → 상승 패턴
// 채널 기울기: 약 -1.0 per candle (상단), -1.0 per candle (하단)
// 상단선: (0, 106) → (11, 95)  하단선: (0, 100) → (11, 89)

export const DESCENDING_CHANNEL_BREAKOUT: ChartSceneProps = {
  candles: [
    // --- 하방 채널 구간 (0~11) ---
    { open: 105, high: 106, low: 102, close: 103 }, // 0: 음봉
    { open: 103, high: 105, low: 101, close: 104 }, // 1: 양봉
    { open: 104, high: 105, low: 100, close: 101 }, // 2: 음봉
    { open: 101, high: 103, low: 99, close: 102 },  // 3: 양봉
    { open: 102, high: 103, low: 98, close: 99 },   // 4: 음봉
    { open: 99, high: 101, low: 97, close: 100 },   // 5: 양봉
    { open: 100, high: 101, low: 96, close: 97 },   // 6: 음봉
    { open: 97, high: 99, low: 95, close: 98 },     // 7: 양봉
    { open: 98, high: 99, low: 94, close: 95 },     // 8: 음봉
    { open: 95, high: 97, low: 93, close: 96 },     // 9: 양봉
    { open: 96, high: 97, low: 92, close: 93 },     // 10: 음봉
    { open: 93, high: 95, low: 91, close: 92 },     // 11: 음봉 (채널 바닥)

    // --- 돌파 캔들 (12) ---
    { open: 92, high: 99, low: 91, close: 98 },     // 12: 강한 양봉, 상단선 돌파!

    // --- 돌파 후 상승 + 리테스트 (13~15) ---
    { open: 98, high: 100, low: 96, close: 97 },    // 13: 음봉 (되돌림 시작)
    { open: 97, high: 98, low: 93, close: 94 },     // 14: 음봉 (리테스트: 상단선 터치)
    { open: 94, high: 99, low: 93, close: 98 },     // 15: 양봉 (리테스트 후 반등)

    // --- 추세 전환 상승 (16~19) ---
    { open: 98, high: 102, low: 97, close: 101 },   // 16: 양봉
    { open: 101, high: 105, low: 100, close: 104 }, // 17: 양봉
    { open: 104, high: 107, low: 103, close: 106 }, // 18: 양봉
    { open: 106, high: 110, low: 105, close: 109 }, // 19: 양봉 (추세 확인)
  ],

  channels: [
    {
      upper: {
        startIndex: 0,
        startPrice: 106,
        endIndex: 14,
        endPrice: 92,
        color: "#FFD700",
        strokeWidth: 2,
      },
      lower: {
        startIndex: 0,
        startPrice: 100,
        endIndex: 14,
        endPrice: 86,
        color: "#FFD700",
        strokeWidth: 2,
      },
      fillOpacity: 0.06,
    },
  ],

  annotations: [
    {
      type: "circle",
      index: 12,
      price: 99,
      radius: 25,
      color: "#26a69a",
    },
    {
      type: "text",
      index: 12,
      price: 101,
      text: "돌파",
      fontSize: 28,
      color: "#26a69a",
    },
    {
      type: "circle",
      index: 14.5,
      price: 93.5,
      radius: 22,
      color: "#FFD700",
    },
    {
      type: "text",
      index: 14.5,
      price: 88,
      text: "리테스트",
      fontSize: 28,
      color: "#FFD700",
    },
    {
      type: "arrow",
      index: 15,
      price: 99,
      arrowDirection: "up",
      arrowLength: 35,
      color: "#26a69a",
    },
  ],

  timing: {
    candleInterval: 5,
    trendLineDelay: 3,
    trendLineDuration: 25,
    annotationDelay: 8,
  },

  pan: {
    enabled: true,
    visibleCandles: 10,
    leadCandles: 3,
  },
};
