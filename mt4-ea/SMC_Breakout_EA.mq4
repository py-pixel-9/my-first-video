//+------------------------------------------------------------------+
//|                                              SMC_Breakout_EA.mq4 |
//|         SMC Breakout v5.0 - 주요 레벨만 + 재진입 방지            |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property link      ""
#property version   "5.00"
#property strict

//=== 시그널 ===
input int       SwingSize           = 5;        // 스윙 크기 (좌우 캔들)
input int       MaxLevelsPerSide    = 3;        // 방향별 최대 주문 수
input int       CandlesBeforeExpiry = 100;      // 레벨 만료 캔들 수
input double    MinLevelDistPips    = 30.0;     // 최소 레벨 간격 (pips)
input double    MaxLevelDistPips    = 300.0;    // 최대 레벨 거리 (pips)
input int       ScanBars            = 100;      // 스캔 범위
input int       MinTouchCount       = 2;        // 최소 터치 횟수 (레벨 강도)
input double    TouchZonePips       = 5.0;      // 터치 판정 범위 (pips)

//=== 주문 ===
input double    LotSize             = 0.01;
input int       StopLossPoints      = 300;
input int       TakeProfitPoints    = 500;
input int       MagicNumber         = 20260208;

//=== 트레일링 ===
input bool      UseTrailing         = true;
input int       TrailStartPts       = 50;
input int       TrailStepPts        = 50;

//=== 필터 ===
input double    MaxSpreadPips       = 15.0;
input int       MaxSlippage         = 5;        // Max slippage (points)
input bool      UseTradingHours     = false;
input int       StartHour           = 8;
input int       EndHour             = 22;

//=== 재진입 방지 ===
input double    UsedZonePips        = 20.0;     // 사용된 레벨 근처 재진입 금지 범위
input int       MaxUsedHistory      = 50;       // 기록 보관 개수
input double    BreachCancelPips    = 3.0;      // 돌파 후 펜딩 취소 거리 (pips)

//=== 표시 ===
input bool      ShowPanel           = true;
input bool      ShowLines           = true;
input color     BuyColor            = clrAqua;
input color     SellColor           = clrOrangeRed;
input int       FontSize            = 9;

//+------------------------------------------------------------------+
struct EALevel {
   double   price;
   int      barAge;
   bool     isBullish;
   bool     active;
   int      ticket;
   int      touchCount;
};

//+------------------------------------------------------------------+
double     g_pip;
datetime   g_lastBar = 0;
EALevel    g_levels[];

// 사용된 레벨 기록 (재진입 방지)
double     g_usedPrices[];
bool       g_usedDirection[];
int        g_usedCount = 0;

// 통계
int        g_statSwH=0, g_statSwL=0, g_statCreated=0;
int        g_statOrders=0, g_statFilled=0, g_statFiltered=0;

