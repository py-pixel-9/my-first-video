//+------------------------------------------------------------------+
//|                                    SMC_Professional_Signal.mq4   |
//|                          BOS/CHoCH with Smart Filtering          |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026 - Option B"
#property link      ""
#property version   "2.00"
#property strict
#property indicator_chart_window

// === 옵션 B: 균형 접근 파라미터 ===
input int MarketStructureTimeHorizon = 35;      // Market Structure Time-Horizon (30-35 권장)
input double MinimumPriceRange = 30.0;          // 최소 가격 범위 (pips)
input int MaxSwingsToTrack = 5;                 // 최근 스윙 추적 개수
input double BreakoutDistance = 30.0;           // 돌파 거리 (pips)
input bool UseTrendFilter = true;               // 추세 필터 사용
input bool ShowCHoCHLabels = true;              // CHoCH 라벨 표시
input int ArrowSize = 3;                        // 화살표 크기
input color BullishColor = clrAqua;             // 매수 신호 색상
input color BearishColor = clrMagenta;          // 매도 신호 색상
input bool ShowBOSCHoCHLines = true;            // 수평선 표시
input bool PCPopupAlert = true;                 // PC 알림
input bool ShowPanelAtTopLeft = true;           // 패널 표시
input int FontSize = 12;                        // 폰트 크기

// Global arrays for swing points
double swingHighPrices[];
int swingHighBars[];
datetime swingHighTimes[];
double swingLowPrices[];
int swingLowBars[];
datetime swingLowTimes[];

// Structure tracking arrays
double structPrices[];
int structBars[];
string structTypes[];
bool structIsBuy[];
bool structConfirmed[];

// Global variables
bool currentTrend = true; // true = bullish, false = bearish
datetime lastAlertTime = 0;
double pointSize;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorShortName("SMC Professional Signal (Option B)");

   // Calculate point size for pips conversion
   pointSize = Point;
   if(Digits == 3 || Digits == 5) pointSize = Point * 10;

   ArrayResize(swingHighPrices, 0);
   ArrayResize(swingHighBars, 0);
   ArrayResize(swingHighTimes, 0);
   ArrayResize(swingLowPrices, 0);
   ArrayResize(swingLowBars, 0);
   ArrayResize(swingLowTimes, 0);

   ArrayResize(structPrices, 0);
   ArrayResize(structBars, 0);
   ArrayResize(structTypes, 0);
   ArrayResize(structIsBuy, 0);
   ArrayResize(structConfirmed, 0);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   // Find swing points
   FindSwingPoints();

   // Filter swing points
   FilterSwingPoints();

   // Determine trend
   if(UseTrendFilter)
      DetermineTrend();

   // Detect structures
   DetectStructures();

   // Draw on chart
   DrawStructures();

   // Draw panel
   if(ShowPanelAtTopLeft)
      DrawPanel();

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Find swing high and low points                                   |
//+------------------------------------------------------------------+
void FindSwingPoints()
{
   ArrayResize(swingHighPrices, 0);
   ArrayResize(swingHighBars, 0);
   ArrayResize(swingHighTimes, 0);
   ArrayResize(swingLowPrices, 0);
   ArrayResize(swingLowBars, 0);
   ArrayResize(swingLowTimes, 0);

   int lookback = MarketStructureTimeHorizon;

   for(int i = lookback; i < Bars - lookback; i++)
   {
      // Check for swing high
      bool isSwingHigh = true;
      for(int j = 1; j <= lookback; j++)
      {
         if(High[i] <= High[i+j] || High[i] <= High[i-j])
         {
            isSwingHigh = false;
            break;
         }
      }

      if(isSwingHigh)
      {
         int size = ArraySize(swingHighPrices);
         ArrayResize(swingHighPrices, size + 1);
         ArrayResize(swingHighBars, size + 1);
         ArrayResize(swingHighTimes, size + 1);
         swingHighPrices[size] = High[i];
         swingHighBars[size] = i;
         swingHighTimes[size] = Time[i];
      }

      // Check for swing low
      bool isSwingLow = true;
      for(int j = 1; j <= lookback; j++)
      {
         if(Low[i] >= Low[i+j] || Low[i] >= Low[i-j])
         {
            isSwingLow = false;
            break;
         }
      }

      if(isSwingLow)
      {
         int size = ArraySize(swingLowPrices);
         ArrayResize(swingLowPrices, size + 1);
         ArrayResize(swingLowBars, size + 1);
         ArrayResize(swingLowTimes, size + 1);
         swingLowPrices[size] = Low[i];
         swingLowBars[size] = i;
         swingLowTimes[size] = Time[i];
      }
   }
}

