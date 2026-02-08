//+------------------------------------------------------------------+
//|                                              SMC_Breakout_EA.mq4 |
//|              SMC Breakout Level Auto Limit Order Trading System   |
//|                                                                  |
//|  - 스윙 하이/로우 감지 후 지정가(Limit) 주문 자동 배치           |
//|  - 스프레드/슬리피지 회피를 위한 사전 지정가 전략                 |
//|  - 트레일링 스탑 지원                                            |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property link      ""
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
//=== 시그널 파라미터 ===
input int       SwingSize           = 5;        // 스윙 크기 (좌우 확인 캔들 수)
input int       MaxLevelsPerSide    = 3;        // 방향별 최대 주문 수
input int       CandlesBeforeExpiry = 50;       // 레벨 만료 캔들 수
input double    MinLevelDistance    = 10.0;     // 최소 레벨 간격 (pips)
input int       ScanRange           = 500;      // 스캔 범위 (캔들 수)

//=== 주문 파라미터 ===
input double    LotSize             = 0.01;     // 고정 랏 사이즈
input int       StopLossPoints      = 300;      // 손절 (포인트)
input int       TakeProfitPoints    = 500;      // 익절 (포인트)
input int       MagicNumber         = 20260208; // 매직 넘버

//=== 트레일링 스탑 ===
input bool      UseTrailing         = true;     // 트레일링 스탑 사용
input int       TrailingStartPoints = 50;       // 트레일링 시작 (포인트, 수익)
input int       TrailingStepPoints  = 50;       // 트레일링 스텝 (포인트)

//=== 안전 필터 ===
input double    MaxSpreadPips       = 5.0;      // 최대 스프레드 (pips)
input bool      UseTradingHours     = false;    // 거래시간 필터 사용
input int       TradingStartHour    = 8;        // 거래 시작 시간 (서버시간)
input int       TradingEndHour      = 22;       // 거래 종료 시간 (서버시간)
input bool      DeleteOnFriday      = false;    // 금요일 대기주문 삭제
input int       FridayCloseHour     = 20;       // 금요일 삭제 시간

//=== 표시 ===
input bool      ShowPanel           = true;     // 상태 패널 표시
input bool      ShowLevelLines      = true;     // 레벨 라인 표시
input color     BullishColor        = clrAqua;  // 롱 레벨 색상
input color     BearishColor        = clrOrangeRed; // 숏 레벨 색상
input int       FontSize            = 9;        // 폰트 크기

//+------------------------------------------------------------------+
//| Data Structures                                                  |
//+------------------------------------------------------------------+
struct EALevel {
   double   price;         // 레벨 가격
   int      barIndex;      // 생성 바 인덱스
   bool     isBullish;     // true=BuyLimit, false=SellLimit
   bool     active;        // 활성 여부
   int      ticket;        // 주문 티켓 (-1=미배치)
   datetime createTime;    // 생성 시간
};

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
EALevel    g_levels[];
double     g_pointSize;
datetime   g_lastBarTime = 0;
int        g_levelCounter = 0;

