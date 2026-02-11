import React from "react";
import {
  AbsoluteFill,
  useCurrentFrame,
  useVideoConfig,
  interpolate,
  spring,
  Easing,
} from "remotion";

// ─── 가격 라인 데이터 (골드 느낌의 상승 차트) ───
const PRICE_POINTS = [
  40, 38, 42, 36, 44, 41, 47, 43, 50, 46, 53, 49, 56, 52, 58, 55, 62, 58, 65,
  61, 68, 72, 66, 74, 70, 78, 73, 80, 76, 84, 88, 82, 90, 86, 94, 91, 96, 100,
];

export const TradingIntro: React.FC<{
  channelName?: string;
  tagline?: string;
  accentColor?: string;
}> = ({
  channelName = "YHH TRADING",
  tagline = "ALGORITHMIC GOLD TRADING",
  accentColor = "#FFD700",
}) => {
  const frame = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();

  // ─── 타이밍 (5초 = 150프레임 @30fps) ───
  // 0~30f:   배경 + 가격 라인 드로잉
  // 20~50f:  캔들 스캔라인 효과
  // 40~80f:  채널 이름 등장
  // 60~90f:  태그라인 등장
  // 100~130f: 글로우 플래시
  // 120~150f: 페이드아웃

  // ─── 배경 그라데이션 펄스 ───
  const bgPulse = interpolate(frame, [0, 75, 150], [0, 0.3, 0], {
    extrapolateRight: "clamp",
  });

  // ─── 가격 라인 드로잉 애니메이션 ───
  const lineProgress = interpolate(frame, [0, 60], [0, 1], {
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  const buildPricePath = () => {
    const segmentWidth = width / (PRICE_POINTS.length - 1);
    const minP = Math.min(...PRICE_POINTS);
    const maxP = Math.max(...PRICE_POINTS);
    const chartHeight = height * 0.4;
    const chartTop = height * 0.3;

    const totalPoints = Math.floor(lineProgress * PRICE_POINTS.length);

    const points = PRICE_POINTS.slice(0, totalPoints + 1).map((p, i) => {
      const x = i * segmentWidth;
      const y = chartTop + chartHeight - ((p - minP) / (maxP - minP)) * chartHeight;
      return `${i === 0 ? "M" : "L"} ${x} ${y}`;
    });

    return points.join(" ");
  };

  // ─── 스캔라인 효과 ───
  const scanLineY = interpolate(frame, [15, 80], [-100, height + 100], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // ─── 채널 이름 애니메이션 ───
  const nameSpring = spring({
    frame: frame - 40,
    fps,
    config: { damping: 12, stiffness: 100 },
  });

  const nameOpacity = interpolate(frame, [40, 55], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const nameY = interpolate(nameSpring, [0, 1], [40, 0]);

  // ─── 태그라인 애니메이션 ───
  const tagOpacity = interpolate(frame, [65, 80], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const tagWidth = interpolate(frame, [65, 90], [0, 100], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  // ─── 골드 글로우 플래시 ───
  const flashOpacity = interpolate(
    frame,
    [100, 110, 120],
    [0, 0.6, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
  );

  // ─── 전체 페이드아웃 ───
  const fadeOut = interpolate(frame, [130, 150], [1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // ─── 수평 구분선 애니메이션 ───
  const lineWidth = interpolate(frame, [35, 65], [0, 400], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  // ─── 좌우 데코 입자들 ───
  const particles = Array.from({ length: 20 }, (_, i) => {
    const startFrame = 10 + i * 4;
    const x = (i % 2 === 0 ? 0.1 : 0.9) * width + (Math.sin(i * 2.5) * 100);
    const baseY = height * 0.2 + (i * height * 0.6) / 20;
    const particleOpacity = interpolate(
      frame,
      [startFrame, startFrame + 15, startFrame + 50],
      [0, 0.6, 0],
      { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
    );
    const drift = interpolate(frame, [startFrame, startFrame + 50], [0, -30], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    });
    return { x, y: baseY + drift, opacity: particleOpacity, size: 2 + (i % 3) };
  });

  return (
    <AbsoluteFill style={{ opacity: fadeOut }}>
      {/* 배경 */}
      <AbsoluteFill
        style={{
          background: `radial-gradient(ellipse at 50% 50%,
            rgba(26, 20, 0, ${0.8 + bgPulse}) 0%,
            #0a0a0a 70%,
            #000000 100%)`,
        }}
      />

      {/* 미세한 그리드 패턴 */}
      <AbsoluteFill style={{ opacity: 0.06 }}>
        <svg width={width} height={height}>
          {Array.from({ length: 40 }, (_, i) => (
            <line
              key={`vg-${i}`}
              x1={i * (width / 40)}
              y1={0}
              x2={i * (width / 40)}
              y2={height}
              stroke="#FFD700"
              strokeWidth={0.5}
            />
          ))}
          {Array.from({ length: 22 }, (_, i) => (
            <line
              key={`hg-${i}`}
              x1={0}
              y1={i * (height / 22)}
              x2={width}
              y2={i * (height / 22)}
              stroke="#FFD700"
              strokeWidth={0.5}
            />
          ))}
        </svg>
      </AbsoluteFill>

      {/* 가격 라인 */}
      <AbsoluteFill>
        <svg width={width} height={height}>
          <defs>
            <linearGradient id="lineGrad" x1="0%" y1="0%" x2="100%" y2="0%">
              <stop offset="0%" stopColor={accentColor} stopOpacity={0.3} />
              <stop offset="50%" stopColor={accentColor} stopOpacity={1} />
              <stop offset="100%" stopColor="#FFF8DC" stopOpacity={1} />
            </linearGradient>
            <filter id="lineGlow">
              <feGaussianBlur stdDeviation="4" result="blur" />
              <feMerge>
                <feMergeNode in="blur" />
                <feMergeNode in="SourceGraphic" />
              </feMerge>
            </filter>
          </defs>
          {/* 글로우 레이어 */}
          <path
            d={buildPricePath()}
            fill="none"
            stroke={accentColor}
            strokeWidth={6}
            opacity={0.3}
            filter="url(#lineGlow)"
          />
          {/* 메인 라인 */}
          <path
            d={buildPricePath()}
            fill="none"
            stroke="url(#lineGrad)"
            strokeWidth={2.5}
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        </svg>
      </AbsoluteFill>

      {/* 스캔라인 */}
      <AbsoluteFill style={{ opacity: 0.15 }}>
        <div
          style={{
            position: "absolute",
            top: scanLineY,
            left: 0,
            width: "100%",
            height: 2,
            background: `linear-gradient(90deg, transparent, ${accentColor}, transparent)`,
            boxShadow: `0 0 40px 20px ${accentColor}40`,
          }}
        />
      </AbsoluteFill>

      {/* 파티클 */}
      <AbsoluteFill>
        {particles.map((p, i) => (
          <div
            key={`p-${i}`}
            style={{
              position: "absolute",
              left: p.x,
              top: p.y,
              width: p.size,
              height: p.size,
              borderRadius: "50%",
              backgroundColor: accentColor,
              opacity: p.opacity,
              boxShadow: `0 0 ${p.size * 3}px ${accentColor}`,
            }}
          />
        ))}
      </AbsoluteFill>

      {/* 메인 텍스트 영역 */}
      <AbsoluteFill
        style={{
          justifyContent: "center",
          alignItems: "center",
        }}
      >
        {/* 채널 이름 */}
        <div
          style={{
            opacity: nameOpacity,
            transform: `translateY(${nameY}px)`,
            textAlign: "center",
          }}
        >
          <div
            style={{
              fontSize: 88,
              fontWeight: 900,
              fontFamily: "'Arial Black', 'Impact', sans-serif",
              color: "white",
              letterSpacing: 12,
              textShadow: `0 0 40px ${accentColor}80, 0 0 80px ${accentColor}40`,
            }}
          >
            {channelName}
          </div>
        </div>

        {/* 구분선 */}
        <div
          style={{
            width: lineWidth,
            height: 2,
            background: `linear-gradient(90deg, transparent, ${accentColor}, transparent)`,
            marginTop: 16,
            marginBottom: 16,
          }}
        />

        {/* 태그라인 */}
        <div
          style={{
            opacity: tagOpacity,
            overflow: "hidden",
            textAlign: "center",
          }}
        >
          <div
            style={{
              fontSize: 24,
              fontWeight: 400,
              fontFamily: "'Consolas', 'Courier New', monospace",
              color: accentColor,
              letterSpacing: 8,
              width: `${tagWidth}%`,
              margin: "0 auto",
              whiteSpace: "nowrap",
              overflow: "hidden",
            }}
          >
            {tagline}
          </div>
        </div>
      </AbsoluteFill>

      {/* 골드 글로우 플래시 */}
      <AbsoluteFill
        style={{
          background: `radial-gradient(circle at 50% 50%, ${accentColor}60 0%, transparent 60%)`,
          opacity: flashOpacity,
        }}
      />
    </AbsoluteFill>
  );
};