//+------------------------------------------------------------------+
//| Filter swing points by minimum range                             |
//+------------------------------------------------------------------+
void FilterSwingPoints()
{
   double minRange = MinimumPriceRange * pointSize;

   // Filter highs
   int highCount = ArraySize(swingHighPrices);
   for(int i = highCount - 1; i >= 0; i--)
   {
      // Find corresponding low
      double nearestLow = 0;
      for(int j = 0; j < ArraySize(swingLowPrices); j++)
      {
         if(MathAbs(swingLowBars[j] - swingHighBars[i]) < MarketStructureTimeHorizon * 2)
         {
            nearestLow = swingLowPrices[j];
            break;
         }
      }

      // Check range
      if(nearestLow > 0 && (swingHighPrices[i] - nearestLow) < minRange)
      {
         RemoveSwingHigh(i);
      }
   }

   // Keep only recent swings
   if(ArraySize(swingHighPrices) > MaxSwingsToTrack)
   {
      int toRemove = ArraySize(swingHighPrices) - MaxSwingsToTrack;
      for(int i = 0; i < toRemove; i++)
      {
         RemoveSwingHigh(ArraySize(swingHighPrices) - 1);
      }
   }

   if(ArraySize(swingLowPrices) > MaxSwingsToTrack)
   {
      int toRemove = ArraySize(swingLowPrices) - MaxSwingsToTrack;
      for(int i = 0; i < toRemove; i++)
      {
         RemoveSwingLow(ArraySize(swingLowPrices) - 1);
      }
   }
}

//+------------------------------------------------------------------+
//| Determine current trend                                          |
//+------------------------------------------------------------------+
void DetermineTrend()
{
   int highSize = ArraySize(swingHighPrices);
   int lowSize = ArraySize(swingLowPrices);

   if(highSize < 2 || lowSize < 2) return;

   // Compare recent highs and lows (Higher High / Higher Low pattern)
   bool higherHigh = swingHighPrices[0] > swingHighPrices[1];
   bool higherLow = (lowSize >= 2 && swingLowPrices[0] > swingLowPrices[1]);

   if(higherHigh && higherLow)
      currentTrend = true; // Bullish
   else if(!higherHigh && !higherLow)
      currentTrend = false; // Bearish
}