// 통계
int        g_totalBuyLimits = 0;
int        g_totalSellLimits = 0;
int        g_totalBuyTrades = 0;
int        g_totalSellTrades = 0;
double     g_sessionPL = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // 포인트 사이즈 계산
   g_pointSize = Point;
   if(Digits == 3 || Digits == 5) g_pointSize = Point * 10;

   // 입력값 검증
   if(LotSize <= 0)
   {
      Alert("SMC EA: 랏 사이즈가 0 이하입니다!");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(StopLossPoints <= 0 || TakeProfitPoints <= 0)
   {
      Alert("SMC EA: SL/TP가 0 이하입니다!");
      return(INIT_PARAMETERS_INCORRECT);
   }

   // 초기화
   ArrayResize(g_levels, 0);
   g_levelCounter = 0;

   // 기존 주문 복원 (EA 재시작 대비)
   ScanExistingOrders();

   Print("SMC Breakout EA v1.0 초기화 완료");
   Print("설정: Lot=", LotSize, " SL=", StopLossPoints, "pt TP=", TakeProfitPoints, "pt");
   Print("트레일링: ", UseTrailing ? "ON" : "OFF",
         " Start=", TrailingStartPoints, "pt Step=", TrailingStepPoints, "pt");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   CleanupObjects();
   Print("SMC Breakout EA 종료. 사유: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. 새 바 감지
   bool newBar = false;
   if(g_lastBarTime != Time[0])
   {
      g_lastBarTime = Time[0];
      newBar = true;
   }

   // 2. 새 바에서만 레벨 스캔 및 생성
   if(newBar)
   {
      // 스윙 포인트에서 새 레벨 체크
      CheckNewLevels();

      // 만료된 레벨 정리
      UpdateActiveLevels();

      // 주문 동기화 (새 레벨에 주문 배치)
      SyncOrdersWithLevels();
   }

   // 3. 매 틱마다 트레일링 스탑 관리
   if(UseTrailing)
      ManageTrailingStop();

   // 4. 주문 상태 확인 (체결/삭제 감지)
   CheckOrderStatus();

   // 5. 패널 업데이트
   if(ShowPanel) DrawPanel();
   if(ShowLevelLines) DrawLevelLines();
}

//+------------------------------------------------------------------+
//| 스윙 하이 판별                                                    |
//+------------------------------------------------------------------+
bool IsSwingHigh(int bar)
{
   if(bar - SwingSize < 0 || bar + SwingSize >= Bars) return false;

   for(int j = 1; j <= SwingSize; j++)
   {
      if(High[bar] <= High[bar + j] || High[bar] <= High[bar - j])
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| 스윙 로우 판별                                                    |
//+------------------------------------------------------------------+
bool IsSwingLow(int bar)
{
   if(bar - SwingSize < 0 || bar + SwingSize >= Bars) return false;

   for(int j = 1; j <= SwingSize; j++)
   {
      if(Low[bar] >= Low[bar + j] || Low[bar] >= Low[bar - j])
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| 새 레벨 체크 (새 바 마다)                                         |
//+------------------------------------------------------------------+
void CheckNewLevels()
{
   // SwingSize 위치의 캔들이 스윙인지 확인
   // (오른쪽 캔들이 SwingSize개 확정된 시점)
   int checkBar = SwingSize;

   // 상승 레벨 (스윙 하이 → 가격이 다시 올라오면 BuyLimit)
   if(IsSwingHigh(checkBar))
   {
      double level = High[checkBar];

      // 현재 가격보다 위에 있어야 BuyLimit 가능
      if(level > Ask)
      {
         if(!LevelExists(level, true) && CountActiveLevels(true) < MaxLevelsPerSide)
         {
            AddLevel(level, checkBar, true);
            Print("새 BUY LIMIT 레벨: ", DoubleToStr(level, Digits));
         }
      }
   }

   // 하락 레벨 (스윙 로우 → 가격이 다시 내려오면 SellLimit)
   if(IsSwingLow(checkBar))
   {
      double level = Low[checkBar];

      // 현재 가격보다 아래에 있어야 SellLimit 가능
      if(level < Bid)
      {
         if(!LevelExists(level, false) && CountActiveLevels(false) < MaxLevelsPerSide)
         {
            AddLevel(level, checkBar, false);
            Print("새 SELL LIMIT 레벨: ", DoubleToStr(level, Digits));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 레벨 중복 체크                                                    |
//+------------------------------------------------------------------+
bool LevelExists(double price, bool isBullish)
{
   double minDist = MinLevelDistance * g_pointSize;

   for(int i = 0; i < ArraySize(g_levels); i++)
   {
      if(g_levels[i].active &&
         g_levels[i].isBullish == isBullish &&
         MathAbs(g_levels[i].price - price) < minDist)
      {
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| 활성 레벨 수 카운트                                               |
//+------------------------------------------------------------------+
int CountActiveLevels(bool isBullish)
{
   int count = 0;
   for(int i = 0; i < ArraySize(g_levels); i++)
   {
      if(g_levels[i].active && g_levels[i].isBullish == isBullish)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| 레벨 추가                                                        |
//+------------------------------------------------------------------+
void AddLevel(double price, int barIdx, bool isBullish)
{
   int size = ArraySize(g_levels);
   ArrayResize(g_levels, size + 1);

   g_levels[size].price      = NormalizeDouble(price, Digits);
   g_levels[size].barIndex   = barIdx;
   g_levels[size].isBullish  = isBullish;
   g_levels[size].active     = true;
   g_levels[size].ticket     = -1;  // 아직 주문 안 넣음
   g_levels[size].createTime = TimeCurrent();
}

//+------------------------------------------------------------------+
//| 활성 레벨 업데이트 (만료/무효화)                                   |
//+------------------------------------------------------------------+
void UpdateActiveLevels()
{
   for(int i = ArraySize(g_levels) - 1; i >= 0; i--)
   {
      if(!g_levels[i].active) continue;

      // 만료 체크: 생성 후 CandlesBeforeExpiry 캔들 경과
      if(g_levels[i].barIndex >= CandlesBeforeExpiry)
      {
         Print("레벨 만료: ", DoubleToStr(g_levels[i].price, Digits),
               g_levels[i].isBullish ? " (Buy)" : " (Sell)");
         RemoveLevel(i);
         continue;
      }

      // 바 인덱스 증가 (새 바가 생겼으므로)
      g_levels[i].barIndex++;

      // 가격이 레벨을 넘어갔으면 무효화
      if(g_levels[i].isBullish)
      {
         // BuyLimit인데 가격이 이미 위에 있으면 → 유지 (아직 내려올 수 있음)
         // BuyLimit인데 가격이 너무 아래로 멀어지면 → 무효화
         if(g_levels[i].price - Ask > 200 * g_pointSize)
         {
            Print("레벨 무효화 (너무 먼): ", DoubleToStr(g_levels[i].price, Digits));
            RemoveLevel(i);
         }
      }
      else
      {
         // SellLimit인데 가격이 너무 위로 멀어지면 → 무효화
         if(Bid - g_levels[i].price > 200 * g_pointSize)
         {
            Print("레벨 무효화 (너무 먼): ", DoubleToStr(g_levels[i].price, Digits));
            RemoveLevel(i);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 레벨 제거 + 대기주문 삭제                                         |
//+------------------------------------------------------------------+
void RemoveLevel(int index)
{
   if(index < 0 || index >= ArraySize(g_levels)) return;

   // 대기 주문이 있으면 삭제
   if(g_levels[index].ticket > 0)
   {
      DeletePendingOrder(g_levels[index].ticket);
   }

   g_levels[index].active = false;

   // 차트 오브젝트 삭제
   string baseName = "SMCEA_Lv_" + IntegerToString(index);
   ObjectDelete(baseName);
   ObjectDelete(baseName + "_lbl");
}

//+------------------------------------------------------------------+
//| 주문과 레벨 동기화                                                |
//+------------------------------------------------------------------+
void SyncOrdersWithLevels()
{
   // 안전 체크
   if(!IsTradingAllowed()) return;

   for(int i = 0; i < ArraySize(g_levels); i++)
   {
      if(!g_levels[i].active) continue;
      if(g_levels[i].ticket > 0) continue; // 이미 주문 있음

      // 스프레드 체크
      double currentSpread = MarketInfo(Symbol(), MODE_SPREAD) * Point / g_pointSize;
      if(currentSpread > MaxSpreadPips)
      {
         Print("스프레드 초과로 주문 보류: ", DoubleToStr(currentSpread, 1), " pips");
         continue;
      }

      // 거래시간 체크
      if(UseTradingHours && !IsWithinTradingHours()) continue;

      // 금요일 체크
      if(DeleteOnFriday && IsFridayClose())
      {
         RemoveLevel(i);
         continue;
      }

      // 주문 배치
      double price = g_levels[i].price;
      double sl, tp;

      if(g_levels[i].isBullish)
      {
         // BUY LIMIT: 현재가보다 아래에 배치 (가격이 내려와서 체결)
         sl = NormalizeDouble(price - StopLossPoints * Point, Digits);
         tp = NormalizeDouble(price + TakeProfitPoints * Point, Digits);

         // 가격이 현재 Ask보다 아래에 있어야 Buy Limit 가능
         if(price >= Ask)
         {
            // Ask보다 위면 주문 불가 → 다음 틱에서 재시도
            continue;
         }

         int ticket = PlaceBuyLimit(price, sl, tp);
         if(ticket > 0)
         {
            g_levels[i].ticket = ticket;
            Print("BUY LIMIT 배치 성공: #", ticket, " @ ", DoubleToStr(price, Digits),
                  " SL=", DoubleToStr(sl, Digits), " TP=", DoubleToStr(tp, Digits));
         }
      }
      else
      {
         // SELL LIMIT: 현재가보다 위에 배치 (가격이 올라와서 체결)
         sl = NormalizeDouble(price + StopLossPoints * Point, Digits);
         tp = NormalizeDouble(price - TakeProfitPoints * Point, Digits);

         // 가격이 현재 Bid보다 위에 있어야 Sell Limit 가능
         if(price <= Bid)
         {
            continue;
         }

         int ticket = PlaceSellLimit(price, sl, tp);
         if(ticket > 0)
         {
            g_levels[i].ticket = ticket;
            Print("SELL LIMIT 배치 성공: #", ticket, " @ ", DoubleToStr(price, Digits),
                  " SL=", DoubleToStr(sl, Digits), " TP=", DoubleToStr(tp, Digits));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Buy Limit 주문                                                   |
//+------------------------------------------------------------------+
int PlaceBuyLimit(double price, double sl, double tp)
{
   price = NormalizeDouble(price, Digits);
   sl = NormalizeDouble(sl, Digits);
   tp = NormalizeDouble(tp, Digits);

   // 스탑레벨 검증
   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   if(Ask - price < stopLevel)
   {
      Print("BUY LIMIT 거부: 스탑레벨 미달 (", DoubleToStr(Ask - price, Digits),
            " < ", DoubleToStr(stopLevel, Digits), ")");
      return -1;
   }

   string comment = "SMCEA_BL_" + DoubleToStr(price, Digits);

   int ticket = OrderSend(Symbol(), OP_BUYLIMIT, LotSize, price, 0, sl, tp,
                           comment, MagicNumber, 0, BullishColor);

   if(ticket < 0)
   {
      int err = GetLastError();
      Print("BUY LIMIT 실패: 에러 ", err, " - ", ErrorDescription(err));

      // 재시도 가능한 에러
      if(err == ERR_REQUOTE || err == ERR_BROKER_BUSY || err == ERR_TRADE_CONTEXT_BUSY)
      {
         Sleep(500);
         RefreshRates();
         ticket = OrderSend(Symbol(), OP_BUYLIMIT, LotSize, price, 0, sl, tp,
                            comment, MagicNumber, 0, BullishColor);
         if(ticket < 0)
            Print("BUY LIMIT 재시도 실패: 에러 ", GetLastError());
      }
   }

   return ticket;
}

//+------------------------------------------------------------------+
//| Sell Limit 주문                                                  |
//+------------------------------------------------------------------+
int PlaceSellLimit(double price, double sl, double tp)
{
   price = NormalizeDouble(price, Digits);
   sl = NormalizeDouble(sl, Digits);
   tp = NormalizeDouble(tp, Digits);

   // 스탑레벨 검증
   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   if(price - Bid < stopLevel)
   {
      Print("SELL LIMIT 거부: 스탑레벨 미달 (", DoubleToStr(price - Bid, Digits),
            " < ", DoubleToStr(stopLevel, Digits), ")");
      return -1;
   }

   string comment = "SMCEA_SL_" + DoubleToStr(price, Digits);

   int ticket = OrderSend(Symbol(), OP_SELLLIMIT, LotSize, price, 0, sl, tp,
                           comment, MagicNumber, 0, BearishColor);

   if(ticket < 0)
   {
      int err = GetLastError();
      Print("SELL LIMIT 실패: 에러 ", err, " - ", ErrorDescription(err));

      if(err == ERR_REQUOTE || err == ERR_BROKER_BUSY || err == ERR_TRADE_CONTEXT_BUSY)
      {
         Sleep(500);
         RefreshRates();
         ticket = OrderSend(Symbol(), OP_SELLLIMIT, LotSize, price, 0, sl, tp,
                            comment, MagicNumber, 0, BearishColor);
         if(ticket < 0)
            Print("SELL LIMIT 재시도 실패: 에러 ", GetLastError());
      }
   }

   return ticket;
}

//+------------------------------------------------------------------+
//| 대기주문 삭제                                                     |
//+------------------------------------------------------------------+
bool DeletePendingOrder(int ticket)
{
   if(ticket <= 0) return true;

   if(!OrderSelect(ticket, SELECT_BY_TICKET)) return true;

   // 이미 체결되었거나 닫힌 주문이면 삭제할 필요 없음
   if(OrderCloseTime() > 0) return true;
   if(OrderType() != OP_BUYLIMIT && OrderType() != OP_SELLLIMIT) return true;

   for(int retry = 0; retry < 3; retry++)
   {
      if(OrderDelete(ticket))
      {
         Print("대기주문 삭제 성공: #", ticket);
         return true;
      }

      int err = GetLastError();
      Print("대기주문 삭제 실패 (시도 ", retry + 1, "): #", ticket, " 에러=", err);

      if(err == ERR_TRADE_CONTEXT_BUSY)
         Sleep(500);
      else
         break;
   }

   return false;
}

//+------------------------------------------------------------------+
//| 주문 상태 확인 (체결/외부삭제 감지)                               |
//+------------------------------------------------------------------+
void CheckOrderStatus()
{
   for(int i = 0; i < ArraySize(g_levels); i++)
   {
      if(!g_levels[i].active) continue;
      if(g_levels[i].ticket <= 0) continue;

      if(!OrderSelect(g_levels[i].ticket, SELECT_BY_TICKET))
      {
         // 주문을 찾을 수 없음 → 외부 삭제
         Print("주문 소실: #", g_levels[i].ticket, " → 레벨 비활성화");
         g_levels[i].active = false;
         continue;
      }

      // 체결되었는지 확인
      if(OrderType() == OP_BUY || OrderType() == OP_SELL)
      {
         // 지정가가 체결됨 → 레벨 비활성화 (포지션은 SL/TP/트레일링이 관리)
         Print("주문 체결! #", g_levels[i].ticket, " @ ", DoubleToStr(OrderOpenPrice(), Digits),
               g_levels[i].isBullish ? " (BUY)" : " (SELL)");
         g_levels[i].active = false;
         continue;
      }

      // 삭제되었는지 확인
      if(OrderCloseTime() > 0)
      {
         Print("주문 삭제됨: #", g_levels[i].ticket);
         g_levels[i].active = false;
      }
   }
}

//+------------------------------------------------------------------+
//| 트레일링 스탑 관리                                                |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderMagicNumber() != MagicNumber) continue;

      // 포지션만 (대기주문 제외)
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;

      double openPrice = OrderOpenPrice();
      double currentSL = OrderStopLoss();
      double newSL;

      if(OrderType() == OP_BUY)
      {
         double profit = Bid - openPrice;

         // 트레일링 시작 조건
         if(profit < TrailingStartPoints * Point) continue;

         // 새 SL 계산: 현재가 - 트레일링스텝
         newSL = NormalizeDouble(Bid - TrailingStepPoints * Point, Digits);

         // 현재 SL보다 높아야 이동 (SL을 올리기만 함)
         if(newSL > currentSL + Point)
         {
            if(OrderModify(OrderTicket(), openPrice, newSL, OrderTakeProfit(), 0, BullishColor))
            {
               Print("트레일링 SL 이동 (BUY #", OrderTicket(), "): ",
                     DoubleToStr(currentSL, Digits), " → ", DoubleToStr(newSL, Digits));
            }
            else
            {
               Print("트레일링 수정 실패: 에러 ", GetLastError());
            }
         }
      }
      else if(OrderType() == OP_SELL)
      {
         double profit = openPrice - Ask;

         if(profit < TrailingStartPoints * Point) continue;

         // 새 SL 계산: 현재가 + 트레일링스텝
         newSL = NormalizeDouble(Ask + TrailingStepPoints * Point, Digits);

         // 현재 SL보다 낮아야 이동 (SL을 내리기만 함)
         if(currentSL == 0 || newSL < currentSL - Point)
         {
            if(OrderModify(OrderTicket(), openPrice, newSL, OrderTakeProfit(), 0, BearishColor))
            {
               Print("트레일링 SL 이동 (SELL #", OrderTicket(), "): ",
                     DoubleToStr(currentSL, Digits), " → ", DoubleToStr(newSL, Digits));
            }
            else
            {
               Print("트레일링 수정 실패: 에러 ", GetLastError());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 기존 주문 복원 (EA 재시작 시)                                     |
//+------------------------------------------------------------------+
void ScanExistingOrders()
{
   int restored = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderMagicNumber() != MagicNumber) continue;

      // 대기주문만 복원
      if(OrderType() == OP_BUYLIMIT || OrderType() == OP_SELLLIMIT)
      {
         int size = ArraySize(g_levels);
         ArrayResize(g_levels, size + 1);

         g_levels[size].price      = OrderOpenPrice();
         g_levels[size].barIndex   = 0;
         g_levels[size].isBullish  = (OrderType() == OP_BUYLIMIT);
         g_levels[size].active     = true;
         g_levels[size].ticket     = OrderTicket();
         g_levels[size].createTime = OrderOpenTime();

         restored++;
         Print("주문 복원: #", OrderTicket(), " @ ", DoubleToStr(OrderOpenPrice(), Digits),
               OrderType() == OP_BUYLIMIT ? " (BUY LIMIT)" : " (SELL LIMIT)");
      }
   }

   if(restored > 0)
      Print("총 ", restored, "개 대기주문 복원 완료");
}

//+------------------------------------------------------------------+
//| 거래 허용 확인                                                    |
//+------------------------------------------------------------------+
bool IsTradingAllowed()
{
   if(!IsTradeAllowed())
   {
      Print("거래 비허용 상태");
      return false;
   }
   if(!IsConnected())
   {
      Print("서버 연결 안됨");
      return false;
   }
   if(IsTradeContextBusy())
   {
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| 거래시간 체크                                                     |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
   int hour = TimeHour(TimeCurrent());

   if(TradingStartHour < TradingEndHour)
      return (hour >= TradingStartHour && hour < TradingEndHour);
   else // 야간 세션 (예: 22~6)
      return (hour >= TradingStartHour || hour < TradingEndHour);
}

//+------------------------------------------------------------------+
//| 금요일 마감 체크                                                  |
//+------------------------------------------------------------------+
bool IsFridayClose()
{
   return (TimeDayOfWeek(TimeCurrent()) == 5 &&
           TimeHour(TimeCurrent()) >= FridayCloseHour);
}

//+------------------------------------------------------------------+
//| 에러 설명                                                        |
//+------------------------------------------------------------------+
string ErrorDescription(int error)
{
   switch(error)
   {
      case 0:   return "No error";
      case 1:   return "No error but result unknown";
      case 2:   return "Common error";
      case 3:   return "Invalid trade parameters";
      case 4:   return "Trade server busy";
      case 5:   return "Old version of client terminal";
      case 6:   return "No connection with trade server";
      case 7:   return "Not enough rights";
      case 8:   return "Too frequent requests";
      case 9:   return "Malfunctional trade operation";
      case 64:  return "Account disabled";
      case 65:  return "Invalid account";
      case 128: return "Trade timeout";
      case 129: return "Invalid price";
      case 130: return "Invalid stops";
      case 131: return "Invalid trade volume";
      case 132: return "Market is closed";
      case 133: return "Trade is disabled";
      case 134: return "Not enough money";
      case 135: return "Price changed";
      case 136: return "Off quotes";
      case 137: return "Broker is busy";
      case 138: return "Requote";
      case 139: return "Order is locked";
      case 140: return "Buy orders only allowed";
      case 141: return "Too many requests";
      case 145: return "Modification denied (too close)";
      case 146: return "Trade context is busy";
      case 147: return "Expiration denied by broker";
      case 148: return "Pending orders limit reached";
      default:  return "Unknown error " + IntegerToString(error);
   }
}

//+------------------------------------------------------------------+
//| 상태 패널 그리기                                                  |
//+------------------------------------------------------------------+
void DrawPanel()
{
   // 통계 수집
   g_totalBuyLimits = 0;
   g_totalSellLimits = 0;
   g_totalBuyTrades = 0;
   g_totalSellTrades = 0;
   g_sessionPL = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;

      if(OrderType() == OP_BUYLIMIT) g_totalBuyLimits++;
      else if(OrderType() == OP_SELLLIMIT) g_totalSellLimits++;
      else if(OrderType() == OP_BUY) { g_totalBuyTrades++; g_sessionPL += OrderProfit() + OrderSwap() + OrderCommission(); }
      else if(OrderType() == OP_SELL) { g_totalSellTrades++; g_sessionPL += OrderProfit() + OrderSwap() + OrderCommission(); }
   }

   // 오늘 종료된 주문의 손익
   double closedPL = 0;
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      if(OrderCloseTime() >= iTime(Symbol(), PERIOD_D1, 0))
         closedPL += OrderProfit() + OrderSwap() + OrderCommission();
   }
   g_sessionPL += closedPL;

   // 스프레드
   double spread = MarketInfo(Symbol(), MODE_SPREAD) * Point / g_pointSize;

   // 패널 그리기
   color plColor = g_sessionPL >= 0 ? clrLime : clrRed;

   string line1 = "SMC Breakout EA v1.0 | " + Symbol() + " " + GetTimeframeName();
   CreateLabel("SMCEA_P1", 10, 20, line1, clrYellow);

   string line2 = "Pending: BuyLimit=" + IntegerToString(g_totalBuyLimits) +
                   "  SellLimit=" + IntegerToString(g_totalSellLimits);
   CreateLabel("SMCEA_P2", 10, 38, line2, clrWhite);

   string line3 = "Trades: Buy=" + IntegerToString(g_totalBuyTrades) +
                   "  Sell=" + IntegerToString(g_totalSellTrades) +
                   "  P/L: " + DoubleToStr(g_sessionPL, 2);
   CreateLabel("SMCEA_P3", 10, 56, line3, plColor);

   string line4 = "Levels: Long=" + IntegerToString(CountActiveLevels(true)) +
                   "  Short=" + IntegerToString(CountActiveLevels(false)) +
                   "  | Spread: " + DoubleToStr(spread, 1) + " pip";
   CreateLabel("SMCEA_P4", 10, 74, line4, clrGray);

   string line5 = "SL=" + IntegerToString(StopLossPoints) + "pt  TP=" + IntegerToString(TakeProfitPoints) +
                   "pt  Trail=" + (UseTrailing ? IntegerToString(TrailingStartPoints) + "/" + IntegerToString(TrailingStepPoints) + "pt" : "OFF");
   CreateLabel("SMCEA_P5", 10, 92, line5, clrDarkGray);
}

//+------------------------------------------------------------------+
//| 타임프레임 이름                                                   |
//+------------------------------------------------------------------+
string GetTimeframeName()
{
   switch(Period())
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";
      default: return "TF" + IntegerToString(Period());
   }
}

//+------------------------------------------------------------------+
//| 레벨 라인 그리기                                                  |
//+------------------------------------------------------------------+
void DrawLevelLines()
{
   for(int i = 0; i < ArraySize(g_levels); i++)
   {
      string baseName = "SMCEA_Lv_" + IntegerToString(i);

      if(!g_levels[i].active)
      {
         ObjectDelete(baseName);
         ObjectDelete(baseName + "_lbl");
         continue;
      }

      color lineColor = g_levels[i].isBullish ? BullishColor : BearishColor;
      int lineStyle = g_levels[i].ticket > 0 ? STYLE_SOLID : STYLE_DASH;

      // 수평선
      if(ObjectFind(baseName) < 0)
         ObjectCreate(baseName, OBJ_HLINE, 0, 0, g_levels[i].price);

      ObjectSet(baseName, OBJPROP_PRICE1, g_levels[i].price);
      ObjectSet(baseName, OBJPROP_COLOR, lineColor);
      ObjectSet(baseName, OBJPROP_STYLE, lineStyle);
      ObjectSet(baseName, OBJPROP_WIDTH, 1);
      ObjectSet(baseName, OBJPROP_BACK, true);

      // 라벨
      string labelName = baseName + "_lbl";
      string orderStatus = g_levels[i].ticket > 0 ? " [#" + IntegerToString(g_levels[i].ticket) + "]" : " [대기]";
      string labelText = (g_levels[i].isBullish ? "BUY LMT " : "SELL LMT ") +
                          DoubleToStr(g_levels[i].price, Digits) + orderStatus;

      if(ObjectFind(labelName) < 0)
         ObjectCreate(labelName, OBJ_TEXT, 0, Time[0], g_levels[i].price);

      ObjectSetText(labelName, labelText, FontSize, "Arial Bold", lineColor);
      ObjectSet(labelName, OBJPROP_TIME1, Time[0]);
      ObjectSet(labelName, OBJPROP_PRICE1, g_levels[i].price);
   }
}

//+------------------------------------------------------------------+
//| 라벨 생성 헬퍼                                                    |
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
//| 오브젝트 전체 삭제                                                |
//+------------------------------------------------------------------+
void CleanupObjects()
{
   for(int i = ObjectsTotal() - 1; i >= 0; i--)
   {
      string name = ObjectName(i);
      if(StringFind(name, "SMCEA_") >= 0)
         ObjectDelete(name);
   }
}
//+------------------------------------------------------------------+
