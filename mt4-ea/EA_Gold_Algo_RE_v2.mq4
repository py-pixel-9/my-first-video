//+------------------------------------------------------------------+
//|                                           EA_Gold_Algo_RE_v2.mq4 |
//|         EA Gold Algo Reverse Engineering v2.0                     |
//|         + Auto Risk% Lot                                          |
//|         + Negative Gap → Market Entry                             |
//|         + Breakeven Option                                        |
//|         + Slippage Control                                        |
//+------------------------------------------------------------------+
#property copyright "Reverse Engineering Project 2026"
#property link      ""
#property version   "2.00"
#property strict

//=== Trade Settings ===
input string    NoteTradeSet       = "==================Trade Settings";
input int       MagicNumber        = 1;
input double    LotSize            = 0.01;      // Lot Size (used when AutoRisk=false)
input bool      UseAutoRisk        = true;      // use Automatic Risk
input double    RiskPercent        = 1.0;       // Risk % (Recommend 1%)
input int       MaxSpreadPts       = 60;        // Max Spread (in Points)
input int       MaxSlippage        = 40;        // Max slippage (points)

//=== Session Filter ===
input string    NoteSession        = "==================Session";
input bool      UseSessionFilter   = true;      // Use Session Filters (UTC-based universal)
input bool      TradeAsian         = false;     // Trade Asian Session (UTC)
input int       AsiaStart          = 0;         // Asia Start Hour (UTC)
input int       AsiaEnd            = 8;         // Asia End Hour (UTC)
input bool      TradeLondon        = true;      // Trade London Session (UTC)
input int       LondonStart        = 8;         // London Start Hour (UTC)
input int       LondonEnd          = 16;        // London End Hour (UTC)
input bool      TradeNewYork       = true;      // Trade New York Session (UTC)
input int       NYStart            = 13;        // New York Start Hour (UTC)
input int       NYEnd              = 21;        // New York End Hour (UTC)

//=== Stop Loss ===
input int       HardSL_Pts         = 150;       // Hard Stop Loss (Points)

//=== Breakeven ===
input string    NoteBE             = "==================Breakeven";
input bool      EnableBreakeven    = false;     // Enable Breakeven
input int       BreakevenPts       = 40;        // Breakeven (Points)

//=== Trailing Stop ===
input string    NoteTrail          = "==================Trailing";
input bool      EnableTrailing     = true;      // Enable SL Trailing
input int       TrailStartPts      = 70;        // Trailing Start (Points)
input int       TrailStopPts       = 63;        // Trailing Stop (Points)
input int       TrailStepPts       = 5;         // Trailing Step (Points)

//=== Pending Orders ===
input string    NotePending        = "====== Pending Orders Settings ======";
input bool      ActivatePending    = true;      // Activate Pending Orders
input int       PendingGapPts      = 100;       // Enable Breakout Pending Gap (Points)
input int       NegGapPts          = 100;       // Disable Negative Pending Gap(Points)

//=== Breakout Level ===
input int       N_Bars             = 14;        // Lookback period (10~20, optimize)

//=== RSI Filter ===
input int       RSI_Period         = 14;        // RSI period
input int       RSI_Threshold      = 50;        // RSI threshold (50 = neutral)

//=== Position Management ===
input int       MaxPositions       = 2;         // Max simultaneous positions

//=== Display ===
input bool      ShowPanel          = true;      // Show Panel
input int       FontSize           = 9;         // Panel font size

//+------------------------------------------------------------------+
// Global variables
//+------------------------------------------------------------------+
datetime   g_lastBarTime      = 0;
int        g_pendingTicket    = -1;
int        g_lastPendingType  = -1;

// State tracking
string     g_currentState     = "Initializing";
double     g_breakoutLong     = 0;
double     g_breakoutShort    = 0;
double     g_currentRSI       = 0;
string     g_rsiLabel         = "";
double     g_calcLot          = 0;

