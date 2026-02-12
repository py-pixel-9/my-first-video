//+------------------------------------------------------------------+
//|                                           VWAP_Breakout_EA.mq4   |
//|    ML v2.1 전략 → 룰 기반 변환 (VWAP + 돌파매매)                  |
//|    피처 중요도: 세션 > 1H추세 > VWAP위치 > 거래량 > RSI > ADX     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, py-pixel-9"
#property link      "https://github.com/py-pixel-9"
#property version   "1.00"
#property strict

//=== 시그널 ===
input int       BreakoutPeriod     = 20;       // 돌파 기준 봉 수
input double    MinADX             = 20.0;     // 최소 ADX (추세 필터)
input int       ADX_Period         = 14;       // ADX 기간
input int       RSI_Period         = 14;       // RSI 기간
input double    RSI_Overbought     = 75.0;     // RSI 과매수 (Buy 제한)
input double    RSI_Oversold       = 25.0;     // RSI 과매도 (Sell 제한)
input double    MaxVWAP_DistPct    = 0.5;      // VWAP 대비 최대 거리 (%)
input bool      UseHigherTF        = true;     // 1H 추세 필터 사용
input int       EMA_Period_H1      = 20;       // 1H EMA 기간
input bool      UseVolumeFilter    = true;     // 거래량 필터 사용
input bool      UseSessionFilter   = false;    // 세션 필터 사용
input bool      UseGoldenFilter    = true;     // 골든타임 추가 필터 (ADX 강화)
input double    GoldenMinADX       = 25.0;     // 골든타임 최소 ADX

//=== 주문 ===
input double    LotSize            = 0.01;     // 랏 사이즈
input int       StopLossPoints     = 300;      // 손절 (포인트)
input int       TakeProfitPoints   = 500;      // 익절 (포인트)
input int       MagicNumber        = 20260212; // 매직넘버
input int       MaxPositions       = 1;        // 최대 동시 포지션
input int       CooldownBars       = 5;        // 재진입 대기 봉 수

//=== 트레일링 ===
input bool      UseTrailing        = true;     // 트레일링 사용
input int       TrailStartPts      = 50;       // 트레일 시작 (포인트)
input int       TrailStepPts       = 50;       // 트레일 간격 (포인트)

//=== 필터 ===
input double    MaxSpreadPips      = 15.0;     // 최대 스프레드 (pips)
input int       MaxSlippage        = 5;        // 최대 슬리피지

//=== 세션 (브로커 서버 시간 기준) ===
input int       ServerUTC_Offset   = 2;        // 서버 시간 - UTC 오프셋 (기본 GMT+2)
input int       LondonStartUTC     = 7;        // 런던 시작 (UTC)
input int       LondonEndUTC       = 16;       // 런던 종료 (UTC)
input int       NYStartUTC         = 13;       // 뉴욕 시작 (UTC)
input int       NYEndUTC           = 22;       // 뉴욕 종료 (UTC)

//=== 표시 ===
input bool      ShowPanel          = true;     // 패널 표시
input bool      ShowVWAP_Line      = true;     // VWAP 라인 표시
input color     VWAPColor          = clrGold;  // VWAP 라인 색상
input color     BuyColor           = clrAqua;  // Buy 색상
input color     SellColor          = clrOrangeRed; // Sell 색상
input int       FontSize           = 9;        // 폰트 크기

//+------------------------------------------------------------------+
//| 전역 변수
//+------------------------------------------------------------------+
double   g_pip;
datetime g_lastBar       = 0;
int      g_lastTradeBar  = -999;    // 마지막 거래 봉 인덱스
int      g_barCount      = 0;       // 총 봉 수 카운트

// VWAP 데이터
double   g_vwap          = 0;
double   g_vwapUpper1    = 0;
double   g_vwapLower1    = 0;
double   g_cumTPV        = 0;       // 누적 TP*Volume
double   g_cumVol        = 0;       // 누적 Volume
int      g_vwapDay       = -1;      // VWAP 리셋용 날짜
double   g_vwapDiffSq[];            // VWAP 편차 제곱 (밴드 계산용)
int      g_vwapDiffIdx   = 0;
int      g_vwapDiffSize  = 20;      // 밴드 계산 윈도우