//+------------------------------------------------------------------+
//| Detect BOS and CHoCH structures                                  |
//+------------------------------------------------------------------+
void DetectStructures()
{
   int highSize = ArraySize(swingHighPrices);
   int lowSize = ArraySize(swingLowPrices);

   if(highSize < 2 || lowSize < 2) return;

   double breakDist = BreakoutDistance * pointSize;

   // Scan recent bars for structure breaks
   int barsToScan = MathMin(300, Bars - MarketStructureTimeHorizon);

   for(int bar = 1; bar < barsToScan; bar++)
   {
      // Check for bullish breaks (BOS or CHoCH)
      for(int h = 0; h < highSize; h++)
      {
         if(swingHighBars[h] >= bar) continue;

         double swingPrice = swingHighPrices[h];

         // Check if this bar broke the swing high
         if(High[bar] > swingPrice + breakDist && High[bar+1] <= swingPrice)
         {
            // Determine if BOS or CHoCH
            bool isBOS = currentTrend; // If bullish trend, breaking high = BOS
            string signalType = isBOS ? "BOS" : "CHoCH";

            if(isBOS || ShowCHoCHLabels)
            {
               if(!StructureExistsAt(swingPrice, true, bar))
               {
                  AddStructure(swingPrice, bar, signalType, true, true);
               }
            }
            break;
         }
      }

      // Check for bearish breaks
      for(int l = 0; l < lowSize; l++)
      {
         if(swingLowBars[l] >= bar) continue;

         double swingPrice = swingLowPrices[l];

         // Check if this bar broke the swing low
         if(Low[bar] < swingPrice - breakDist && Low[bar+1] >= swingPrice)
         {
            // Determine if BOS or CHoCH
            bool isBOS = !currentTrend; // If bearish trend, breaking low = BOS
            string signalType = isBOS ? "BOS" : "CHoCH";

            if(isBOS || ShowCHoCHLabels)
            {
               if(!StructureExistsAt(swingPrice, false, bar))
               {
                  AddStructure(swingPrice, bar, signalType, false, true);
               }
            }
            break;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Add structure to arrays                                          |
//+------------------------------------------------------------------+
void AddStructure(double price, int bar, string type, bool isBuy, bool confirmed)
{
   int size = ArraySize(structPrices);
   ArrayResize(structPrices, size + 1);
   ArrayResize(structBars, size + 1);
   ArrayResize(structTypes, size + 1);
   ArrayResize(structIsBuy, size + 1);
   ArrayResize(structConfirmed, size + 1);

   structPrices[size] = price;
   structBars[size] = bar;
   structTypes[size] = type;
   structIsBuy[size] = isBuy;
   structConfirmed[size] = confirmed;
}

//+------------------------------------------------------------------+
//| Check if structure exists at location                            |
//+------------------------------------------------------------------+
bool StructureExistsAt(double price, bool isBuy, int bar)
{
   for(int i = 0; i < ArraySize(structPrices); i++)
   {
      if(MathAbs(structPrices[i] - price) < 20 * pointSize &&
         structIsBuy[i] == isBuy &&
         MathAbs(structBars[i] - bar) < 10)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Draw structures on chart                                         |
//+------------------------------------------------------------------+
void DrawStructures()
{
   for(int i = 0; i < ArraySize(structPrices); i++)
   {
      if(!structConfirmed[i]) continue;

      string objName = "SMC_Pro_" + structTypes[i] + "_" + IntegerToString(structBars[i]);
      datetime objTime = Time[structBars[i]];
      color objColor = structIsBuy[i] ? BullishColor : BearishColor;

      double labelPrice = structIsBuy[i] ?
         structPrices[i] + (20 * pointSize) :
         structPrices[i] - (20 * pointSize);

      // Draw arrow
      if(ObjectFind(objName + "_Arrow") < 0)
      {
         ObjectCreate(objName + "_Arrow", OBJ_ARROW, 0, objTime, structPrices[i]);
         ObjectSet(objName + "_Arrow", OBJPROP_ARROWCODE, structIsBuy[i] ? 233 : 234);
         ObjectSet(objName + "_Arrow", OBJPROP_COLOR, objColor);
         ObjectSet(objName + "_Arrow", OBJPROP_WIDTH, ArrowSize + 1);
         ObjectSet(objName + "_Arrow", OBJPROP_BACK, false);
      }

      // Draw label
      if(ObjectFind(objName + "_Label") < 0)
      {
         ObjectCreate(objName + "_Label", OBJ_TEXT, 0, objTime, labelPrice);
         ObjectSetText(objName + "_Label", "  " + structTypes[i] + "  ", FontSize + 2, "Arial Black", objColor);
         ObjectSet(objName + "_Label", OBJPROP_BACK, false);
      }

      // Draw line
      if(ShowBOSCHoCHLines)
      {
         if(ObjectFind(objName + "_Line") < 0)
         {
            ObjectCreate(objName + "_Line", OBJ_TREND, 0, Time[structBars[i]], structPrices[i], Time[0], structPrices[i]);
            ObjectSet(objName + "_Line", OBJPROP_COLOR, objColor);
            ObjectSet(objName + "_Line", OBJPROP_STYLE, STYLE_DASHDOT);
            ObjectSet(objName + "_Line", OBJPROP_WIDTH, 2);
            ObjectSet(objName + "_Line", OBJPROP_RAY_RIGHT, true);
            ObjectSet(objName + "_Line", OBJPROP_BACK, false);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Draw information panel                                           |
//+------------------------------------------------------------------+
void DrawPanel()
{
   int buyCount = 0, sellCount = 0;
   int bosCount = 0, chochCount = 0;

   for(int i = 0; i < ArraySize(structPrices); i++)
   {
      if(structConfirmed[i])
      {
         if(structIsBuy[i]) buyCount++;
         else sellCount++;

         if(structTypes[i] == "BOS") bosCount++;
         else chochCount++;
      }
   }

   string signalText = "Signal: ";
   color signalColor = clrWhite;

   if(buyCount > sellCount)
   {
      signalText = signalText + "Buy Now";
      signalColor = BullishColor;
   }
   else if(sellCount > buyCount)
   {
      signalText = signalText + "Sell Now";
      signalColor = BearishColor;
   }
   else
   {
      signalText = signalText + "Neutral";
   }

   CreateLabel("SMC_Pro_Signal", 6, 18, signalText, signalColor);

   string detailText = "BOS:" + IntegerToString(bosCount) + " CHoCH:" + IntegerToString(chochCount) +
                       " (Buy:" + IntegerToString(buyCount) + " Sell:" + IntegerToString(sellCount) + ")";
   CreateLabel("SMC_Pro_Detail", 6, 38, detailText, clrYellow);

   string swingText = "Swings H:" + IntegerToString(ArraySize(swingHighPrices)) +
                      " L:" + IntegerToString(ArraySize(swingLowPrices)) +
                      " | Trend: " + (currentTrend ? "Bullish" : "Bearish");
   CreateLabel("SMC_Pro_Swings", 6, 58, swingText, clrGray);
}

//+------------------------------------------------------------------+
//| Create label                                                     |
//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, string text, color clr)
{
   if(ObjectFind(name) < 0)
      ObjectCreate(name, OBJ_LABEL, 0, 0, 0);

   ObjectSet(name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSet(name, OBJPROP_XDISTANCE, x);
   ObjectSet(name, OBJPROP_YDISTANCE, y);
   ObjectSetText(name, text, FontSize, "Arial Bold", clr);
}

//+------------------------------------------------------------------+
//| Remove swing high                                                |
//+------------------------------------------------------------------+
void RemoveSwingHigh(int index)
{
   int size = ArraySize(swingHighPrices);
   if(index < 0 || index >= size) return;

   for(int i = index; i < size - 1; i++)
   {
      swingHighPrices[i] = swingHighPrices[i + 1];
      swingHighBars[i] = swingHighBars[i + 1];
      swingHighTimes[i] = swingHighTimes[i + 1];
   }

   ArrayResize(swingHighPrices, size - 1);
   ArrayResize(swingHighBars, size - 1);
   ArrayResize(swingHighTimes, size - 1);
}

//+------------------------------------------------------------------+
//| Remove swing low                                                 |
//+------------------------------------------------------------------+
void RemoveSwingLow(int index)
{
   int size = ArraySize(swingLowPrices);
   if(index < 0 || index >= size) return;

   for(int i = index; i < size - 1; i++)
   {
      swingLowPrices[i] = swingLowPrices[i + 1];
      swingLowBars[i] = swingLowBars[i + 1];
      swingLowTimes[i] = swingLowTimes[i + 1];
   }

   ArrayResize(swingLowPrices, size - 1);
   ArrayResize(swingLowBars, size - 1);
   ArrayResize(swingLowTimes, size - 1);
}

//+------------------------------------------------------------------+
//| Deinitialize                                                     |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   for(int i = ObjectsTotal() - 1; i >= 0; i--)
   {
      string name = ObjectName(i);
      if(StringFind(name, "SMC_Pro_") >= 0)
         ObjectDelete(name);
   }
}