// Statistics
int        g_totalEntries     = 0;
int        g_totalCancelled   = 0;
int        g_wins             = 0;
int        g_losses           = 0;
double     g_totalPL          = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   if(N_Bars < 3)
   {
      Alert("EA Gold Algo RE v2: N_Bars must be >= 3");
      return(INIT_PARAMETERS_INCORRECT);
   }

   // Calculate initial lot
   g_calcLot = CalculateLot();

   ScanExistingOrders();

   Print("=== EA Gold Algo RE v2.0 Initialized ===");
   Print("AutoRisk=", UseAutoRisk, " Risk%=", RiskPercent, " Lot=", DoubleToStr(g_calcLot, 2));
   Print("N_Bars=", N_Bars, " PendingGap=", PendingGapPts, " NegGap=", NegGapPts,
         " HardSL=", HardSL_Pts);
   Print("Trailing: Start=", TrailStartPts, " Stop=", TrailStopPts, " Step=", TrailStepPts);
   Print("BE: Enabled=", EnableBreakeven, " Pts=", BreakevenPts);
   Print("Slippage=", MaxSlippage, " MaxSpread=", MaxSpreadPts);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   CleanupPanel();
}

//+------------------------------------------------------------------+
void OnTick()
{
   //--- New bar logic
   bool newBar = (g_lastBarTime != Time[0]);
   if(newBar)
   {
      g_lastBarTime = Time[0];
      OnNewBar();
   }

   //--- Every tick: check breakout and place pending if needed
   if(g_pendingTicket <= 0 && g_breakoutLong > 0 && IsSessionActive())
   {
      double currentSpread = MarketInfo(Symbol(), MODE_SPREAD);
      if(currentSpread <= MaxSpreadPts)
         DetermineStateAndTrade();
   }

   //--- Trailing stop (every tick)
   if(EnableTrailing)
      ManageTrailingStop();

   //--- Breakeven (every tick)
   if(EnableBreakeven)
      ManageBreakeven();

   //--- Check pending fill
   CheckPendingFill();

   //--- Panel
   if(ShowPanel) DrawPanel();
}

//+------------------------------------------------------------------+
//| Calculate Lot based on Risk% and Hard SL                         |
//+------------------------------------------------------------------+
double CalculateLot()
{
   if(!UseAutoRisk)
      return LotSize;

   double riskMoney  = AccountBalance() * (RiskPercent / 100.0);
   double tickValue  = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize   = MarketInfo(Symbol(), MODE_TICKSIZE);

   if(tickValue <= 0 || tickSize <= 0 || HardSL_Pts <= 0)
      return LotSize;

   // SL in price = HardSL_Pts * Point
   // SL ticks = SL in price / tickSize
   // Risk per lot = SL ticks * tickValue
   double slPrice    = HardSL_Pts * Point;
   double slTicks    = slPrice / tickSize;
   double riskPerLot = slTicks * tickValue;

   if(riskPerLot <= 0)
      return LotSize;

   double lot = riskMoney / riskPerLot;

   // Normalize to lot step
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);

   if(lotStep > 0)
      lot = MathFloor(lot / lotStep) * lotStep;

   lot = MathMax(lot, minLot);
   lot = MathMin(lot, maxLot);

   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
void OnNewBar()
{
   //--- Session check
   if(!IsSessionActive())
   {
      CancelPendingOrder();
      g_currentState = "Off Session";
      return;
   }

   //--- Spread check
   double currentSpread = MarketInfo(Symbol(), MODE_SPREAD);
   if(currentSpread > MaxSpreadPts)
   {
      g_currentState = "High Spread";
      return;
   }

   //--- Cancel previous pending
   CancelPendingOrder();

   //--- Calculate Breakout Levels
   CalculateBreakoutLevels();

   //--- Calculate RSI
   g_currentRSI = iRSI(Symbol(), PERIOD_M5, RSI_Period, PRICE_CLOSE, 1);

   //--- Recalculate lot each bar
   g_calcLot = CalculateLot();

   //--- Place order
   DetermineStateAndTrade();
}

