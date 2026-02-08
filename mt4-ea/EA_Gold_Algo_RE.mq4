//+------------------------------------------------------------------+
//|                                              EA_Gold_Algo_RE.mq4 |
//|         EA Gold Algo Reverse Engineering v1.0                     |
//|         Liquidity Breakout + RSI Filter + Trailing SL            |
//+------------------------------------------------------------------+
#property copyright "Reverse Engineering Project 2026"
#property link      ""
#property version   "1.00"
#property strict

//=== Breakout Level ===
input int       N_Bars             = 14;       // Lookback period (10~20, optimize)
input int       PendingGapPts      = 100;      // Pending order gap (100pt = $1.00)

//=== Stop Loss ===
input int       HardSL_Pts         = 150;      // Hard SL (150pt = $1.50)

//=== Trailing Stop ===
input int       TrailStartPts      = 70;       // Trailing start (70pt = $0.70)
input int       TrailStepPts       = 5;        // Trailing step (5pt = $0.05)
input int       TrailStopPts       = 63;       // Trailing distance (63pt = $0.63)

//=== RSI Filter ===
input int       RSI_Period         = 14;       // RSI period
input int       RSI_Threshold      = 50;       // RSI threshold (50 = neutral)

//=== Position Management ===
input int       MaxPositions       = 2;        // Max simultaneous positions
input double    LotSize            = 0.67;     // Lot size

//=== Session Filter (UTC hours) ===
input bool      UseLondon          = true;     // London session
input int       LondonStart        = 8;        // London start (UTC)
input int       LondonEnd          = 16;       // London end (UTC)
input bool      UseNewYork         = true;     // New York session
input int       NYStart            = 13;       // NY start (UTC)
input int       NYEnd              = 21;       // NY end (UTC)

//=== Misc ===
input int       MagicNumber        = 20260211; // Magic number
input double    MaxSpreadPts       = 50;       // Max spread (points)
input bool      ShowPanel          = true;     // Show info panel
input int       FontSize           = 9;        // Panel font size

//+------------------------------------------------------------------+
// Global variables
//+------------------------------------------------------------------+
datetime   g_lastBarTime      = 0;
int        g_pendingTicket    = -1;          // Current pending order ticket
int        g_lastPendingType  = -1;          // Last pending type (OP_BUYSTOP/SELLSTOP)

// State tracking
string     g_currentState     = "Initializing";
double     g_breakoutLong     = 0;
double     g_breakoutShort    = 0;
double     g_currentRSI       = 0;
string     g_rsiLabel         = "";

// Statistics
int        g_totalEntries     = 0;
int        g_totalCancelled   = 0;
int        g_wins             = 0;
int        g_losses           = 0;
double     g_totalPL          = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   // Validate parameters
   if(LotSize <= 0)
   {
      Alert("EA Gold Algo RE: LotSize must be > 0");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(N_Bars < 3)
   {
      Alert("EA Gold Algo RE: N_Bars must be >= 3");
      return(INIT_PARAMETERS_INCORRECT);
   }

   // Scan for any existing pending/positions from previous session
   ScanExistingOrders();

   Print("=== EA Gold Algo RE v1.0 Initialized ===");
   Print("N_Bars=", N_Bars, " PendingGap=", PendingGapPts,
         " HardSL=", HardSL_Pts, " TrailStart=", TrailStartPts,
         " TrailStep=", TrailStepPts, " TrailStop=", TrailStopPts);
   Print("RSI=", RSI_Period, " Threshold=", RSI_Threshold,
         " MaxPos=", MaxPositions, " Lot=", DoubleToStr(LotSize, 2));

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
   //--- New bar logic (runs once per M5 bar)
   bool newBar = (g_lastBarTime != Time[0]);
   if(newBar)
   {
      g_lastBarTime = Time[0];
      OnNewBar();
   }

   //--- Trailing stop (runs every tick)
   ManageTrailingStop();

   //--- Check if pending orders got filled
   CheckPendingFill();

   //--- Update panel
   if(ShowPanel) DrawPanel();
}

//+------------------------------------------------------------------+
//| Main logic: runs on every new M5 bar                             |
//+------------------------------------------------------------------+
void OnNewBar()
{
   //--- Step 1: Session check
   if(!IsSessionActive())
   {
      CancelPendingOrder();
      g_currentState = "Off Session";
      return;
   }

   //--- Step 2: Spread check
   double currentSpread = MarketInfo(Symbol(), MODE_SPREAD);
   if(currentSpread > MaxSpreadPts)
   {
      g_currentState = "High Spread";
      return;
   }

   //--- Step 3: Cancel previous pending order
   CancelPendingOrder();

   //--- Step 4: Calculate Breakout Levels
   CalculateBreakoutLevels();

   //--- Step 5: Calculate RSI
   g_currentRSI = iRSI(Symbol(), PERIOD_M5, RSI_Period, PRICE_CLOSE, 1);

   //--- Step 6: Determine state and place order
   DetermineStateAndTrade();
}

