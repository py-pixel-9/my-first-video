//+------------------------------------------------------------------+
//|                                          SMC_Breakout_Levels.mq4 |
//|                      Breakout Level Indicator for Limit Orders   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property link      ""
#property version   "1.00"
#property strict
#property indicator_chart_window

//--- Input Parameters
input int SwingSize = 50;                          // 스윙 크기 (좌우 확인 캔들 수)
input int MaxLevelsToShow = 3;                     // 최대 표시 레벨 수
input double MinimumBreakDistance = 20.0;          // 최소 돌파 거리 (pips)
input int CandlesBeforeExpiry = 5;                 // 레벨 만료 캔들 수
input bool ShowBullishLevels = true;               // 상승 돌파 레벨 표시
input bool ShowBearishLevels = true;               // 하락 돌파 레벨 표시
input color BullishLevelColor = clrLime;           // 상승 레벨 색상
input color BearishLevelColor = clrRed;            // 하락 레벨 색상
input int LineWidth = 2;                           // 선 두께
input bool ShowLabels = true;                      // 라벨 표시
input int FontSize = 10;                           // 폰트 크기
input bool ShowDebugPanel = true;                  // 디버그 패널 표시

//--- Global Variables
struct BreakLevel {
   double price;
   int createdBar;
   bool isBullish;
   bool active;
   int lineID;
};

BreakLevel activeLevels[];
double swingHighs[];
int swingHighBars[];
double swingLows[];
int swingLowBars[];
double pointSize;
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorShortName("SMC Breakout Levels");

   // Calculate point size for pips
   pointSize = Point;
   if(Digits == 3 || Digits == 5) pointSize = Point * 10;

   ArrayResize(activeLevels, 0);
   ArrayResize(swingHighs, 0);
   ArrayResize(swingHighBars, 0);
   ArrayResize(swingLows, 0);
   ArrayResize(swingLowBars, 0);

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
   // Check for new bar
   bool newBar = false;
   if(lastBarTime != Time[0])
   {
      lastBarTime = Time[0];
      newBar = true;
   }

   // Find swing points
   FindSwingPoints();

   // Update active levels
   UpdateActiveLevels();

   // Create new potential breakout levels
   if(newBar)
   {
      CreateBreakoutLevels();
   }

   // Draw levels on chart
   DrawLevels();

   // Draw debug panel
   if(ShowDebugPanel)
      DrawDebugPanel();

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Find swing high and low points                                   |
//+------------------------------------------------------------------+
void FindSwingPoints()
{
   ArrayResize(swingHighs, 0);
   ArrayResize(swingHighBars, 0);
   ArrayResize(swingLows, 0);
   ArrayResize(swingLowBars, 0);

   // Scan for swing points
   for(int i = SwingSize; i < Bars - SwingSize; i++)
   {
      // Check for swing high
      bool isSwingHigh = true;
      for(int j = 1; j <= SwingSize; j++)
      {
         if(High[i] <= High[i+j] || High[i] <= High[i-j])
         {
            isSwingHigh = false;
            break;
         }
      }

      if(isSwingHigh)
      {
         int size = ArraySize(swingHighs);
         ArrayResize(swingHighs, size + 1);
         ArrayResize(swingHighBars, size + 1);
         swingHighs[size] = High[i];
         swingHighBars[size] = i;
      }

      // Check for swing low
      bool isSwingLow = true;
      for(int j = 1; j <= SwingSize; j++)
      {
         if(Low[i] >= Low[i+j] || Low[i] >= Low[i-j])
         {
            isSwingLow = false;
            break;
         }
      }

      if(isSwingLow)
      {
         int size = ArraySize(swingLows);
         ArrayResize(swingLows, size + 1);
         ArrayResize(swingLowBars, size + 1);
         swingLows[size] = Low[i];
         swingLowBars[size] = i;
      }
   }
}