// 통계
int      g_totalBreakouts = 0;
int      g_buySignals     = 0;
int      g_sellSignals    = 0;
int      g_filtered       = 0;
string   g_lastFilterReason = "";
string   g_lastSignal     = "대기 중";

//+------------------------------------------------------------------+
int OnInit()
{
   g_pip = Point;
   if(Digits == 3 || Digits == 5) g_pip = Point * 10;

   if(LotSize <= 0 || StopLossPoints <= 0 || TakeProfitPoints <= 0)
   {
      Alert("VWAP EA: 파라미터 오류!");
      return(INIT_PARAMETERS_INCORRECT);
   }

   // VWAP 편차 배열 초기화
   ArrayResize(g_vwapDiffSq, g_vwapDiffSize);
   ArrayInitialize(g_vwapDiffSq, 0);
   g_vwapDiffIdx = 0;

   Print("=== VWAP Breakout EA v1.0 (ML v2.1 룰 변환) ===");
   Print("돌파기준=", BreakoutPeriod, "봉, ADX>", MinADX,
         ", RSI(", RSI_Oversold, "-", RSI_Overbought, ")");
   Print("1H추세=", UseHigherTF ? "ON" : "OFF",
         ", 거래량=", UseVolumeFilter ? "ON" : "OFF",
         ", 세션=", UseSessionFilter ? "ON" : "OFF");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   CleanupObjects();
}

//+------------------------------------------------------------------+
void OnTick()
{
   bool newBar = (g_lastBar != Time[0]);

   if(newBar)
   {
      g_lastBar = Time[0];
      g_barCount++;

      // 1. VWAP 계산
      CalculateVWAP();

      // 2. 돌파 체크 + 진입
      CheckAndTrade();
   }

   // 매 틱
   if(UseTrailing) DoTrailing();
   if(ShowPanel)   DrawPanel();
   if(ShowVWAP_Line) DrawVWAPLine();
}

//+------------------------------------------------------------------+
//| VWAP 계산 (일별 리셋)
//+------------------------------------------------------------------+
void CalculateVWAP()
{
   int today = TimeDay(Time[0]) + TimeMonth(Time[0]) * 100 + TimeYear(Time[0]) * 10000;

   // 새 날짜 → 리셋
   if(today != g_vwapDay)
   {
      g_vwapDay = today;
      g_cumTPV  = 0;
      g_cumVol  = 0;
      ArrayInitialize(g_vwapDiffSq, 0);
      g_vwapDiffIdx = 0;
   }

   // 현재 봉의 TP (Typical Price)
   double tp = (High[1] + Low[1] + Close[1]) / 3.0;  // 완성된 봉 사용
   double vol = (double)Volume[1];

   if(vol <= 0) return;

   g_cumTPV += tp * vol;
   g_cumVol += vol;

   if(g_cumVol > 0)
      g_vwap = g_cumTPV / g_cumVol;

   // 밴드 계산 (이동 표준편차)
   double diff = Close[1] - g_vwap;
   g_vwapDiffSq[g_vwapDiffIdx % g_vwapDiffSize] = diff * diff;
   g_vwapDiffIdx++;

   int count = MathMin(g_vwapDiffIdx, g_vwapDiffSize);
   if(count > 2)
   {
      double sumSq = 0;
      for(int i = 0; i < count; i++)
         sumSq += g_vwapDiffSq[i];
      double stdDev = MathSqrt(sumSq / count);
      g_vwapUpper1 = g_vwap + stdDev;
      g_vwapLower1 = g_vwap - stdDev;
   }
}

