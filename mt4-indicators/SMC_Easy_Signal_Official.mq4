//+------------------------------------------------------------------+
//|                                       SMC_Easy_Signal_Official.mq4|
//|                                  BOS/CHoCH Structure Indicator    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property link      ""
#property version   "1.00"
#property strict
#property indicator_chart_window

// Input parameters
input int MarketStructureTimeHorizon = 25;           // Market Structure Time-Horizon
input string BOSConfirmationType = "CandleClose";    // BOS Confirmation Type
input bool ShowCHoCHLabels = true;                   // Show CHoCH labels
input int HowManyLatestZones = 1;                    // How many latest zones to keep
input int ArrowSize = 3;                             // Arrow size
input color BullishColor = clrAqua;                  // Bullish Color (Buy Signal)
input color BearishColor = clrMagenta;               // Bearish Color (Sell Signal)
input bool ShowShadedTPRectangles = false;           // Shaded TP rectangles
input bool ShowDashedLines = true;                   // Dashed TP1/TP2/TP3 lines
input bool ShowBOSCHoCHLines = true;                 // BOS/CHoCH horizontal lines
input bool ExtendRecentZones = true;                 // Extend most recent zones to current bar
input bool PCPopupAlert = true;                      // PC Pop-up/Sound alert
input bool PushNotification = false;                 // Push Notification (Phone)
input bool EmailAlert = false;                       // Email Alert
input bool ShowPanelAtTopLeft = true;                // Show panel at top-left
input int XOffset = 6;                               // X offset (px)
input int YOffset = 18;                              // Y offset (px)
input int FontSize = 12;                             // Font size
input int ExtraSpacing = 10;                         // Extra spacing between lines (px)

// Global arrays for swing points
double swingHighPrices[];
int swingHighBars[];
double swingLowPrices[];
int swingLowBars[];

// Temporary structure tracking arrays
double tempPrices[];
int tempBars[];
string tempTypes[];
bool tempIsBuy[];
bool tempConfirmed[];

// Global variables
bool isBullish = true;
double lastHighPrice = 0;
double lastLowPrice = 0;
datetime lastAlertTime = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorShortName("SMC Easy Signal");

   ArrayResize(swingHighPrices, 0);
   ArrayResize(swingHighBars, 0);
   ArrayResize(swingLowPrices, 0);
   ArrayResize(swingLowBars, 0);

   ArrayResize(tempPrices, 0);
   ArrayResize(tempBars, 0);
   ArrayResize(tempTypes, 0);
   ArrayResize(tempIsBuy, 0);
   ArrayResize(tempConfirmed, 0);

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
   FindSwingPoints(MarketStructureTimeHorizon);

   // Detect BOS and CHoCH
   DetectStructureBreaks();

   // Draw structures
   DrawStructures();

   // Draw panel
   if(ShowPanelAtTopLeft)
      DrawPanel();

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Find swing high and low points                                   |
//+------------------------------------------------------------------+
void FindSwingPoints(int lookback)
{
   ArrayResize(swingHighPrices, 0);
   ArrayResize(swingHighBars, 0);
   ArrayResize(swingLowPrices, 0);
   ArrayResize(swingLowBars, 0);

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
         swingHighPrices[size] = High[i];
         swingHighBars[size] = i;
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
         swingLowPrices[size] = Low[i];
         swingLowBars[size] = i;
      }
   }
}