//+------------------------------------------------------------------+
//| Calculate Breakout Long (Highest High) and Short (Lowest Low)    |
//+------------------------------------------------------------------+
void CalculateBreakoutLevels()
{
   // Use bar index 1 to N_Bars (exclude current unfinished bar 0)
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
//| Determine EA state and place appropriate pending order           |
//+------------------------------------------------------------------+
void DetermineStateAndTrade()
{
   double closePrice = Close[1];  // Previous bar close

   //--- Check position count
   int openPos = CountOpenPositions();

   //--- Determine direction based on price vs breakout levels
   bool priceAboveLong  = (closePrice > g_breakoutLong);
   bool priceBelowShort = (closePrice < g_breakoutShort);

   //--- Buy side logic
   if(priceAboveLong)
   {
      if(g_currentRSI > RSI_Threshold)
      {
         // Favourable RSI for Buy
         g_rsiLabel = "Favourable";
         g_currentState = "Breaking Upwards";

         if(openPos < MaxPositions)
         {
            PlaceBuyStop();
         }
         else
         {
            g_currentState += " (Max Pos)";
         }
      }
      else
      {
         // Unfavourable RSI for Buy
         g_rsiLabel = "Unfavourable";
         g_currentState = "Breaking Up (Unfav RSI)";
      }
   }
   //--- Sell side logic
   else if(priceBelowShort)
   {
      if(g_currentRSI < RSI_Threshold)
      {
         // Favourable RSI for Sell
         g_rsiLabel = "Favourable";
         g_currentState = "Breaking Downwards";

         if(openPos < MaxPositions)
         {
            PlaceSellStop();
         }
         else
         {
            g_currentState += " (Max Pos)";
         }
      }
      else
      {
         // Unfavourable RSI for Sell
         g_rsiLabel = "Unfavourable";
         g_currentState = "Breaking Down (Unfav RSI)";
      }
   }
   //--- Range bound: price between breakout levels
   else
   {
      g_rsiLabel = "-";
      g_currentState = "Range Bound";
   }
}

//+------------------------------------------------------------------+
//| Place Buy Stop order at Breakout Long + PendingGap               |
//+------------------------------------------------------------------+
void PlaceBuyStop()
{
   if(!IsTradeAllowed() || IsTradeContextBusy()) return;

   double entryPrice = NormalizeDouble(g_breakoutLong + PendingGapPts * Point, Digits);

   // Ensure entry price is above current Ask + stop level
   double minStopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   if(entryPrice <= Ask + minStopLevel)
   {
      // Entry too close to current price, skip this bar
      return;
   }

   double sl = NormalizeDouble(entryPrice - HardSL_Pts * Point, Digits);

   int ticket = OrderSend(Symbol(), OP_BUYSTOP, LotSize, entryPrice, 0,
                           sl, 0,  // TP = 0 (trailing only)
                           "EGAR", MagicNumber, 0, clrDodgerBlue);

   if(ticket > 0)
   {
      g_pendingTicket = ticket;
      g_lastPendingType = OP_BUYSTOP;
      Print(">> BuyStop #", ticket, " @ ", DoubleToStr(entryPrice, Digits),
            " SL=", DoubleToStr(sl, Digits),
            " B.Long=", DoubleToStr(g_breakoutLong, Digits),
            " RSI=", DoubleToStr(g_currentRSI, 1));
   }
   else
   {
      int err = GetLastError();
      Print("!! BuyStop FAILED: err=", err, " price=", DoubleToStr(entryPrice, Digits),
            " Ask=", DoubleToStr(Ask, Digits),
            " minStop=", DoubleToStr(minStopLevel, Digits));
   }
}

//+------------------------------------------------------------------+
//| Place Sell Stop order at Breakout Short - PendingGap             |
//+------------------------------------------------------------------+
void PlaceSellStop()
{
   if(!IsTradeAllowed() || IsTradeContextBusy()) return;

   double entryPrice = NormalizeDouble(g_breakoutShort - PendingGapPts * Point, Digits);

   // Ensure entry price is below current Bid - stop level
   double minStopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   if(entryPrice >= Bid - minStopLevel)
   {
      // Entry too close to current price, skip this bar
      return;
   }

   double sl = NormalizeDouble(entryPrice + HardSL_Pts * Point, Digits);

   int ticket = OrderSend(Symbol(), OP_SELLSTOP, LotSize, entryPrice, 0,
                           sl, 0,  // TP = 0 (trailing only)
                           "EGAR", MagicNumber, 0, clrOrangeRed);

   if(ticket > 0)
   {
      g_pendingTicket = ticket;
      g_lastPendingType = OP_SELLSTOP;
      Print(">> SellStop #", ticket, " @ ", DoubleToStr(entryPrice, Digits),
            " SL=", DoubleToStr(sl, Digits),
            " B.Short=", DoubleToStr(g_breakoutShort, Digits),
            " RSI=", DoubleToStr(g_currentRSI, 1));
   }
   else
   {
      int err = GetLastError();
      Print("!! SellStop FAILED: err=", err, " price=", DoubleToStr(entryPrice, Digits),
            " Bid=", DoubleToStr(Bid, Digits),
            " minStop=", DoubleToStr(minStopLevel, Digits));
   }
}

//+------------------------------------------------------------------+
//| Cancel existing pending order                                    |
//+------------------------------------------------------------------+
void CancelPendingOrder()
{
   if(g_pendingTicket <= 0) return;

   if(!OrderSelect(g_pendingTicket, SELECT_BY_TICKET))
   {
      g_pendingTicket = -1;
      return;
   }

   // If already filled or closed, just clear the reference
   if(OrderCloseTime() > 0 || OrderType() == OP_BUY || OrderType() == OP_SELL)
   {
      g_pendingTicket = -1;
      return;
   }

   // Delete pending order
   if(OrderType() == OP_BUYSTOP || OrderType() == OP_SELLSTOP)
   {
      if(OrderDelete(g_pendingTicket))
      {
         g_totalCancelled++;
         g_pendingTicket = -1;
      }
      else
      {
         Print("!! Cancel pending #", g_pendingTicket, " failed: err=", GetLastError());
      }
   }
}

//+------------------------------------------------------------------+
//| Check if pending order was filled (became market order)          |
//+------------------------------------------------------------------+
void CheckPendingFill()
{
   if(g_pendingTicket <= 0) return;

   if(!OrderSelect(g_pendingTicket, SELECT_BY_TICKET)) return;

   // Pending order got filled -> became market position
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
//| Trailing Stop Management (runs every tick)                       |
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

         // Trail SL at TrailStopPts behind Bid
         newSL = NormalizeDouble(Bid - TrailStopPts * Point, Digits);

         // Only modify if new SL is better by at least TrailStepPts
         if(newSL > currentSL + TrailStepPts * Point)
         {
            if(!OrderModify(OrderTicket(), entryPrice, newSL, 0, 0, clrDodgerBlue))
            {
               Print("!! Trail BUY #", OrderTicket(), " failed: err=", GetLastError());
            }
         }
      }
      else if(OrderType() == OP_SELL)
      {
         double profitPts = (entryPrice - Ask) / Point;
         if(profitPts < TrailStartPts) continue;

         // Trail SL at TrailStopPts above Ask
         newSL = NormalizeDouble(Ask + TrailStopPts * Point, Digits);

         // Only modify if new SL is better (lower) by at least TrailStepPts
         if(currentSL == 0 || newSL < currentSL - TrailStepPts * Point)
         {
            if(!OrderModify(OrderTicket(), entryPrice, newSL, 0, 0, clrOrangeRed))
            {
               Print("!! Trail SELL #", OrderTicket(), " failed: err=", GetLastError());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Session filter: is current time within active sessions?          |
//+------------------------------------------------------------------+
bool IsSessionActive()
{
   if(!UseLondon && !UseNewYork) return true;

   // Get current UTC hour
   // Note: TimeCurrent() returns server time.
   // For accurate UTC, adjust if your broker offset differs.
   int hour = TimeHour(TimeCurrent());

   bool londonActive  = false;
   bool newYorkActive = false;

   if(UseLondon)
   {
      if(LondonStart < LondonEnd)
         londonActive = (hour >= LondonStart && hour < LondonEnd);
      else
         londonActive = (hour >= LondonStart || hour < LondonEnd);
   }

   if(UseNewYork)
   {
      if(NYStart < NYEnd)
         newYorkActive = (hour >= NYStart && hour < NYEnd);
      else
         newYorkActive = (hour >= NYStart || hour < NYEnd);
   }

   return (londonActive || newYorkActive);
}

//+------------------------------------------------------------------+
//| Count open market positions for this EA                          |
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
//| Scan existing orders on init (recovery after restart)            |
//+------------------------------------------------------------------+
void ScanExistingOrders()
{
   g_pendingTicket = -1;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;

      // Find existing pending order
      if(OrderType() == OP_BUYSTOP || OrderType() == OP_SELLSTOP)
      {
         g_pendingTicket = OrderTicket();
         g_lastPendingType = OrderType();
         Print("Found existing pending #", g_pendingTicket);
      }
   }

   // Count existing positions for stats
   g_totalEntries = 0;
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      {
         double pl = OrderProfit() + OrderSwap() + OrderCommission();
         if(pl > 0) g_wins++;
         else g_losses++;
         g_totalPL += pl;
   }
   g_totalEntries = g_wins + g_losses;
}

//+------------------------------------------------------------------+
//| Draw information panel                                           |
//+------------------------------------------------------------------+
void DrawPanel()
{
   //--- Current open positions P/L
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

   //--- Today's historical P/L
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

   // Line 1: Title + State
   string stateColor = "";
   color line1Color = clrYellow;
   MakeLabel("EGAR_L1", 10, 20,
      "EA Gold Algo RE v1.0 | " + Symbol() + " M" + IntegerToString(Period()),
      clrGold);

   // Line 2: State + RSI
   color stateClr = clrWhite;
   if(StringFind(g_currentState, "Up") >= 0 || StringFind(g_currentState, "Upwards") >= 0)
      stateClr = clrLime;
   else if(StringFind(g_currentState, "Down") >= 0)
      stateClr = clrOrangeRed;
   else if(g_currentState == "Range Bound")
      stateClr = clrYellow;
   else if(StringFind(g_currentState, "Unfav") >= 0)
      stateClr = clrGray;

   MakeLabel("EGAR_L2", 10, 38,
      "State: " + g_currentState + "  RSI: " + DoubleToStr(g_currentRSI, 1) +
      " (" + g_rsiLabel + ")",
      stateClr);

   // Line 3: Breakout Levels
   MakeLabel("EGAR_L3", 10, 56,
      "B.Long: " + DoubleToStr(g_breakoutLong, Digits) +
      "  B.Short: " + DoubleToStr(g_breakoutShort, Digits) +
      "  Range: $" + DoubleToStr(g_breakoutLong - g_breakoutShort, 2),
      clrCyan);

   // Line 4: Positions + Pending
   string pendStr = (g_pendingTicket > 0) ?
      "#" + IntegerToString(g_pendingTicket) + " " +
      (g_lastPendingType == OP_BUYSTOP ? "BuyStop" : "SellStop") :
      "None";
   MakeLabel("EGAR_L4", 10, 74,
      "Positions: " + IntegerToString(openCount) + "/" + IntegerToString(MaxPositions) +
      "  Pending: " + pendStr +
      "  Spread: " + DoubleToStr(spread, 0) + "pt",
      clrWhite);

   // Line 5: P/L
   MakeLabel("EGAR_L5", 10, 92,
      "Open P/L: $" + DoubleToStr(openPL, 2) +
      "  Today: $" + DoubleToStr(todayPL, 2) +
      " (" + IntegerToString(todayTrades) + " trades)",
      (openPL + todayPL) >= 0 ? clrLime : clrRed);

   // Line 6: Stats
   MakeLabel("EGAR_L6", 10, 110,
      "Entries: " + IntegerToString(g_totalEntries) +
      "  Cancelled: " + IntegerToString(g_totalCancelled) +
      "  N=" + IntegerToString(N_Bars),
      clrDimGray);

   //--- Draw Breakout Level lines
   DrawBreakoutLines();
}

//+------------------------------------------------------------------+
//| Draw horizontal lines for Breakout Long and Short                |
//+------------------------------------------------------------------+
void DrawBreakoutLines()
{
   // Breakout Long line
   if(ObjectFind("EGAR_BL") < 0)
      ObjectCreate("EGAR_BL", OBJ_HLINE, 0, 0, g_breakoutLong);
   else
      ObjectSet("EGAR_BL", OBJPROP_PRICE1, g_breakoutLong);

   ObjectSet("EGAR_BL", OBJPROP_COLOR, clrDodgerBlue);
   ObjectSet("EGAR_BL", OBJPROP_STYLE, STYLE_DASH);
   ObjectSet("EGAR_BL", OBJPROP_WIDTH, 1);
   ObjectSet("EGAR_BL", OBJPROP_BACK, true);

   // Breakout Short line
   if(ObjectFind("EGAR_BS") < 0)
      ObjectCreate("EGAR_BS", OBJ_HLINE, 0, 0, g_breakoutShort);
   else
      ObjectSet("EGAR_BS", OBJPROP_PRICE1, g_breakoutShort);

   ObjectSet("EGAR_BS", OBJPROP_COLOR, clrOrangeRed);
   ObjectSet("EGAR_BS", OBJPROP_STYLE, STYLE_DASH);
   ObjectSet("EGAR_BS", OBJPROP_WIDTH, 1);
   ObjectSet("EGAR_BS", OBJPROP_BACK, true);

   // Pending entry line (if exists)
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
//| Helper: Create or update label object                            |
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
//| Cleanup all panel objects                                        |
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