//+------------------------------------------------------------------+
//| 돌파 체크 + 조건 필터 + 진입
//+------------------------------------------------------------------+
void CheckAndTrade()
{
   if(!IsTradeAllowed() || IsTradeContextBusy()) return;

   // 스프레드 체크
   double spread = MarketInfo(Symbol(), MODE_SPREAD) * Point / g_pip;
   if(spread > MaxSpreadPips) return;

   // 최대 포지션 체크
   if(CountPositions() >= MaxPositions) return;

   // 쿨다운 체크
   if(g_barCount - g_lastTradeBar < CooldownBars) return;

   // VWAP가 아직 계산 안됨
   if(g_vwap <= 0) return;

   // 최소 봉 수 확인
   if(Bars < BreakoutPeriod + 5) return;

   // ──────────────────────────────────────
   // 돌파 감지
   // ──────────────────────────────────────
   int breakoutDir = CheckBreakout();  // 1=상방, -1=하방, 0=없음
   if(breakoutDir == 0) return;

   g_totalBreakouts++;

   // ──────────────────────────────────────
   // 필터 체인 (ML 피처 중요도 순서)
   // ──────────────────────────────────────

   // 필터 1: VWAP 위치 (피처 중요도 높음)
   if(breakoutDir == 1 && Close[1] < g_vwap)
   {
      g_filtered++;
      g_lastFilterReason = "VWAP 아래 (Buy 불가)";
      return;
   }
   if(breakoutDir == -1 && Close[1] > g_vwap)
   {
      g_filtered++;
      g_lastFilterReason = "VWAP 위 (Sell 불가)";
      return;
   }

   // 필터 2: VWAP 대비 거리 (너무 멀면 과매수/과매도)
   if(g_vwap > 0)
   {
      double vwapDistPct = MathAbs(Close[1] - g_vwap) / g_vwap * 100.0;
      if(vwapDistPct > MaxVWAP_DistPct)
      {
         g_filtered++;
         g_lastFilterReason = "VWAP 거리 초과 (" + DoubleToStr(vwapDistPct, 2) + "%)";
         return;
      }
   }

   // 필터 3: 거래량 (Volume > 20봉 평균)
   if(UseVolumeFilter)
   {
      double avgVol = 0;
      for(int v = 1; v <= 20; v++)
         avgVol += (double)Volume[v];
      avgVol /= 20.0;

      if((double)Volume[1] < avgVol)
      {
         g_filtered++;
         g_lastFilterReason = "거래량 부족";
         return;
      }
   }

   // 필터 4: ADX (추세 강도)
   double adxVal = iADX(Symbol(), 0, ADX_Period, PRICE_CLOSE, MODE_MAIN, 1);
   double adxThreshold = MinADX;

   // 골든타임이면 ADX 기준 강화
   if(UseGoldenFilter && GetSessionType() == 2)
      adxThreshold = GoldenMinADX;

   if(adxVal < adxThreshold)
   {
      g_filtered++;
      g_lastFilterReason = "ADX 약함 (" + DoubleToStr(adxVal, 1) + "<" + DoubleToStr(adxThreshold, 1) + ")";
      return;
   }

   // 필터 5: RSI (과매수/과매도)
   double rsiVal = iRSI(Symbol(), 0, RSI_Period, PRICE_CLOSE, 1);
   if(breakoutDir == 1 && rsiVal > RSI_Overbought)
   {
      g_filtered++;
      g_lastFilterReason = "RSI 과매수 (" + DoubleToStr(rsiVal, 1) + ")";
      return;
   }
   if(breakoutDir == -1 && rsiVal < RSI_Oversold)
   {
      g_filtered++;
      g_lastFilterReason = "RSI 과매도 (" + DoubleToStr(rsiVal, 1) + ")";
      return;
   }

   // 필터 6: 1H 추세 일치
   if(UseHigherTF)
   {
      int trendDir = CheckHigherTF();  // 1=상승, -1=하락, 0=불명
      if(breakoutDir == 1 && trendDir == -1)
      {
         g_filtered++;
         g_lastFilterReason = "1H 하락추세 (Buy 역추세)";
         return;
      }
      if(breakoutDir == -1 && trendDir == 1)
      {
         g_filtered++;
         g_lastFilterReason = "1H 상승추세 (Sell 역추세)";
         return;
      }
   }

   // 필터 7: 세션 필터 (선택)
   if(UseSessionFilter)
   {
      int session = GetSessionType();
      if(session == 0)  // 아시아 세션
      {
         g_filtered++;
         g_lastFilterReason = "아시아 세션 (거래 제한)";
         return;
      }
   }

   // ──────────────────────────────────────
   // 모든 필터 통과 → 진입!
   // ──────────────────────────────────────
   ExecuteTrade(breakoutDir, adxVal, rsiVal);
}