//+------------------------------------------------------------------+
//| Detect BOS and CHoCH                                             |
//+------------------------------------------------------------------+
void DetectStructureBreaks()
{
   // Clean up invalidated structures (only for unconfirmed)
   for(int i = ArraySize(tempPrices) - 1; i >= 0; i--)
   {
      if(!tempConfirmed[i])
      {
         if(tempIsBuy[i])
         {
            // Check if price fell back below the level
            if(Close[0] < tempPrices[i])
            {
               RemoveStructure(i);
               continue;
            }
            // Check for confirmation (candle close above level)
            if(BOSConfirmationType == "CandleClose" && Close[1] > tempPrices[i])
            {
               tempConfirmed[i] = true;
            }
         }
         else
         {
            // Check if price rose back above the level
            if(Close[0] > tempPrices[i])
            {
               RemoveStructure(i);
               continue;
            }
            // Check for confirmation (candle close below level)
            if(BOSConfirmationType == "CandleClose" && Close[1] < tempPrices[i])
            {
               tempConfirmed[i] = true;
            }
         }
      }
   }

   int highSize = ArraySize(swingHighPrices);
   int lowSize = ArraySize(swingLowPrices);

   if(highSize < 2 || lowSize < 2) return;

   // Scan through recent history for BOS/CHoCH
   int barsToScan = MathMin(500, Bars - MarketStructureTimeHorizon);

   for(int bar = 1; bar < barsToScan; bar++)
   {
      // Find which swing high/low this bar might break
      for(int h = 0; h < highSize - 1; h++)
      {
         int swingBar = swingHighBars[h];
         if(swingBar >= bar) continue; // Swing must be in the past

         double swingPrice = swingHighPrices[h];

         // Check if this bar broke the swing high
         if(High[bar] > swingPrice && High[bar+1] <= swingPrice)
         {
            // Determine if BOS or CHoCH
            bool wasBearish = (h > 0 && swingLowPrices[0] < swingLowPrices[1]);
            string signalType = wasBearish ? "CHoCH" : "BOS";

            if(!wasBearish || ShowCHoCHLabels)
            {
               if(!StructureExistsAt(swingPrice, true, bar))
               {
                  AddStructure(swingPrice, bar, signalType, true, true);
               }
            }
         }
      }

      // Check for bearish breaks
      for(int l = 0; l < lowSize - 1; l++)
      {
         int swingBar = swingLowBars[l];
         if(swingBar >= bar) continue;

         double swingPrice = swingLowPrices[l];

         // Check if this bar broke the swing low
         if(Low[bar] < swingPrice && Low[bar+1] >= swingPrice)
         {
            // Determine if BOS or CHoCH
            bool wasBullish = (l > 0 && swingHighPrices[0] > swingHighPrices[1]);
            string signalType = wasBullish ? "CHoCH" : "BOS";

            if(!wasBullish || ShowCHoCHLabels)
            {
               if(!StructureExistsAt(swingPrice, false, bar))
               {
                  AddStructure(swingPrice, bar, signalType, false, true);
               }
            }
         }
      }
   }

   // Check current bar for new breaks (real-time detection)
   if(isBullish)
   {
      double prevHigh = swingHighPrices[highSize-2];
      if(High[0] > prevHigh || High[1] > prevHigh)
      {
         if(!StructureExists(prevHigh, true))
         {
            AddStructure(prevHigh, 0, "BOS", true, false);
            SendAlert("BOS Buy Signal");
         }
      }
   }
   else
   {
      double prevHigh = swingHighPrices[highSize-1];
      if((High[0] > prevHigh || High[1] > prevHigh) && ShowCHoCHLabels)
      {
         if(!StructureExists(prevHigh, true))
         {
            AddStructure(prevHigh, 0, "CHoCH", true, false);
            isBullish = true;
            SendAlert("CHoCH Buy Signal");
         }
      }
   }

   if(!isBullish)
   {
      double prevLow = swingLowPrices[lowSize-2];
      if(Low[0] < prevLow || Low[1] < prevLow)
      {
         if(!StructureExists(prevLow, false))
         {
            AddStructure(prevLow, 0, "BOS", false, false);
            SendAlert("BOS Sell Signal");
         }
      }
   }
   else
   {
      double prevLow = swingLowPrices[lowSize-1];
      if((Low[0] < prevLow || Low[1] < prevLow) && ShowCHoCHLabels)
      {
         if(!StructureExists(prevLow, false))
         {
            AddStructure(prevLow, 0, "CHoCH", false, false);
            isBullish = false;
            SendAlert("CHoCH Sell Signal");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Add structure to arrays                                          |
//+------------------------------------------------------------------+
void AddStructure(double price, int bar, string type, bool isBuy, bool confirmed)
{
   int size = ArraySize(tempPrices);
   ArrayResize(tempPrices, size + 1);
   ArrayResize(tempBars, size + 1);
   ArrayResize(tempTypes, size + 1);
   ArrayResize(tempIsBuy, size + 1);
   ArrayResize(tempConfirmed, size + 1);

   tempPrices[size] = price;
   tempBars[size] = bar;
   tempTypes[size] = type;
   tempIsBuy[size] = isBuy;
   tempConfirmed[size] = confirmed;
}

//+------------------------------------------------------------------+
//| Remove structure from arrays                                     |
//+------------------------------------------------------------------+
void RemoveStructure(int index)
{
   int size = ArraySize(tempPrices);
   if(index < 0 || index >= size) return;

   // Delete associated objects
   string objName = "SMC_" + tempTypes[index] + "_" + IntegerToString(index);
   ObjectDelete(objName + "_Arrow");
   ObjectDelete(objName + "_Label");
   ObjectDelete(objName + "_Line");

   // Shift arrays
   for(int i = index; i < size - 1; i++)
   {
      tempPrices[i] = tempPrices[i + 1];
      tempBars[i] = tempBars[i + 1];
      tempTypes[i] = tempTypes[i + 1];
      tempIsBuy[i] = tempIsBuy[i + 1];
      tempConfirmed[i] = tempConfirmed[i + 1];
   }

   ArrayResize(tempPrices, size - 1);
   ArrayResize(tempBars, size - 1);
   ArrayResize(tempTypes, size - 1);
   ArrayResize(tempIsBuy, size - 1);
   ArrayResize(tempConfirmed, size - 1);
}

//+------------------------------------------------------------------+
//| Check if structure already exists                                |
//+------------------------------------------------------------------+
bool StructureExists(double price, bool isBuy)
{
   for(int i = 0; i < ArraySize(tempPrices); i++)
   {
      if(MathAbs(tempPrices[i] - price) < Point * 10 && tempIsBuy[i] == isBuy)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check if structure exists at specific bar                        |
//+------------------------------------------------------------------+
bool StructureExistsAt(double price, bool isBuy, int bar)
{
   for(int i = 0; i < ArraySize(tempPrices); i++)
   {
      if(MathAbs(tempPrices[i] - price) < Point * 10 &&
         tempIsBuy[i] == isBuy &&
         MathAbs(tempBars[i] - bar) < 5)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Draw structures on chart                                         |
//+------------------------------------------------------------------+
void DrawStructures()
{
   // Delete old objects first
   DeleteOldObjects();

   for(int i = 0; i < ArraySize(tempPrices); i++)
   {
      if(!tempConfirmed[i]) continue;

      string objName = "SMC_" + tempTypes[i] + "_" + IntegerToString(i) + "_" + IntegerToString(tempBars[i]);
      datetime objTime = Time[tempBars[i]];
      color objColor = tempIsBuy[i] ? BullishColor : BearishColor;

      // Calculate label position (above for buy, below for sell)
      double labelPrice = tempIsBuy[i] ? tempPrices[i] + (10 * Point) : tempPrices[i] - (10 * Point);

      // Draw arrow with larger size
      if(ObjectFind(objName + "_Arrow") < 0)
      {
         ObjectCreate(objName + "_Arrow", OBJ_ARROW, 0, objTime, tempPrices[i]);
         ObjectSet(objName + "_Arrow", OBJPROP_ARROWCODE, tempIsBuy[i] ? 233 : 234);
         ObjectSet(objName + "_Arrow", OBJPROP_COLOR, objColor);
         ObjectSet(objName + "_Arrow", OBJPROP_WIDTH, ArrowSize + 1);
         ObjectSet(objName + "_Arrow", OBJPROP_BACK, false);
      }

      // Draw text label with better visibility
      if(ObjectFind(objName + "_Label") < 0)
      {
         ObjectCreate(objName + "_Label", OBJ_TEXT, 0, objTime, labelPrice);
         ObjectSetText(objName + "_Label", "  " + tempTypes[i] + "  ", FontSize + 2, "Arial Black", objColor);
         ObjectSet(objName + "_Label", OBJPROP_BACK, false);
      }

      // Draw horizontal line with better visibility
      if(ShowBOSCHoCHLines)
      {
         if(ObjectFind(objName + "_Line") < 0)
         {
            ObjectCreate(objName + "_Line", OBJ_TREND, 0, Time[tempBars[i]], tempPrices[i], Time[0], tempPrices[i]);
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
   int buyCount = 0;
   int sellCount = 0;
   int totalStructures = 0;

   for(int i = 0; i < ArraySize(tempPrices); i++)
   {
      if(tempConfirmed[i])
      {
         totalStructures++;
         if(tempIsBuy[i]) buyCount++;
         else sellCount++;
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

   CreateLabel("SMC_Panel_Signal", XOffset, YOffset, signalText, signalColor);

   // Debug info
   string debugText = "BOS/CHoCH: " + IntegerToString(totalStructures) +
                      " (Buy:" + IntegerToString(buyCount) +
                      " Sell:" + IntegerToString(sellCount) + ")";
   CreateLabel("SMC_Panel_Debug", XOffset, YOffset + FontSize + ExtraSpacing, debugText, clrYellow);

   // Swing points info
   string swingText = "Swings H:" + IntegerToString(ArraySize(swingHighPrices)) +
                      " L:" + IntegerToString(ArraySize(swingLowPrices));
   CreateLabel("SMC_Panel_Swings", XOffset, YOffset + (FontSize + ExtraSpacing) * 2, swingText, clrGray);
}

//+------------------------------------------------------------------+
//| Create text label                                                |
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
//| Delete old objects                                               |
//+------------------------------------------------------------------+
void DeleteOldObjects()
{
   int confirmed = 0;
   for(int i = ArraySize(tempPrices) - 1; i >= 0; i--)
   {
      if(tempConfirmed[i])
      {
         confirmed++;
         if(confirmed > HowManyLatestZones)
         {
            string objName = "SMC_" + tempTypes[i] + "_" + IntegerToString(i);
            ObjectDelete(objName + "_Arrow");
            ObjectDelete(objName + "_Label");
            ObjectDelete(objName + "_Line");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Send alert                                                       |
//+------------------------------------------------------------------+
void SendAlert(string message)
{
   if(PCPopupAlert)
   {
      if(TimeCurrent() - lastAlertTime > 5) // Prevent duplicate alerts
      {
         Alert(message + " at " + Symbol() + " - " + IntegerToString(Period()));
         lastAlertTime = TimeCurrent();
      }
   }

   if(PushNotification)
      SendNotification(message + " at " + Symbol());

   if(EmailAlert)
      SendMail("SMC Signal", message + " at " + Symbol() + " - " + IntegerToString(Period()));
}

//+------------------------------------------------------------------+
//| Deinitialize                                                     |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   for(int i = ObjectsTotal() - 1; i >= 0; i--)
   {
      string name = ObjectName(i);
      if(StringFind(name, "SMC_") >= 0)
         ObjectDelete(name);
   }
}