//+------------------------------------------------------------------+
void CalculateBreakoutLevels()
{
   double highestHigh = High[1];
   double lowestLow   = Low[1];

   for(int i = 2; i <= N_Bars; i++)
   {
      if(i >= Bars) break;
      if(High[i] > highestHigh) highestHigh = High[i];
      if(Low[i]  < lowestLow)   lowestLow   = Low[i];
   }

   g_breakoutLong  = NormalizeDouble(highestHigh, Digits);
   g_breakoutShort = NormalizeDouble(lowestLow, Digits);
}

//+------------------------------------------------------------------+
//| Determine state and trade - with Negative Gap handling           |
//+------------------------------------------------------------------+
void DetermineStateAndTrade()
{
   int openPos = CountOpenPositions();

   bool priceAboveLong  = (Ask > g_breakoutLong);
   bool priceBelowShort = (Bid < g_breakoutShort);

   //--- Buy side
   if(priceAboveLong)
   {
      if(g_currentRSI > RSI_Threshold)
      {
         g_rsiLabel = "Favourable";
         g_currentState = "Breaking Upwards";

         if(openPos < MaxPositions)
         {
            double pendingEntry = NormalizeDouble(g_breakoutLong + PendingGapPts * Point, Digits);

            // Negative Gap: Ask already past the pending entry price
            if(Ask >= pendingEntry)
            {
               // Check if Ask is too far above breakout (beyond NegGap limit)
               double negLimit = NormalizeDouble(g_breakoutLong + (PendingGapPts + NegGapPts) * Point, Digits);
               if(Ask <= negLimit)
               {
                  // Market entry - price already at/past pending level
                  PlaceMarketBuy();
               }
               else
               {
                  g_currentState = "Breaking Up (Too Far)";
               }
            }
            else
            {
               // Normal: place Buy Stop
               if(ActivatePending)
                  PlaceBuyStop();
            }
         }
         else
         {
            g_currentState += " (Max Pos)";
         }
      }
      else
      {
         g_rsiLabel = "Unfavourable";
         g_currentState = "Breaking Up (Unfav RSI)";
      }
   }
   //--- Sell side
   else if(priceBelowShort)
   {
      if(g_currentRSI < RSI_Threshold)
      {
         g_rsiLabel = "Favourable";
         g_currentState = "Breaking Downwards";

         if(openPos < MaxPositions)
         {
            double pendingEntry = NormalizeDouble(g_breakoutShort - PendingGapPts * Point, Digits);

            // Negative Gap: Bid already past the pending entry price
            if(Bid <= pendingEntry)
            {
               double negLimit = NormalizeDouble(g_breakoutShort - (PendingGapPts + NegGapPts) * Point, Digits);
               if(Bid >= negLimit)
               {
                  PlaceMarketSell();
               }
               else
               {
                  g_currentState = "Breaking Down (Too Far)";
               }
            }
            else
            {
               if(ActivatePending)
                  PlaceSellStop();
            }
         }
         else
         {
            g_currentState += " (Max Pos)";
         }
      }
      else
      {
         g_rsiLabel = "Unfavourable";
         g_currentState = "Breaking Down (Unfav RSI)";
      }
   }
   //--- Range bound
   else
   {
      g_rsiLabel = "-";
      g_currentState = "Range Bound";
   }
}

