# Project Context - Trading Strategy & ML Research

## Owner
- GitHub: py-pixel-9
- Repo: https://github.com/py-pixel-9/my-first-video

## PC Environment
- **Windows PC**: AMD Ryzen 5 3600, 16GB RAM, RTX 2060 SUPER 8GB, 233GB SSD (36GB free), Windows x64
- **Mac Mini**: Apple Silicon M-series, 16GB RAM
- Claude Code Desktop App (Windows) + Cowork feature available

## Project Structure
- `/mt4-ea/` - MetaTrader 4 Expert Advisors (MQL4)
  - SMC_Breakout_EA.mq4 - SMC 돌파매매 EA (v5.0+, breach cancel 기능)
  - **VWAP_Breakout_EA.mq4** - ML v2.1 전략 룰 기반 변환 EA (NEW)
  - EA_Gold_Algo series - 금 알고리즘 EA
- `/src/` - Remotion (React video framework)
  - Trading intro video components
- `/trading_strategies_report.html` - 전 세계 트레이딩 전략 12가지 기획안 (8개 카테고리)
- `/ml_trading_guide.html` - ML 트레이딩 완전 가이드 (12개 섹션)
- `/ml_result_report.html` - ML v1 결과 리포트 (67.2% 정확도)

## Current Focus: ML Trading Research (2026.02)

### ML VWAP Breakout 개발 히스토리

#### v1 (baseline)
- **교차검증**: 0.672 (단일 분할)
- **데이터**: yfinance 60일 XAUUSD 15분봉, 4370 캔들
- **돌파**: 236건 감지
- **라벨**: 10봉 후 +0.1% = real breakout
- **피처**: 22개 (VWAP, Volume Profile, 모멘텀, 변동성, 캔들, 속도/가속도, 거래량)
- **결과**: 67.2% 정확도, feature importance top = price_vs_vwap, ADX, MACD_norm
- **파일**: ~/ml-trading/vwap_breakout_ml.py (Mac Mini, OpenClaw 실행)

#### v2 (세션 필터 + 클래스 보정) ❌ 실패
- **교차검증**: 0.505 (±0.141) - v1 대비 하락
- **원인**: 아시아 세션 제거로 데이터 33% 감소 → 학습 데이터 부족
- **교훈**: 60일 데이터에서 데이터를 줄이는 건 역효과
- **발견**: 골든타임(런던+뉴욕 겹침) 돌파 성공률이 가장 낮음 (37.6%) - 유동성 사냥
- **파일**: ~/ml-trading/vwap_breakout_ml_v2.py

#### v2.1 (v1 베이스 + 세션피처 + 상위TF + 라벨강화) ✅ 현재 최고
- **교차검증**: 0.624 (±0.094) - 5-Fold
- **데이터**: 전체 유지 (세션 필터 제거 → 피처로만 사용)
- **돌파**: 301건
- **라벨**: 10봉 후 +0.2%
- **새 피처 7개**: is_golden_hour, is_asia, session_type, trend_1h, trend_strength_1h, ADX_1h, trend_align
- **총 피처**: 29개
- **피처 중요도**: is_london > is_golden_hour > trend_strength_1h > price_vs_vwap
- **세션별 성공률**: 아시아 49.6% > 런던/뉴욕 41.8% > 골든타임 27.6%
- **추세 일치 분석**: 추세 방향 돌파가 역추세보다 유리
- **파일**: ~/ml-trading/vwap_breakout_ml_v2_1.py

#### v2.2 (라벨 그리드서치 결과 적용) ❌ 하락
- **교차검증**: 0.496 (±0.149) - v2.1 대비 하락
- **라벨**: 20봉 후 +0.1% (그리드서치 F1 최고 조합)
- **원인**: 20봉(5시간)은 예측 범위가 너무 김 → 노이즈 증가
- **교훈**: 그리드서치 최적 조합이 항상 실전 최적은 아님 (과최적화 위험)
- **파일**: ~/ml-trading/vwap_breakout_ml_v2_2.py (OpenClaw 자체 완성)

#### 라벨 그리드서치 결과
- 테스트: 6 horizons × 8 thresholds = 48 조합
- **F1 최고**: 20봉/0.10% → 실제 적용 시 하락
- **Accuracy 최고**: 5봉/0.50% → 함정 (Real 8.8%, F1 0.067)
- **파일**: ~/ml-trading/vwap_breakout_label_search.py

