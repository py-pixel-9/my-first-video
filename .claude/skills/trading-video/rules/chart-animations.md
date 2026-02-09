# Chart Animations Guide

## 캔들차트 애니메이션 규칙

### 기본 구조
- 캔들은 좌→우로 순차적으로 나타나야 함
- 각 캔들 등장 시 fade-in + scale 애니메이션
- 양봉(초록/흰색), 음봉(빨강/검정) 색상 구분

### Breakout 표현
- Breakout 레벨은 점선으로 표시
- 돌파 시 레벨 라인이 하이라이트 (glow 효과)
- 돌파 후 화살표로 진입 방향 표시

### 지지/저항 표현
- 수평선으로 S/R 레벨 표시
- 터치 횟수 카운터 표시
- Multi-touch 시 라인 두께 증가

### 인디케이터
- RSI: 하단 서브차트, 30/70 레벨 표시
- MA: 부드러운 곡선, 캔들 위에 오버레이
- 볼린저밴드: 상/하단 채널 + 중심선

### Remotion 컴포넌트 패턴
```tsx
// 캔들 하나의 애니메이션
const candleOpacity = interpolate(frame, [startFrame, startFrame + 10], [0, 1]);
const candleScale = spring({ frame: frame - startFrame, fps, config: { damping: 12 } });
```

### 색상 팔레트 (다크 테마)
- 배경: #1a1a2e
- 양봉: #00d09c
- 음봉: #ff4757
- 그리드: #2d2d44
- 텍스트: #ffffff
- 강조: #ffd700
