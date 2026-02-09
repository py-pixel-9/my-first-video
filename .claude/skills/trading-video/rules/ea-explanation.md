# EA Explanation Video Guide

## EA 설명 영상 제작 가이드

### 시각화 원칙
1. **로직을 플로우차트로** - 코드가 아닌 흐름도로 설명
2. **실제 차트 위에 시각화** - 캔들차트에 진입/청산 표시
3. **단계별 분해** - 복잡한 로직을 한 단계씩

### EA 분석 체크리스트
- [ ] EA 이름, 버전, 대상 상품
- [ ] 진입 조건 (Entry Condition)
- [ ] 청산 조건 (Exit Condition)
- [ ] 리스크 관리 (SL, TP, Trailing)
- [ ] 세션 필터 (아시안, 런던, 뉴욕)
- [ ] 파라미터 목록과 기본값
- [ ] 백테스트 결과 요약

### 현재 프로젝트 EA 목록

#### 1. EA_Gold_Algo_RE (XAUUSD Breakout)
- N봉 최고/최저 돌파 전략
- RSI 필터
- Buy Stop / Sell Stop 펜딩 주문
- Hard SL + Trailing Stop
- v2: Auto Risk%, Negative Gap, Breakeven 추가

#### 2. SMC_Breakout_EA (SMC 기반)
- Swing High/Low 멀티터치 지지/저항
- 3회 이상 터치된 레벨에서 돌파 대기
- 펜딩 주문 에이징/만료 시스템
- Spread 15, Slippage 5 제한

#### 3. GridTrader + EquityManager (RandomWalk 역공학)
- 6개 FX 통화쌍 그리드 트레이딩
- 시간 기반 진입 + 헤징
- Equity 기반 일괄 청산
- (현재 보완 필요)

### Remotion 영상 패턴
```
Composition 구조:
1. IntroScene (5초) - EA 이름 + 대상 상품
2. LogicFlowScene (15초) - 플로우차트 애니메이션
3. ChartDemoScene (20초) - 실제 차트 위 시뮬레이션
4. ParameterScene (10초) - 주요 파라미터 설명
5. BacktestScene (10초) - 성과 요약
```