### 결론: v2.1이 최고 성능
- **v2.1 (10봉/0.2%, 전체 데이터, 세션+상위TF 피처)이 가장 좋은 결과**
- 이를 기반으로 MQL4 EA 생성 완료 (VWAP_Breakout_EA.mq4)

### MQL4 EA - VWAP_Breakout_EA.mq4
- v2.1 ML 전략을 룰 기반으로 변환
- **진입 조건**: 20봉 고/저점 돌파 + VWAP 위치 + 거래량 + ADX + RSI + 1H추세 일치
- **추가 필터**: VWAP 거리 제한 (0.5%), 골든타임 ADX 강화 (25), 재진입 쿨다운 (5봉)
- **패널**: VWAP, ADX, RSI, 1H추세, 세션, P/L 실시간 표시
- **백테스트 대기 중** → 사용자가 MT4 틱 데이터로 테스트 예정

---

## 다음 단계 (로컬 PC에서 진행)

### 즉시 할 일
1. **Windows PC에 Python 환경 세팅** (5분)
   - Python 3.11+ 설치
   - pip install: xgboost, scikit-learn, pandas, numpy, yfinance
   - Claude Code에서 직접 실행 가능하도록 설정

2. **v2.1 기반 개선 작업** (Claude Code가 직접 실행)
   - early_stopping 적용 → Fold별 안정성 개선
   - Walk-Forward 검증 → 시간 흐름에 따른 실제 성능 측정
   - 확률 교정 (Platt scaling) → 시그널 확률 정확도 향상

3. **VWAP_Breakout_EA.mq4 백테스트** (사용자가 MT4에서)
   - XAUUSD M15, 틱 데이터
   - ServerUTC_Offset 브로커에 맞게 조정
   - 결과 피드백 → 다음 개선에 반영

### 워크플로우 변경
- **이전**: Claude → 코드 작성 → 사용자 복사 → OpenClaw 실행 → 결과 복사
- **이후**: Claude Code가 직접 Python 실행 → 결과 자동 분석 → MQL4 변환 → 사용자는 백테스트만

### 전략 확장 계획 (3~4개씩 나눠서)
- [세션 1] v2.1 개선 (early_stopping, walk-forward) → MQL4 → 백테스트
- [세션 2] 백테스트 피드백 기반 다음 전략들 → MQL4 → 백테스트
- [세션 3] 최종 최적화 + 실전 전략 확정

---

## Completed Topics
1. **Trading Strategies Report** (trading_strategies_report.html)
   - 8 categories, 12 strategies

2. **ML Trading Guide** (ml_trading_guide.html)
   - 12 sections: ML basics → overfitting → ML vs DL → CNN/GPU → Breakout+ML

3. **ML Result Report** (ml_result_report.html)
   - v1 결과 시각화 리포트

### Key Learnings & Decisions
- User prefers **breakout trading** (돌파매매) but suffers losses in ranging markets (횡보장)
- Main interest: Using ML to **distinguish real vs fake breakouts**
- **Indicator velocity/acceleration** (1st/2nd derivatives) = leading signals
- Feature engineering: **ratios/percentages, NOT absolute prices**
- Walk-forward validation preferred
- **세션을 "필터"가 아닌 "피처"로 사용하는 게 효과적** (v2 교훈)
- **골든타임은 유동성 사냥이 많아 돌파 성공률 최저** (27.6%)
- **아시아 세션 돌파가 의외로 성공률 최고** (49.6%)
- **1H 추세 일치 돌파가 역추세보다 유리**
- **라벨 그리드서치 결과가 항상 실전 최적은 아님** (과최적화 주의)
- **데이터 부족 시 필터링보다 피처화가 효과적**

### User's Knowledge Level
- Understands: RSI, MACD, ADX, candlestick patterns, VWAP, Volume Profile
- Learning: ML/DL concepts, Python, XGBoost, feature engineering
- Has: TickStory tick data, MT4
- Workflow: Claude Code 직접 실행 (OpenClaw 불필요)

### Coding Preferences
- HTML reports: Dark theme, CSS-only visuals, Korean language
- Commit style: `feat:` prefix, Korean+English descriptions
- MQL4 for MT4 EAs
- Python ML: XGBoost, scikit-learn, pandas