//+------------------------------------------------------------------+
//| 20봉 고/저점 돌파 감지
//| return: 1=상방돌파, -1=하방돌파, 0=없음
//+------------------------------------------------------------------+
int CheckBreakout()
{
   // 20봉 최고/최저 (현재 봉 제외, 1~20)
   double highestHigh = High[1];
   double lowestLow   = Low[1];

   for(int i = 2; i <= BreakoutPeriod; i++)
   {
      if(High[i] > highestHigh) highestHigh = High[i];
      if(Low[i]  < lowestLow)  lowestLow   = Low[i];
   }

   // 상방 돌파: 현재 완성봉 Close가 이전 20봉 최고점보다 높음
   // 단, shift(1)의 Close가 직전 20봉(shift 2~21)의 최고점을 넘어야 함
   double prevHighest = 0;
   for(int i = 2; i <= BreakoutPeriod + 1; i++)
   {
      if(High[i] > prevHighest) prevHighest = High[i];
   }

   double prevLowest = 999999;
   for(int i = 2; i <= BreakoutPeriod + 1; i++)
   {
      if(Low[i] < prevLowest) prevLowest = Low[i];
   }

   // 상방 돌파
   if(Close[1] > prevHighest)
      return 1;

   // 하방 돌파
   if(Close[1] < prevLowest)
      return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| 1H EMA20 추세 확인
//| return: 1=상승추세, -1=하락추세, 0=불명
//+------------------------------------------------------------------+
int CheckHigherTF()
{
   double ema = iMA(Symbol(), PERIOD_H1, EMA_Period_H1, 0, MODE_EMA, PRICE_CLOSE, 1);
   double closeH1 = iClose(Symbol(), PERIOD_H1, 1);

   if(closeH1 > ema) return 1;   // 상승추세
   if(closeH1 < ema) return -1;  // 하락추세
   return 0;
}

//+------------------------------------------------------------------+
//| 세션 판별 (UTC 기준)
//| return: 0=아시아, 1=런던 or 뉴욕 단독, 2=골든타임(런+뉴 겹침)
//+------------------------------------------------------------------+
int GetSessionType()
{
   int serverHour = TimeHour(TimeCurrent());
   int utcHour = serverHour - ServerUTC_Offset;
   if(utcHour < 0)  utcHour += 24;
   if(utcHour >= 24) utcHour -= 24;

   bool isLondon = (utcHour >= LondonStartUTC && utcHour < LondonEndUTC);
   bool isNY     = (utcHour >= NYStartUTC && utcHour < NYEndUTC);

   if(isLondon && isNY) return 2;  // 골든타임
   if(isLondon || isNY) return 1;  // 런던 or 뉴욕 단독
   return 0;                        // 아시아
}

//+------------------------------------------------------------------+
//| 거래 실행
//+------------------------------------------------------------------+
void ExecuteTrade(int direction, double adxVal, double rsiVal)
{
   double sl, tp;
   int ticket;
   string session = "";
   int sType = GetSessionType();
   if(sType == 0)      session = "아시아";
   else if(sType == 1) session = "런던/뉴욕";
   else                session = "골든타임";

   string trend1h = "";
   if(UseHigherTF)
   {
      int t = CheckHigherTF();
      trend1h = (t == 1) ? "↑" : (t == -1) ? "↓" : "→";
   }

   if(direction == 1)
   {
      // BUY
      sl = NormalizeDouble(Ask - StopLossPoints * Point, Digits);
      tp = NormalizeDouble(Ask + TakeProfitPoints * Point, Digits);

      ticket = OrderSend(Symbol(), OP_BUY, LotSize, Ask, MaxSlippage,
                          sl, tp, "VWAP_BK", MagicNumber, 0, BuyColor);

      if(ticket > 0)
      {
         g_buySignals++;
         g_lastTradeBar = g_barCount;
         g_lastSignal = "🟢 BUY #" + IntegerToString(ticket);

         Print(">>> BUY #", ticket,
               " @ ", DoubleToStr(Ask, Digits),
               " VWAP=", DoubleToStr(g_vwap, Digits),
               " ADX=", DoubleToStr(adxVal, 1),
               " RSI=", DoubleToStr(rsiVal, 1),
               " [", session, "] 1H", trend1h);
      }
      else
      {
         Print("BUY 실패: Error=", GetLastError());
      }
   }
   else if(direction == -1)
   {
      // SELL
      sl = NormalizeDouble(Bid + StopLossPoints * Point, Digits);
      tp = NormalizeDouble(Bid - TakeProfitPoints * Point, Digits);

      ticket = OrderSend(Symbol(), OP_SELL, LotSize, Bid, MaxSlippage,
                          sl, tp, "VWAP_BK", MagicNumber, 0, SellColor);

      if(ticket > 0)
      {
         g_sellSignals++;
         g_lastTradeBar = g_barCount;
         g_lastSignal = "🔴 SELL #" + IntegerToString(ticket);

         Print(">>> SELL #", ticket,
               " @ ", DoubleToStr(Bid, Digits),
               " VWAP=", DoubleToStr(g_vwap, Digits),
               " ADX=", DoubleToStr(adxVal, 1),
               " RSI=", DoubleToStr(rsiVal, 1),
               " [", session, "] 1H", trend1h);
      }
      else
      {
         Print("SELL 실패: Error=", GetLastError());
      }
   }
}

//+------------------------------------------------------------------+
//| 현재 포지션 수 카운트
//+------------------------------------------------------------------+
int CountPositions()
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderMagicNumber() != MagicNumber) continue;
      if(OrderType() == OP_BUY || OrderType() == OP_SELL)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| 트레일링 스탑
