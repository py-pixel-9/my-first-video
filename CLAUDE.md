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
  - EA_Gold_Algo series - 금 알고리즘 EA
- `/src/` - Remotion (React video framework)
  - Trading intro video components
- `/trading_strategies_report.html` - 전 세계 트레이딩 전략 12가지 기획안 (8개 카테고리)
- `/ml_trading_guide.html` - ML 트레이딩 완전 가이드 (12개 섹션)

## Current Focus: ML Trading Research (2026.02)

### Completed Topics
1. **Trading Strategies Report** (trading_strategies_report.html)
   - 8 categories, 12 strategies (추세추종, 평균회귀, SMC/ICT, 프라이스액션, 수급, 퀀트, 파동, 스캘핑)
   - Comparison table + 5 combo ideas

2. **ML Trading Guide** (ml_trading_guide.html)
   - Section 1-8: ML basics, features as numbers, learning process, model types, chart pattern recognition, full pipeline, real-world implementation, tools & costs
   - Section 9: Overfitting deep-dive (XAUUSD $2000→$5000 scale issue, walk-forward validation, normalized features)
   - Section 10: ML vs Deep Learning differences
   - Section 11: CNN & GPU requirements (RTX 2060 SUPER = fully capable)
   - Section 12: Breakout trading + ML (fake vs real breakout detection, 3-layer filter system)

### Key Learnings & Decisions
- User prefers **breakout trading** (돌파매매) but suffers losses in ranging markets (횡보장)
- Main interest: Using ML to **distinguish real vs fake breakouts**
- **Indicator velocity/acceleration** (1st/2nd derivatives of RSI, MACD, etc.) can serve as leading signals despite indicators being lagging
- Recommended approach: **XGBoost (fast filter) + CNN (chart pattern) + LSTM (tick analysis)** 3-layer system
- All ML tools are free (scikit-learn, XGBoost, TensorFlow)
- OpenAI/Claude API only for news sentiment analysis (supplementary)
- Feature engineering must use **ratios/percentages, NOT absolute prices** to prevent overfitting
- Walk-forward validation preferred over fixed train/test split

### User's Knowledge Level
- Understands: RSI (direction), MACD (direction), ADX (trend strength), candlestick patterns
- Learning: ROC (rate of change = speed), ML/DL concepts, Python for trading
- Has: TickStory tick data available
- Uses: MT4 for trading, interested in MT4+Python integration

### Next Steps (Potential)
- [ ] Build actual Python ML code for breakout detection
- [ ] Create XGBoost model with momentum acceleration features
- [ ] Implement CNN chart pattern recognition
- [ ] Connect Python ML signals to MT4 EA
- [ ] Backtest on XAUUSD historical data
- [ ] Explore tick data with LSTM for precise entry timing

### Coding Preferences
- HTML reports: Dark theme, CSS-only visuals (no external images), Korean language
- Commit style: `feat:` prefix, Korean+English descriptions
- Uses Remotion for video content
- MQL4 for MT4 EAs