//+------------------------------------------------------------------+
//| Create potential breakout levels                                 |
//+------------------------------------------------------------------+
void CreateBreakoutLevels()
{
   double minBreakDist = MinimumBreakDistance * pointSize;

   // Check bullish breakout levels (swing highs)
   if(ShowBullishLevels)
   {
      for(int i = 0; i < MathMin(5, ArraySize(swingHighs)); i++)
      {
         double level = swingHighs[i];
         int levelBar = swingHighBars[i];

         // Check if price is approaching this level
         double distanceToLevel = level - Close[0];

         // If price is within reasonable distance and below the level
         if(distanceToLevel > 0 && distanceToLevel < (100 * pointSize))
         {
            // Check if this level already exists
            if(!LevelExists(level, true))
            {
               // Check if closer than existing levels
               if(ShouldCreateLevel(level, true))
               {
                  AddLevel(level, levelBar, true);
               }
            }
         }
      }
   }

   // Check bearish breakout levels (swing lows)
   if(ShowBearishLevels)
   {
      for(int i = 0; i < MathMin(5, ArraySize(swingLows)); i++)
      {
         double level = swingLows[i];
         int levelBar = swingLowBars[i];

         // Check if price is approaching this level
         double distanceToLevel = Close[0] - level;

         // If price is within reasonable distance and above the level
         if(distanceToLevel > 0 && distanceToLevel < (100 * pointSize))
         {
            // Check if this level already exists
            if(!LevelExists(level, false))
            {
               // Check if closer than existing levels
               if(ShouldCreateLevel(level, false))
               {
                  AddLevel(level, levelBar, false);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if level already exists                                    |
//+------------------------------------------------------------------+
bool LevelExists(double price, bool isBullish)
{
   for(int i = 0; i < ArraySize(activeLevels); i++)
   {
      if(activeLevels[i].active &&
         activeLevels[i].isBullish == isBullish &&
         MathAbs(activeLevels[i].price - price) < 10 * pointSize)
      {
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check if should create new level                                 |
//+------------------------------------------------------------------+
bool ShouldCreateLevel(double price, bool isBullish)
{
   // Count active levels of same type
   int count = 0;
   double farthestDistance = 0;
   int farthestIndex = -1;

   for(int i = 0; i < ArraySize(activeLevels); i++)
   {
      if(activeLevels[i].active && activeLevels[i].isBullish == isBullish)
      {
         count++;

         double distance;
         if(isBullish)
            distance = MathAbs(Close[0] - activeLevels[i].price);
         else
            distance = MathAbs(activeLevels[i].price - Close[0]);

         if(distance > farthestDistance)
         {
            farthestDistance = distance;
            farthestIndex = i;
         }
      }
   }

   // If max levels reached, check if new level is closer
   if(count >= MaxLevelsToShow)
   {
      double newDistance;
      if(isBullish)
         newDistance = price - Close[0];
      else
         newDistance = Close[0] - price;

      if(newDistance < farthestDistance && farthestIndex >= 0)
      {
         // Remove farthest level
         RemoveLevel(farthestIndex);
         return true;
      }
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Add new level                                                    |
//+------------------------------------------------------------------+
void AddLevel(double price, int barIndex, bool isBullish)
{
   int size = ArraySize(activeLevels);
   ArrayResize(activeLevels, size + 1);

   activeLevels[size].price = price;
   activeLevels[size].createdBar = Bars - barIndex;
   activeLevels[size].isBullish = isBullish;
   activeLevels[size].active = true;
   activeLevels[size].lineID = size;
}

//+------------------------------------------------------------------+
//| Remove level                                                     |
//+------------------------------------------------------------------+
void RemoveLevel(int index)
{
   if(index < 0 || index >= ArraySize(activeLevels)) return;

   activeLevels[index].active = false;

   // Delete line and label
   string lineName = "SMC_Level_" + IntegerToString(activeLevels[index].lineID);
   ObjectDelete(lineName);
   ObjectDelete(lineName + "_Label");
}

//+------------------------------------------------------------------+
//| Update active levels                                             |
//+------------------------------------------------------------------+
void UpdateActiveLevels()
{
   for(int i = ArraySize(activeLevels) - 1; i >= 0; i--)
   {
      if(!activeLevels[i].active) continue;

      // Check if level was hit
      if(activeLevels[i].isBullish)
      {
         if(Close[1] >= activeLevels[i].price || High[1] >= activeLevels[i].price)
         {
            // Level hit - convert to solid line or remove
            RemoveLevel(i);
            continue;
         }
      }
      else
      {
         if(Close[1] <= activeLevels[i].price || Low[1] <= activeLevels[i].price)
         {
            // Level hit - convert to solid line or remove
            RemoveLevel(i);
            continue;
         }
      }

      // Check if level expired (price moved away)
      int barsActive = Bars - activeLevels[i].createdBar;
      if(barsActive > CandlesBeforeExpiry)
      {
         double currentDistance;
         if(activeLevels[i].isBullish)
            currentDistance = activeLevels[i].price - Close[0];
         else
            currentDistance = Close[0] - activeLevels[i].price;

         // If price moved away significantly, remove level
         if(currentDistance < 0 || currentDistance > 200 * pointSize)
         {
            RemoveLevel(i);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Draw levels on chart                                             |
//+------------------------------------------------------------------+
void DrawLevels()
{
   for(int i = 0; i < ArraySize(activeLevels); i++)
   {
      if(!activeLevels[i].active) continue;

      string lineName = "SMC_Level_" + IntegerToString(activeLevels[i].lineID);
      color lineColor = activeLevels[i].isBullish ? BullishLevelColor : BearishLevelColor;

      // Draw dotted line
      if(ObjectFind(lineName) < 0)
      {
         ObjectCreate(lineName, OBJ_HLINE, 0, 0, activeLevels[i].price);
      }

      ObjectSet(lineName, OBJPROP_COLOR, lineColor);
      ObjectSet(lineName, OBJPROP_STYLE, STYLE_DOT);
      ObjectSet(lineName, OBJPROP_WIDTH, LineWidth);
      ObjectSet(lineName, OBJPROP_BACK, false);

      // Draw label
      if(ShowLabels)
      {
         string labelName = lineName + "_Label";
         if(ObjectFind(labelName) < 0)
         {
            ObjectCreate(labelName, OBJ_TEXT, 0, Time[0], activeLevels[i].price);
         }

         string labelText = activeLevels[i].isBullish ? "  LONG LIMIT" : "  SHORT LIMIT";
         ObjectSetText(labelName, labelText, FontSize, "Arial Bold", lineColor);
         ObjectSet(labelName, OBJPROP_TIME1, Time[0]);
         ObjectSet(labelName, OBJPROP_PRICE1, activeLevels[i].price);
      }
   }
}

//+------------------------------------------------------------------+
//| Draw debug panel                                                 |
//+------------------------------------------------------------------+
void DrawDebugPanel()
{
   int bullishCount = 0, bearishCount = 0;

   for(int i = 0; i < ArraySize(activeLevels); i++)
   {
      if(activeLevels[i].active)
      {
         if(activeLevels[i].isBullish) bullishCount++;
         else bearishCount++;
      }
   }

   string debugText = "Breakout Levels | Long: " + IntegerToString(bullishCount) +
                      " Short: " + IntegerToString(bearishCount);
   CreateLabel("SMC_Debug_Panel", 10, 20, debugText, clrYellow);

   string swingText = "Swings: H:" + IntegerToString(ArraySize(swingHighs)) +
                      " L:" + IntegerToString(ArraySize(swingLows)) +
                      " | Size: " + IntegerToString(SwingSize);
   CreateLabel("SMC_Debug_Swings", 10, 40, swingText, clrGray);
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
//| Deinitialize                                                     |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Delete all objects
   for(int i = ObjectsTotal() - 1; i >= 0; i--)
   {
      string name = ObjectName(i);
      if(StringFind(name, "SMC_") >= 0)
         ObjectDelete(name);
   }
}