//+------------------------------------------------------------------+
void DoTrailing()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;

      double sl = OrderStopLoss();
      double newSL;

      if(OrderType() == OP_BUY)
      {
         if(Bid - OrderOpenPrice() < TrailStartPts * Point) continue;
         newSL = NormalizeDouble(Bid - TrailStepPts * Point, Digits);
         if(newSL > sl + Point)
            OrderModify(OrderTicket(), OrderOpenPrice(), newSL, OrderTakeProfit(), 0, BuyColor);
      }
      else
      {
         if(OrderOpenPrice() - Ask < TrailStartPts * Point) continue;
         newSL = NormalizeDouble(Ask + TrailStepPts * Point, Digits);
         if(sl == 0 || newSL < sl - Point)
            OrderModify(OrderTicket(), OrderOpenPrice(), newSL, OrderTakeProfit(), 0, SellColor);
      }
   }
}

//+------------------------------------------------------------------+
//| VWAP 라인 표시
//+------------------------------------------------------------------+
void DrawVWAPLine()
{
   if(g_vwap <= 0) return;

   // VWAP 메인
   if(ObjectFind("VWAP_Main") < 0)
      ObjectCreate("VWAP_Main", OBJ_HLINE, 0, 0, g_vwap);
   else
      ObjectSet("VWAP_Main", OBJPROP_PRICE1, g_vwap);
   ObjectSet("VWAP_Main", OBJPROP_COLOR, VWAPColor);
   ObjectSet("VWAP_Main", OBJPROP_STYLE, STYLE_SOLID);
   ObjectSet("VWAP_Main", OBJPROP_WIDTH, 2);
   ObjectSet("VWAP_Main", OBJPROP_BACK, true);

   // VWAP Upper Band
   if(g_vwapUpper1 > 0)
   {
      if(ObjectFind("VWAP_Upper") < 0)
         ObjectCreate("VWAP_Upper", OBJ_HLINE, 0, 0, g_vwapUpper1);
      else
         ObjectSet("VWAP_Upper", OBJPROP_PRICE1, g_vwapUpper1);
      ObjectSet("VWAP_Upper", OBJPROP_COLOR, VWAPColor);
      ObjectSet("VWAP_Upper", OBJPROP_STYLE, STYLE_DOT);
      ObjectSet("VWAP_Upper", OBJPROP_WIDTH, 1);
      ObjectSet("VWAP_Upper", OBJPROP_BACK, true);
   }

   // VWAP Lower Band
   if(g_vwapLower1 > 0)
   {
      if(ObjectFind("VWAP_Lower") < 0)
         ObjectCreate("VWAP_Lower", OBJ_HLINE, 0, 0, g_vwapLower1);
      else
         ObjectSet("VWAP_Lower", OBJPROP_PRICE1, g_vwapLower1);
      ObjectSet("VWAP_Lower", OBJPROP_COLOR, VWAPColor);
      ObjectSet("VWAP_Lower", OBJPROP_STYLE, STYLE_DOT);
      ObjectSet("VWAP_Lower", OBJPROP_WIDTH, 1);
      ObjectSet("VWAP_Lower", OBJPROP_BACK, true);
   }
}