//+------------------------------------------------------------------+
int OnInit()
{
   g_pip = Point;
   if(Digits == 3 || Digits == 5) g_pip = Point * 10;

   if(LotSize <= 0 || StopLossPoints <= 0 || TakeProfitPoints <= 0)
   {
      Alert("파라미터 오류!");
      return(INIT_PARAMETERS_INCORRECT);
   }

   ArrayResize(g_levels, 0);
   ArrayResize(g_usedPrices, 0);
   ArrayResize(g_usedDirection, 0);
   g_usedCount = 0;

   ScanExistingOrders();

   Print("=== SMC Breakout EA v5.0 ===");
   Print("MinTouch=", MinTouchCount, " TouchZone=", TouchZonePips, "pip");
   Print("UsedZone=", UsedZonePips, "pip (재진입 금지)");

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { CleanupObjects(); }

//+------------------------------------------------------------------+
void OnTick()
{
   bool newBar = (g_lastBar != Time[0]);
   if(newBar)
   {
      g_lastBar = Time[0];
      CleanupInactive();
      ScanLevels();
      AgeLevels();
      SyncOrders();
   }

   CheckBreachCancel();   // 틱마다 돌파 취소 체크 (봉 사이에도!)
   if(UseTrailing) DoTrailing();
   CheckFills();
   if(ShowPanel) DrawPanel();
   if(ShowLines) DrawLines();
}

//+------------------------------------------------------------------+
//| 틱 단위 돌파 취소 - Sell Stop이 돌파 후 되돌림에서 체결되는 것 방지 |
//+------------------------------------------------------------------+
void CheckBreachCancel()
{
   double breachDist = BreachCancelPips * g_pip;

   for(int i = ArraySize(g_levels) - 1; i >= 0; i--)
   {
      if(!g_levels[i].active) continue;
      if(g_levels[i].ticket <= 0) continue;  // 주문 없으면 AgeLevels에서 처리

      // 펜딩 주문이 아직 체결 안 됐는지 확인
      if(!OrderSelect(g_levels[i].ticket, SELECT_BY_TICKET)) continue;
      if(OrderType() == OP_BUY || OrderType() == OP_SELL) continue;  // 이미 체결됨
      if(OrderCloseTime() > 0) continue;  // 이미 삭제됨

      // Buy Stop인데 가격이 이미 위로 돌파해서 지나감
      if(g_levels[i].isBullish && Bid > g_levels[i].price + breachDist)
      {
         Print("▲ [틱] BuyStop 돌파 취소: ", DoubleToStr(g_levels[i].price, Digits));
         MarkPriceUsed(g_levels[i].price, true);
         KillLevel(i);
      }
      // Sell Stop인데 가격이 이미 아래로 돌파해서 지나감
      else if(!g_levels[i].isBullish && Ask < g_levels[i].price - breachDist)
      {
         Print("▼ [틱] SellStop 돌파 취소: ", DoubleToStr(g_levels[i].price, Digits));
         MarkPriceUsed(g_levels[i].price, false);
         KillLevel(i);
      }
   }
}

//+------------------------------------------------------------------+
void CleanupInactive()
{
   int w = 0;
   for(int i = 0; i < ArraySize(g_levels); i++)
   {
      if(g_levels[i].active)
      {
         if(w != i) g_levels[w] = g_levels[i];
         w++;
      }
   }
   if(w < ArraySize(g_levels)) ArrayResize(g_levels, w);
}

//+------------------------------------------------------------------+
bool IsSwingHigh(int bar)
{
   if(bar - SwingSize < 0 || bar + SwingSize >= Bars) return false;
   for(int j = 1; j <= SwingSize; j++)
   {
      if(High[bar] <= High[bar+j] || High[bar] <= High[bar-j])
         return false;
   }
   return true;
}

bool IsSwingLow(int bar)
{
   if(bar - SwingSize < 0 || bar + SwingSize >= Bars) return false;
   for(int j = 1; j <= SwingSize; j++)
   {
      if(Low[bar] >= Low[bar+j] || Low[bar] >= Low[bar-j])
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
int CountTouches(double price, bool isResistance, int fromBar, int toBar)
{
   int touches = 0;
   double zone = TouchZonePips * g_pip;

   for(int i = fromBar; i < toBar && i < Bars; i++)
   {
      if(isResistance)
      {
         if(MathAbs(High[i] - price) < zone && Close[i] < price)
            touches++;
      }
      else
      {
         if(MathAbs(Low[i] - price) < zone && Close[i] > price)
            touches++;
      }
   }
   return touches;
}

//+------------------------------------------------------------------+
bool IsPriceUsed(double price, bool isBull)
{
   double zone = UsedZonePips * g_pip;

   for(int i = 0; i < g_usedCount; i++)
   {
      if(g_usedDirection[i] == isBull &&
         MathAbs(g_usedPrices[i] - price) < zone)
         return true;
   }
   return false;
}

void MarkPriceUsed(double price, bool isBull)
{
   if(g_usedCount >= MaxUsedHistory)
   {
      for(int i = 0; i < g_usedCount - 1; i++)
      {
         g_usedPrices[i] = g_usedPrices[i+1];
         g_usedDirection[i] = g_usedDirection[i+1];
      }
      g_usedCount--;
   }

   ArrayResize(g_usedPrices, g_usedCount + 1);
   ArrayResize(g_usedDirection, g_usedCount + 1);
   g_usedPrices[g_usedCount] = price;
   g_usedDirection[g_usedCount] = isBull;
   g_usedCount++;

   Print("가격 기록: ", DoubleToStr(price, Digits), isBull ? " (Buy)" : " (Sell)",
         " 총 ", g_usedCount, "개");
}

//+------------------------------------------------------------------+
void ScanLevels()
{
   g_statSwH = 0;
   g_statSwL = 0;
   g_statFiltered = 0;

   double maxDist = MaxLevelDistPips * g_pip;
   int scanEnd = MathMin(ScanBars, Bars - SwingSize - 1);

   for(int i = SwingSize + 1; i < scanEnd; i++)
   {
      //--- 저항 (스윙 하이) -> Buy Stop ---
      if(IsSwingHigh(i))
      {
         g_statSwH++;
         double resistance = High[i];
         double dist = resistance - Ask;

         if(dist > 0 && dist < maxDist)
         {
            int touches = CountTouches(resistance, true, i+1, i + ScanBars);

            if(touches < MinTouchCount)
            {
               g_statFiltered++;
               continue;
            }

            if(IsPriceUsed(resistance, true))
               continue;

            if(!LevelExists(resistance, true) && CountActive(true) < MaxLevelsPerSide)
            {
               AddLevel(resistance, true, touches);
            }
         }
      }

      //--- 지지 (스윙 로우) -> Sell Stop ---
      if(IsSwingLow(i))
      {
         g_statSwL++;
         double support = Low[i];
         double dist = Bid - support;

         if(dist > 0 && dist < maxDist)
         {
            int touches = CountTouches(support, false, i+1, i + ScanBars);

            if(touches < MinTouchCount)
            {
               g_statFiltered++;
               continue;
            }

            if(IsPriceUsed(support, false))
               continue;

            if(!LevelExists(support, false) && CountActive(false) < MaxLevelsPerSide)
            {
               AddLevel(support, false, touches);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
bool LevelExists(double price, bool isBull)
{
   double minD = MinLevelDistPips * g_pip;

   for(int i = 0; i < ArraySize(g_levels); i++)
   {
      if(g_levels[i].active && g_levels[i].isBullish == isBull &&
         MathAbs(g_levels[i].price - price) < minD)
         return true;
   }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      if(OrderType() != OP_BUYSTOP && OrderType() != OP_SELLSTOP) continue;
      if(MathAbs(OrderOpenPrice() - price) < minD) return true;
   }

   return false;
}

int CountActive(bool isBull)
{
   int c = 0;
   for(int i = 0; i < ArraySize(g_levels); i++)
      if(g_levels[i].active && g_levels[i].isBullish == isBull) c++;
   return c;
}

//+------------------------------------------------------------------+
void AddLevel(double price, bool isBull, int touches)
{
   int sz = ArraySize(g_levels);
   ArrayResize(g_levels, sz + 1);
   g_levels[sz].price      = NormalizeDouble(price, Digits);
   g_levels[sz].barAge     = 0;
   g_levels[sz].isBullish  = isBull;
   g_levels[sz].active     = true;
   g_levels[sz].ticket     = -1;
   g_levels[sz].touchCount = touches;
   g_statCreated++;

   Print("+ ", isBull ? "저항 BuyStop" : "지지 SellStop", " ",
         DoubleToStr(price, Digits), " 터치=", touches, "회",
         " 거리=", DoubleToStr(MathAbs(Close[0] - price) / g_pip, 1), "pip");
}

//+------------------------------------------------------------------+
void AgeLevels()
{
   double maxDist = MaxLevelDistPips * g_pip;
   double breachDist = BreachCancelPips * g_pip;

   for(int i = ArraySize(g_levels) - 1; i >= 0; i--)
   {
      if(!g_levels[i].active) continue;
      g_levels[i].barAge++;

      // 만료
      if(g_levels[i].barAge > CandlesBeforeExpiry)
      { KillLevel(i); continue; }

      // ─── 핵심 수정: 가격이 레벨을 돌파하면 펜딩 유무 관계없이 즉시 취소 ───
      // Buy Stop: 가격이 레벨 위로 돌파 후 지나감 → 돌파 매매 기회 놓침 → 취소
      if(g_levels[i].isBullish && Bid > g_levels[i].price + breachDist)
      {
         Print("▲ BuyStop 레벨 돌파됨 → 취소: ", DoubleToStr(g_levels[i].price, Digits),
               " Bid=", DoubleToStr(Bid, Digits));
         MarkPriceUsed(g_levels[i].price, true);
         KillLevel(i); continue;
      }
      // Sell Stop: 가격이 레벨 아래로 돌파 후 지나감 → 돌파 매매 기회 놓침 → 취소
      // ★ ticket 조건 제거! 주문이 걸려있어도 돌파되면 취소해야 됨
      if(!g_levels[i].isBullish && Ask < g_levels[i].price - breachDist)
      {
         Print("▼ SellStop 레벨 돌파됨 → 취소: ", DoubleToStr(g_levels[i].price, Digits),
               " Ask=", DoubleToStr(Ask, Digits));
         MarkPriceUsed(g_levels[i].price, false);
         KillLevel(i); continue;
      }

      // 거리 초과
      if(g_levels[i].isBullish && g_levels[i].price - Ask > maxDist)
      { KillLevel(i); continue; }
      if(!g_levels[i].isBullish && Bid - g_levels[i].price > maxDist)
      { KillLevel(i); continue; }
   }
}

void KillLevel(int idx)
{
   if(idx < 0 || idx >= ArraySize(g_levels)) return;
   if(g_levels[idx].ticket > 0) DeletePending(g_levels[idx].ticket);
   g_levels[idx].active = false;
}

//+------------------------------------------------------------------+
void SyncOrders()
{
   if(!IsTradeAllowed() || IsTradeContextBusy()) return;

   double spread = MarketInfo(Symbol(), MODE_SPREAD) * Point / g_pip;
   if(spread > MaxSpreadPips) return;

   if(UseTradingHours)
   {
      int h = TimeHour(TimeCurrent());
      if(StartHour < EndHour)
      { if(h < StartHour || h >= EndHour) return; }
      else
      { if(h < StartHour && h >= EndHour) return; }
   }

   double stopLvl = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;

   for(int i = 0; i < ArraySize(g_levels); i++)
   {
      if(!g_levels[i].active || g_levels[i].ticket > 0) continue;

      double px = g_levels[i].price;
      double sl, tp;

      if(g_levels[i].isBullish)
      {
         if(px <= Ask) continue;
         if(px - Ask < stopLvl) continue;

         sl = NormalizeDouble(px - StopLossPoints * Point, Digits);
         tp = NormalizeDouble(px + TakeProfitPoints * Point, Digits);

         int tk = OrderSend(Symbol(), OP_BUYSTOP, LotSize, px, MaxSlippage, sl, tp,
                            "SMCEA", MagicNumber, 0, BuyColor);
         if(tk > 0)
         {
            g_levels[i].ticket = tk;
            g_statOrders++;
            Print(">>> BuyStop #", tk, " @ ", DoubleToStr(px, Digits),
                  " 터치=", g_levels[i].touchCount);
         }
      }
      else
      {
         if(px >= Bid) continue;
         if(Bid - px < stopLvl) continue;

         sl = NormalizeDouble(px + StopLossPoints * Point, Digits);
         tp = NormalizeDouble(px - TakeProfitPoints * Point, Digits);

         int tk = OrderSend(Symbol(), OP_SELLSTOP, LotSize, px, MaxSlippage, sl, tp,
                            "SMCEA", MagicNumber, 0, SellColor);
         if(tk > 0)
         {
            g_levels[i].ticket = tk;
            g_statOrders++;
            Print(">>> SellStop #", tk, " @ ", DoubleToStr(px, Digits),
                  " 터치=", g_levels[i].touchCount);
         }
      }
   }
}

//+------------------------------------------------------------------+
bool DeletePending(int ticket)
{
   if(ticket <= 0) return true;
   if(!OrderSelect(ticket, SELECT_BY_TICKET)) return true;
   if(OrderCloseTime() > 0) return true;
   if(OrderType() > OP_SELL)
   {
      if(OrderDelete(ticket)) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void CheckFills()
{
   for(int i = 0; i < ArraySize(g_levels); i++)
   {
      if(!g_levels[i].active || g_levels[i].ticket <= 0) continue;

      if(!OrderSelect(g_levels[i].ticket, SELECT_BY_TICKET))
      { g_levels[i].active = false; continue; }

      if(OrderType() == OP_BUY || OrderType() == OP_SELL)
      {
         Print("*** 체결! #", g_levels[i].ticket,
               g_levels[i].isBullish ? " BUY" : " SELL",
               " @ ", DoubleToStr(OrderOpenPrice(), Digits));

         MarkPriceUsed(g_levels[i].price, g_levels[i].isBullish);

         g_levels[i].active = false;
         g_statFilled++;
      }
      else if(OrderCloseTime() > 0)
         g_levels[i].active = false;
   }
}

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
void ScanExistingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      if(OrderType() > OP_SELL)
      {
         int sz = ArraySize(g_levels);
         ArrayResize(g_levels, sz + 1);
         g_levels[sz].price      = OrderOpenPrice();
         g_levels[sz].barAge     = 0;
         g_levels[sz].isBullish  = (OrderType() == OP_BUYSTOP);
         g_levels[sz].active     = true;
         g_levels[sz].ticket     = OrderTicket();
         g_levels[sz].touchCount = 0;
      }
   }
}

//+------------------------------------------------------------------+
void DrawPanel()
{
   int bP=0,sP=0,bT=0,sT=0;
   double pl=0;

   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      if(OrderType()==OP_BUYSTOP) bP++;
      else if(OrderType()==OP_SELLSTOP) sP++;
      else if(OrderType()==OP_BUY) { bT++; pl+=OrderProfit()+OrderSwap()+OrderCommission(); }
      else if(OrderType()==OP_SELL) { sT++; pl+=OrderProfit()+OrderSwap()+OrderCommission(); }
   }

   for(int i = OrdersHistoryTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      if(OrderCloseTime() >= iTime(Symbol(), PERIOD_D1, 0))
         pl += OrderProfit()+OrderSwap()+OrderCommission();
   }

   double sp = MarketInfo(Symbol(), MODE_SPREAD) * Point / g_pip;

   MakeLabel("SMCEA_1", 10, 20,
      "SMC v5 | " + Symbol() + " M" + IntegerToString(Period()), clrYellow);
   MakeLabel("SMCEA_2", 10, 38,
      "대기: BS=" + IntegerToString(bP) + " SS=" + IntegerToString(sP) +
      "  포지션: B=" + IntegerToString(bT) + " S=" + IntegerToString(sT), clrWhite);
   MakeLabel("SMCEA_3", 10, 56,
      "P/L: " + DoubleToStr(pl, 2) + "  Spread: " + DoubleToStr(sp, 1) + "pip",
      pl >= 0 ? clrLime : clrRed);
   MakeLabel("SMCEA_4", 10, 74,
      "저항=" + IntegerToString(CountActive(true)) +
      " 지지=" + IntegerToString(CountActive(false)) +
      "  SwH=" + IntegerToString(g_statSwH) +
      " SwL=" + IntegerToString(g_statSwL) +
      " 필터=" + IntegerToString(g_statFiltered), clrGray);
   MakeLabel("SMCEA_5", 10, 92,
      "생성=" + IntegerToString(g_statCreated) +
      " 주문=" + IntegerToString(g_statOrders) +
      " 체결=" + IntegerToString(g_statFilled) +
      " 사용가격=" + IntegerToString(g_usedCount), clrDimGray);
}

void DrawLines()
{
   for(int i = ObjectsTotal()-1; i >= 0; i--)
   {
      string nm = ObjectName(i);
      if(StringFind(nm, "SMCEA_L") == 0) ObjectDelete(nm);
   }

   for(int i = 0; i < ArraySize(g_levels); i++)
   {
      if(!g_levels[i].active) continue;

      string nm = "SMCEA_L" + IntegerToString(i);
      color clr = g_levels[i].isBullish ? BuyColor : SellColor;
      int sty = g_levels[i].ticket > 0 ? STYLE_SOLID : STYLE_DASH;

      ObjectCreate(nm, OBJ_HLINE, 0, 0, g_levels[i].price);
      ObjectSet(nm, OBJPROP_COLOR, clr);
      ObjectSet(nm, OBJPROP_STYLE, sty);
      ObjectSet(nm, OBJPROP_WIDTH, 1);
      ObjectSet(nm, OBJPROP_BACK, true);

      string lb = nm + "_T";
      string txt = (g_levels[i].isBullish ? "BS " : "SS ") +
                    DoubleToStr(g_levels[i].price, Digits) +
                    " [" + IntegerToString(g_levels[i].touchCount) + "T]" +
                    (g_levels[i].ticket > 0 ? " #" + IntegerToString(g_levels[i].ticket) : "");
      ObjectCreate(lb, OBJ_TEXT, 0, Time[10], g_levels[i].price);
      ObjectSetText(lb, txt, FontSize-1, "Arial", clr);
   }
}

void MakeLabel(string name, int x, int y, string text, color clr)
{
   if(ObjectFind(name) < 0) ObjectCreate(name, OBJ_LABEL, 0, 0, 0);
   ObjectSet(name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSet(name, OBJPROP_XDISTANCE, x);
   ObjectSet(name, OBJPROP_YDISTANCE, y);
   ObjectSetText(name, text, FontSize, "Arial Bold", clr);
}

void CleanupObjects()
{
   for(int i = ObjectsTotal()-1; i >= 0; i--)
   {
      string nm = ObjectName(i);
      if(StringFind(nm, "SMCEA_") >= 0) ObjectDelete(nm);
   }
}
//+------------------------------------------------------------------+