//+------------------------------------------------------------------+
//| Market Buy - for Negative Gap situations                         |
//+------------------------------------------------------------------+
void PlaceMarketBuy()
{
   if(!IsTradeAllowed() || IsTradeContextBusy()) return;

   double sl = NormalizeDouble(Ask - HardSL_Pts * Point, Digits);

   int ticket = OrderSend(Symbol(), OP_BUY, g_calcLot, Ask, MaxSlippage,
                           sl, 0, "EGAR_MKT", MagicNumber, 0, clrDodgerBlue);

   if(ticket > 0)
   {
      g_totalEntries++;
      Print(">> MarketBUY #", ticket, " @ ", DoubleToStr(Ask, Digits),
            " SL=", DoubleToStr(sl, Digits),
            " Lot=", DoubleToStr(g_calcLot, 2),
            " RSI=", DoubleToStr(g_currentRSI, 1));
   }
   else
   {
      Print("!! MarketBUY FAILED: err=", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Market Sell - for Negative Gap situations                        |
//+------------------------------------------------------------------+
void PlaceMarketSell()
{
   if(!IsTradeAllowed() || IsTradeContextBusy()) return;

   double sl = NormalizeDouble(Bid + HardSL_Pts * Point, Digits);

   int ticket = OrderSend(Symbol(), OP_SELL, g_calcLot, Bid, MaxSlippage,
                           sl, 0, "EGAR_MKT", MagicNumber, 0, clrOrangeRed);

   if(ticket > 0)
   {
      g_totalEntries++;
      Print(">> MarketSELL #", ticket, " @ ", DoubleToStr(Bid, Digits),
            " SL=", DoubleToStr(sl, Digits),
            " Lot=", DoubleToStr(g_calcLot, 2),
            " RSI=", DoubleToStr(g_currentRSI, 1));
   }
   else
   {
      Print("!! MarketSELL FAILED: err=", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Place Buy Stop                                                   |
//+------------------------------------------------------------------+
void PlaceBuyStop()
{
   if(!IsTradeAllowed() || IsTradeContextBusy()) return;

   double entryPrice = NormalizeDouble(g_breakoutLong + PendingGapPts * Point, Digits);

   double minStopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   if(entryPrice <= Ask + minStopLevel)
   {
      // Adjust entry to minimum valid level
      entryPrice = NormalizeDouble(Ask + minStopLevel + Point, Digits);
   }

   double sl = NormalizeDouble(entryPrice - HardSL_Pts * Point, Digits);

   int ticket = OrderSend(Symbol(), OP_BUYSTOP, g_calcLot, entryPrice, MaxSlippage,
                           sl, 0, "EGAR", MagicNumber, 0, clrDodgerBlue);

   if(ticket > 0)
   {
      g_pendingTicket = ticket;
      g_lastPendingType = OP_BUYSTOP;
      Print(">> BuyStop #", ticket, " @ ", DoubleToStr(entryPrice, Digits),
            " SL=", DoubleToStr(sl, Digits),
            " Lot=", DoubleToStr(g_calcLot, 2));
   }
   else
   {
      Print("!! BuyStop FAILED: err=", GetLastError(),
            " price=", DoubleToStr(entryPrice, Digits),
            " Ask=", DoubleToStr(Ask, Digits));
   }
}

//+------------------------------------------------------------------+
//| Place Sell Stop                                                  |
//+------------------------------------------------------------------+
void PlaceSellStop()
{
   if(!IsTradeAllowed() || IsTradeContextBusy()) return;

   double entryPrice = NormalizeDouble(g_breakoutShort - PendingGapPts * Point, Digits);

   double minStopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   if(entryPrice >= Bid - minStopLevel)
   {
      entryPrice = NormalizeDouble(Bid - minStopLevel - Point, Digits);
   }

   double sl = NormalizeDouble(entryPrice + HardSL_Pts * Point, Digits);

   int ticket = OrderSend(Symbol(), OP_SELLSTOP, g_calcLot, entryPrice, MaxSlippage,
                           sl, 0, "EGAR", MagicNumber, 0, clrOrangeRed);

   if(ticket > 0)
   {
      g_pendingTicket = ticket;
      g_lastPendingType = OP_SELLSTOP;
      Print(">> SellStop #", ticket, " @ ", DoubleToStr(entryPrice, Digits),
            " SL=", DoubleToStr(sl, Digits),
            " Lot=", DoubleToStr(g_calcLot, 2));
   }
   else
   {
      Print("!! SellStop FAILED: err=", GetLastError(),
            " price=", DoubleToStr(entryPrice, Digits),
            " Bid=", DoubleToStr(Bid, Digits));
   }
}

//+------------------------------------------------------------------+
void CancelPendingOrder()
{
   if(g_pendingTicket <= 0) return;

   if(!OrderSelect(g_pendingTicket, SELECT_BY_TICKET))
   {
      g_pendingTicket = -1;
      return;
   }

   if(OrderCloseTime() > 0 || OrderType() == OP_BUY || OrderType() == OP_SELL)
   {
      g_pendingTicket = -1;
      return;
   }

   if(OrderType() == OP_BUYSTOP || OrderType() == OP_SELLSTOP)
   {
      if(OrderDelete(g_pendingTicket))
      {
         g_totalCancelled++;
         g_pendingTicket = -1;
      }
   }
}

//+------------------------------------------------------------------+
void CheckPendingFill()
{
   if(g_pendingTicket <= 0) return;
   if(!OrderSelect(g_pendingTicket, SELECT_BY_TICKET)) return;

   if(OrderType() == OP_BUY || OrderType() == OP_SELL)
   {
      g_totalEntries++;
      Print("*** FILLED #", g_pendingTicket,
            OrderType() == OP_BUY ? " BUY" : " SELL",
            " @ ", DoubleToStr(OrderOpenPrice(), Digits));
      g_pendingTicket = -1;
   }
}

//+------------------------------------------------------------------+
//| Trailing Stop Management                                         |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;

      double currentSL = OrderStopLoss();
      double entryPrice = OrderOpenPrice();
      double newSL;

      if(OrderType() == OP_BUY)
      {
         double profitPts = (Bid - entryPrice) / Point;
         if(profitPts < TrailStartPts) continue;

         newSL = NormalizeDouble(Bid - TrailStopPts * Point, Digits);

         if(newSL > currentSL + TrailStepPts * Point)
         {
            if(!OrderModify(OrderTicket(), entryPrice, newSL, 0, 0, clrDodgerBlue))
               Print("!! Trail BUY #", OrderTicket(), " failed: err=", GetLastError());
         }
      }
      else if(OrderType() == OP_SELL)
      {
         double profitPts = (entryPrice - Ask) / Point;
         if(profitPts < TrailStartPts) continue;

         newSL = NormalizeDouble(Ask + TrailStopPts * Point, Digits);

         if(currentSL == 0 || newSL < currentSL - TrailStepPts * Point)
         {
            if(!OrderModify(OrderTicket(), entryPrice, newSL, 0, 0, clrOrangeRed))
               Print("!! Trail SELL #", OrderTicket(), " failed: err=", GetLastError());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Breakeven Management                                             |
//+------------------------------------------------------------------+
void ManageBreakeven()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;

      double entryPrice = OrderOpenPrice();
      double currentSL  = OrderStopLoss();

      if(OrderType() == OP_BUY)
      {
         // If profit >= BE threshold and SL is still below entry
         if(currentSL < entryPrice && (Bid - entryPrice) / Point >= BreakevenPts)
         {
            double newSL = NormalizeDouble(entryPrice + Point, Digits);
            if(!OrderModify(OrderTicket(), entryPrice, newSL, 0, 0, clrDodgerBlue))
               Print("!! BE BUY #", OrderTicket(), " failed: err=", GetLastError());
            else
               Print(">> BE BUY #", OrderTicket(), " SL moved to ", DoubleToStr(newSL, Digits));
         }
      }
      else if(OrderType() == OP_SELL)
      {
         if((currentSL > entryPrice || currentSL == 0) && (entryPrice - Ask) / Point >= BreakevenPts)
         {
            double newSL = NormalizeDouble(entryPrice - Point, Digits);
            if(!OrderModify(OrderTicket(), entryPrice, newSL, 0, 0, clrOrangeRed))
               Print("!! BE SELL #", OrderTicket(), " failed: err=", GetLastError());
            else
               Print(">> BE SELL #", OrderTicket(), " SL moved to ", DoubleToStr(newSL, Digits));
         }
      }
   }
}

//+------------------------------------------------------------------+
bool IsSessionActive()
{
   if(!UseSessionFilter) return true;

   int hour = TimeHour(TimeCurrent());

   bool active = false;

   if(TradeAsian)
   {
      if(AsiaStart < AsiaEnd)
         active = active || (hour >= AsiaStart && hour < AsiaEnd);
      else
         active = active || (hour >= AsiaStart || hour < AsiaEnd);
   }

   if(TradeLondon)
   {
      if(LondonStart < LondonEnd)
         active = active || (hour >= LondonStart && hour < LondonEnd);
      else
         active = active || (hour >= LondonStart || hour < LondonEnd);
   }

   if(TradeNewYork)
   {
      if(NYStart < NYEnd)
         active = active || (hour >= NYStart && hour < NYEnd);
      else
         active = active || (hour >= NYStart || hour < NYEnd);
   }

   return active;
}

//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      if(OrderType() == OP_BUY || OrderType() == OP_SELL) count++;
   }
   return count;
}

//+------------------------------------------------------------------+
void ScanExistingOrders()
{
   g_pendingTicket = -1;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;

      if(OrderType() == OP_BUYSTOP || OrderType() == OP_SELLSTOP)
      {
         g_pendingTicket = OrderTicket();
         g_lastPendingType = OrderType();
      }
   }

   g_totalEntries = 0;
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      if(OrderType() == OP_BUY || OrderType() == OP_SELL)
      {
         double pl = OrderProfit() + OrderSwap() + OrderCommission();
         if(pl > 0) g_wins++;
         else g_losses++;
         g_totalPL += pl;
      }
   }
   g_totalEntries = g_wins + g_losses;
}

//+------------------------------------------------------------------+
void DrawPanel()
{
   double openPL = 0;
   int openCount = 0;
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      if(OrderType() == OP_BUY || OrderType() == OP_SELL)
      {
         openPL += OrderProfit() + OrderSwap() + OrderCommission();
         openCount++;
      }
   }

   double todayPL = 0;
   int todayTrades = 0;
   for(int i = OrdersHistoryTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      if(OrderCloseTime() >= iTime(Symbol(), PERIOD_D1, 0))
      {
         todayPL += OrderProfit() + OrderSwap() + OrderCommission();
         todayTrades++;
      }
   }

   double spread = MarketInfo(Symbol(), MODE_SPREAD);

   MakeLabel("EGAR_L1", 10, 20,
      "EA Gold Algo RE v2.0 | " + Symbol() + " M" + IntegerToString(Period()),
      clrGold);

   color stateClr = clrWhite;
   if(StringFind(g_currentState, "Up") >= 0) stateClr = clrLime;
   else if(StringFind(g_currentState, "Down") >= 0) stateClr = clrOrangeRed;
   else if(g_currentState == "Range Bound") stateClr = clrYellow;
   else if(StringFind(g_currentState, "Unfav") >= 0) stateClr = clrGray;

   MakeLabel("EGAR_L2", 10, 38,
      "State: " + g_currentState + "  RSI: " + DoubleToStr(g_currentRSI, 1) +
      " (" + g_rsiLabel + ")",
      stateClr);

   MakeLabel("EGAR_L3", 10, 56,
      "B.Long: " + DoubleToStr(g_breakoutLong, Digits) +
      "  B.Short: " + DoubleToStr(g_breakoutShort, Digits) +
      "  Range: $" + DoubleToStr(g_breakoutLong - g_breakoutShort, 2),
      clrCyan);

   string pendStr = (g_pendingTicket > 0) ?
      "#" + IntegerToString(g_pendingTicket) + " " +
      (g_lastPendingType == OP_BUYSTOP ? "BuyStop" : "SellStop") :
      "None";
   MakeLabel("EGAR_L4", 10, 74,
      "Pos: " + IntegerToString(openCount) + "/" + IntegerToString(MaxPositions) +
      "  Pend: " + pendStr +
      "  Spread: " + DoubleToStr(spread, 0) +
      "  Lot: " + DoubleToStr(g_calcLot, 2),
      clrWhite);

   MakeLabel("EGAR_L5", 10, 92,
      "Open P/L: $" + DoubleToStr(openPL, 2) +
      "  Today: $" + DoubleToStr(todayPL, 2) +
      " (" + IntegerToString(todayTrades) + ")",
      (openPL + todayPL) >= 0 ? clrLime : clrRed);

   MakeLabel("EGAR_L6", 10, 110,
      "Entries: " + IntegerToString(g_totalEntries) +
      "  Cancel: " + IntegerToString(g_totalCancelled) +
      "  N=" + IntegerToString(N_Bars) +
      "  Risk=" + DoubleToStr(RiskPercent, 1) + "%",
      clrDimGray);

   DrawBreakoutLines();
}

//+------------------------------------------------------------------+
void DrawBreakoutLines()
{
   if(ObjectFind("EGAR_BL") < 0)
      ObjectCreate("EGAR_BL", OBJ_HLINE, 0, 0, g_breakoutLong);
   else
      ObjectSet("EGAR_BL", OBJPROP_PRICE1, g_breakoutLong);
   ObjectSet("EGAR_BL", OBJPROP_COLOR, clrDodgerBlue);
   ObjectSet("EGAR_BL", OBJPROP_STYLE, STYLE_DASH);
   ObjectSet("EGAR_BL", OBJPROP_WIDTH, 1);
   ObjectSet("EGAR_BL", OBJPROP_BACK, true);

   if(ObjectFind("EGAR_BS") < 0)
      ObjectCreate("EGAR_BS", OBJ_HLINE, 0, 0, g_breakoutShort);
   else
      ObjectSet("EGAR_BS", OBJPROP_PRICE1, g_breakoutShort);
   ObjectSet("EGAR_BS", OBJPROP_COLOR, clrOrangeRed);
   ObjectSet("EGAR_BS", OBJPROP_STYLE, STYLE_DASH);
   ObjectSet("EGAR_BS", OBJPROP_WIDTH, 1);
   ObjectSet("EGAR_BS", OBJPROP_BACK, true);

   if(g_pendingTicket > 0 && OrderSelect(g_pendingTicket, SELECT_BY_TICKET))
   {
      double pendingPrice = OrderOpenPrice();
      if(ObjectFind("EGAR_PE") < 0)
         ObjectCreate("EGAR_PE", OBJ_HLINE, 0, 0, pendingPrice);
      else
         ObjectSet("EGAR_PE", OBJPROP_PRICE1, pendingPrice);

      color peClr = (OrderType() == OP_BUYSTOP) ? clrLime : clrRed;
      ObjectSet("EGAR_PE", OBJPROP_COLOR, peClr);
      ObjectSet("EGAR_PE", OBJPROP_STYLE, STYLE_SOLID);
      ObjectSet("EGAR_PE", OBJPROP_WIDTH, 2);
      ObjectSet("EGAR_PE", OBJPROP_BACK, false);
   }
   else
   {
      ObjectDelete("EGAR_PE");
   }
}

//+------------------------------------------------------------------+
void MakeLabel(string name, int x, int y, string text, color clr)
{
   if(ObjectFind(name) < 0)
      ObjectCreate(name, OBJ_LABEL, 0, 0, 0);
   ObjectSet(name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSet(name, OBJPROP_XDISTANCE, x);
   ObjectSet(name, OBJPROP_YDISTANCE, y);
   ObjectSetText(name, text, FontSize, "Consolas", clr);
}

//+------------------------------------------------------------------+
void CleanupPanel()
{
   for(int i = ObjectsTotal() - 1; i >= 0; i--)
   {
      string name = ObjectName(i);
      if(StringFind(name, "EGAR_") == 0)
         ObjectDelete(name);
   }
}
//+------------------------------------------------------------------+