//+------------------------------------------------------------------+
//| 정보 패널
//+------------------------------------------------------------------+
void DrawPanel()
{
   double sp = MarketInfo(Symbol(), MODE_SPREAD) * Point / g_pip;
   double adx = iADX(Symbol(), 0, ADX_Period, PRICE_CLOSE, MODE_MAIN, 1);
   double rsi = iRSI(Symbol(), 0, RSI_Period, PRICE_CLOSE, 1);
   int session = GetSessionType();
   string sessionStr = (session == 0) ? "아시아" : (session == 1) ? "런던/뉴욕" : "골든타임";

   // 1H 추세
   string trendStr = "OFF";
   if(UseHigherTF)
   {
      int t = CheckHigherTF();
      trendStr = (t == 1) ? "↑상승" : (t == -1) ? "↓하락" : "→횡보";
   }

   // P/L 계산
   double pl = 0;
   int posCount = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      if(OrderType() == OP_BUY || OrderType() == OP_SELL)
      {
         pl += OrderProfit() + OrderSwap() + OrderCommission();
         posCount++;
      }
   }

   // 당일 히스토리 P/L
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      if(OrderCloseTime() >= iTime(Symbol(), PERIOD_D1, 0))
         pl += OrderProfit() + OrderSwap() + OrderCommission();
   }

   // VWAP 대비 거리
   string vwapStr = "계산중";
   if(g_vwap > 0)
   {
      double dist = (Close[0] - g_vwap) / g_vwap * 100.0;
      vwapStr = DoubleToStr(g_vwap, Digits) + " (" + (dist >= 0 ? "+" : "") + DoubleToStr(dist, 2) + "%)";
   }

   MakeLabel("VBK_1", 10, 20,
      "VWAP BK v1 | " + Symbol() + " M" + IntegerToString(Period()), clrYellow);
   MakeLabel("VBK_2", 10, 38,
      "VWAP: " + vwapStr, VWAPColor);
   MakeLabel("VBK_3", 10, 56,
      "ADX=" + DoubleToStr(adx, 1) +
      "  RSI=" + DoubleToStr(rsi, 1) +
      "  1H:" + trendStr +
      "  [" + sessionStr + "]", clrWhite);
   MakeLabel("VBK_4", 10, 74,
      "포지션=" + IntegerToString(posCount) +
      "  P/L=" + DoubleToStr(pl, 2) +
      "  Sp=" + DoubleToStr(sp, 1) + "pip",
      pl >= 0 ? clrLime : clrRed);
   MakeLabel("VBK_5", 10, 92,
      "돌파=" + IntegerToString(g_totalBreakouts) +
      "  Buy=" + IntegerToString(g_buySignals) +
      "  Sell=" + IntegerToString(g_sellSignals) +
      "  필터=" + IntegerToString(g_filtered), clrGray);
   MakeLabel("VBK_6", 10, 110,
      "시그널: " + g_lastSignal, clrAqua);
   MakeLabel("VBK_7", 10, 128,
      "필터: " + g_lastFilterReason, clrDimGray);
}

//+------------------------------------------------------------------+
void MakeLabel(string name, int x, int y, string text, color clr)
{
   if(ObjectFind(name) < 0)
      ObjectCreate(name, OBJ_LABEL, 0, 0, 0);
   ObjectSet(name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSet(name, OBJPROP_XDISTANCE, x);
   ObjectSet(name, OBJPROP_YDISTANCE, y);
   ObjectSetText(name, text, FontSize, "Arial Bold", clr);
}

//+------------------------------------------------------------------+
void CleanupObjects()
{
   for(int i = ObjectsTotal() - 1; i >= 0; i--)
   {
      string nm = ObjectName(i);
      if(StringFind(nm, "VBK_") >= 0 || StringFind(nm, "VWAP_") >= 0)
         ObjectDelete(nm);
   }
}
//+------------------------------------------------------------------+
