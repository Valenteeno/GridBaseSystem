//+------------------------------------------------------------------+
//|                                             Grid Base System.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property version   "1.00"
#property strict
#define gridMagic 146821

//============================ inputs ===============================
enum TRADE_DIRECTION {
   BUY_ONLY=0,    // Buy Only
   SELL_ONLY=1,   // Sell Only
   BOTH=2         // Both
};
enum REOPEN_POSITION {
   NO=0,    // No
   YES=1    // Yes
};
enum TP_TYPE {
   INDIVIDUAL=0,  // Individual TP
   COMBINE=1      // Combine all Position TP
};

//--- Functionality Controls
input group "Grid System Settings"
input double InstrumentStartPoint = 5553.01;
input TRADE_DIRECTION TradeDirection = BOTH;
input double GapBetweenPrice = 50.0;
input REOPEN_POSITION ReopenPosition = YES;
input bool exactGridEntry = false;

//--- Lot Management
input group "Lot Management"
input double FixedLot = 0.01;
input double MultipleLot = 2.0;
input double PlusLot = 0.01;
input int MAXBuyOrder = 10;
input int MAXSellOrder = 10;

//--- Take Profit Management
input group "Take Profit Management"
input double TP = 100.0;
input TP_TYPE TPType = COMBINE;

//--- Stoploss Management
input group "Stoploss Management"
input double SL = 100.0;

//=========================== globals ===============================
double Buygridprice = 0.0;
double Sellgridprice = 0.0;
bool gridActivate = false;
bool priceWasAbove = false;
ENUM_ORDER_TYPE_FILLING orderFill;

//============================ functions =============================

//--- Trade functions
bool addPosition(ENUM_ORDER_TYPE type, double vol, double tpx, double slx, MqlTradeRequest &request, MqlTradeResult &result) {
   ZeroMemory(request);
   ZeroMemory(result);
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = NormalizeDouble(vol, 2);
   request.type_filling = orderFill;
   request.tp = NormalizeDouble(tpx, _Digits);
   if(!(slx == 0)) {
      request.sl = NormalizeDouble(slx, _Digits);
   }
   request.magic = gridMagic;
   request.type = type;
   if(OrderSend(request, result)) {
      return true;
   }
   return false;
}

void setSLTP(ulong ticket, double tsl, double ttp, MqlTradeRequest &request, MqlTradeResult &result) {
   ZeroMemory(request);
   ZeroMemory(result);
   request.action = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.symbol = _Symbol;
   PositionSelectByTicket(ticket);
   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double stops = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double lower = SymbolInfoDouble(_Symbol, SYMBOL_BID) - stops;
   double upper = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + stops;
   double sls = type == POSITION_TYPE_BUY ? (tsl < lower ? tsl : lower) : ((tsl > upper || tsl == 0) ? tsl : upper);
   double tps = type == POSITION_TYPE_BUY ? ((ttp > upper || ttp == 0) ? ttp : upper) : (ttp < lower ? ttp : lower);
   request.sl = NormalizeDouble(sls, _Digits);
   request.tp = NormalizeDouble(tps, _Digits);
   if(OrderSendAsync(request, result)) {}
}

void groupTrailer(ENUM_POSITION_TYPE type, double trailStop) {
   MqlTradeRequest request;
   MqlTradeResult result;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == gridMagic) {
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == type) {
            double currentSL = PositionGetDouble(POSITION_SL);
            double currentTP = PositionGetDouble(POSITION_TP);
            
            if(type == POSITION_TYPE_BUY && trailStop > currentSL) {
               setSLTP(ticket, trailStop, currentTP, request, result);
            }
            else if(type == POSITION_TYPE_SELL && (trailStop < currentSL || currentSL == 0)) {
               setSLTP(ticket, trailStop, currentTP, request, result);
            }
         }
      }
   }
}

int typeCount(ENUM_POSITION_TYPE type) {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == gridMagic) {
         if(PositionGetInteger(POSITION_TYPE) == type) {
            count++;
         }
      }
   }
   return count;
}

void groupTp(ENUM_POSITION_TYPE type) {
   if(TPType != COMBINE || TP == 0) return;
   
   MqlTradeRequest request;
   MqlTradeResult result;
   
   double sumOpenPrice = 0;
   int count = 0;
   
   // Calculate average open price
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
         PositionGetInteger(POSITION_MAGIC) == gridMagic &&
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == type) {
         
         sumOpenPrice += PositionGetDouble(POSITION_PRICE_OPEN);
         count++;
      }
   }
   
   if(count == 0) return;
   
   double avgOpenPrice = sumOpenPrice / count;
   double tpLevel = 0;
   
   if(type == POSITION_TYPE_BUY) {
      tpLevel = avgOpenPrice + (TP * _Point);
   } else {
      tpLevel = avgOpenPrice - (TP * _Point);
   }
   
   // Apply TP to all positions of this type
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
         PositionGetInteger(POSITION_MAGIC) == gridMagic &&
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == type) {
         
         double currentSL = PositionGetDouble(POSITION_SL);
         setSLTP(ticket, currentSL, tpLevel, request, result);
      }
   }
}

double calculateLotSize(int tradeCount, bool isMultiple) {
   double lotSize;
   
   if(tradeCount == 0) {
      return FixedLot;
   }
   
   if(isMultiple) {
      // Multiple lot calculation
      lotSize = FixedLot * MathPow(MultipleLot, tradeCount);
   } else {
      // Plus lot calculation
      lotSize = FixedLot + (PlusLot * tradeCount);
   }
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
   // Check that autotrading is enabled
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) {
      Alert("First Enable autotrading on terminal to take trades");
      return INIT_FAILED;
   }
   
   // Initialize global variables
   Buygridprice = InstrumentStartPoint;
   Sellgridprice = InstrumentStartPoint;
   gridActivate = false;
   
   // Determine initial price position relative to start point
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   if(bid > InstrumentStartPoint) {
      priceWasAbove = true;
   } else if(ask < InstrumentStartPoint) {
      priceWasAbove = false;
   } else {
      Alert("Current price is exactly at Instrument Start Point. Please adjust the start point or try again later.");
      return INIT_FAILED;
   }
   
   // Get possible filling policy types by symbol
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   
   // If the required filling policy is supported, add it to the request
   if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) {
      orderFill = ORDER_FILLING_FOK;
   } else if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) {
      orderFill = ORDER_FILLING_IOC;
   } else {
      orderFill = ORDER_FILLING_RETURN;
   }
   
   // Validate inputs
   if(GapBetweenPrice <= 0) {
      Alert("Gap Between Price must be greater than zero.");
      return INIT_FAILED;
   }
   
   if(FixedLot <= 0) {
      Alert("Fixed Lot must be greater than zero.");
      return INIT_FAILED;
   }
   
   if(MultipleLot <= 0) {
      Alert("Multiple Lot must be greater than zero.");
      return INIT_FAILED;
   }
   
   if(MAXBuyOrder <= 0 || MAXSellOrder <= 0) {
      Alert("MAX Buy/Sell Order must be greater than zero.");
      return INIT_FAILED;
   }
   
   if(PlusLot < 0) {
      Alert("Plus Lot cannot be negative.");
      return INIT_FAILED;
   }
   
   Print("Grid Base System initialized successfully.");
   Print("Starting configuration: Buy grid price: ", Buygridprice, ", Sell grid price: ", Sellgridprice);
   Print("Price was above start point: ", priceWasAbove);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   // Cleanup or final operations if needed
   Print("Grid Base System deinitialized, reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
   // Order structures
   MqlTradeRequest request;
   MqlTradeResult result;
   
   // Get current prices
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // Handle trailing stop if SL is set
   if(SL > 0) {
      int buyCount = typeCount(POSITION_TYPE_BUY);
      int sellCount = typeCount(POSITION_TYPE_SELL);
      
      if(buyCount > 0) {
         double buyTrailStop = bid - (SL * point);
         groupTrailer(POSITION_TYPE_BUY, buyTrailStop);
      }
      
      if(sellCount > 0) {
         double sellTrailStop = ask + (SL * point);
         groupTrailer(POSITION_TYPE_SELL, sellTrailStop);
      }
   }
   
   // Only process if we're not at the maximum number of orders
   int buyCount = typeCount(POSITION_TYPE_BUY);
   int sellCount = typeCount(POSITION_TYPE_SELL);
   
   // Generate grid levels
   double buyLevels[100];  // Large enough array for all levels
   double sellLevels[100]; // Large enough array for all levels
   int levelCount = 0;
   
   // Generate levels above starting point
   for(int i = 0; i < 13; i++) {
      buyLevels[levelCount] = InstrumentStartPoint + (i * GapBetweenPrice * point);
      sellLevels[levelCount] = InstrumentStartPoint + (i * GapBetweenPrice * point);
      levelCount++;
   }
   
   // Generate levels below starting point
   for(int i = 1; i < 13; i++) {
      buyLevels[levelCount] = InstrumentStartPoint - (i * GapBetweenPrice * point);
      sellLevels[levelCount] = InstrumentStartPoint - (i * GapBetweenPrice * point);
      levelCount++;
   }
   
   // Process buy orders
   if(buyCount < MAXBuyOrder && (TradeDirection == BUY_ONLY || TradeDirection == BOTH)) {
      for(int i = 0; i < levelCount; i++) {
         double level = buyLevels[i];
         
         // Check if we need to place a buy order at this level
         if(ask <= level && !isOrderAtLevel(level, ORDER_TYPE_BUY)) {
            // Calculate lot size based on position count
            double lotSize = calculateLotSize(countOrdersBelow(level, ORDER_TYPE_BUY));
            
            // Set TP and SL levels
            double tpLevel = TP == 0 || TPType == COMBINE ? 0 : level + (TP * point);
            double slLevel = SL == 0 ? 0 : level - (SL * point);
            
            // Place the order
            if(addPosition(ORDER_TYPE_BUY, lotSize, tpLevel, slLevel, request, result)) {
               Print("Buy position executed at level ", level, " with lot size ", lotSize);
               
               // Update combined TP if needed
               if(TPType == COMBINE) {
                  groupTp(POSITION_TYPE_BUY);
               }
               
               // Break after one order to avoid multiple orders in a single tick
               break;
            }
         }
      }
   }
   
   // Process sell orders
   if(sellCount < MAXSellOrder && (TradeDirection == SELL_ONLY || TradeDirection == BOTH)) {
      for(int i = 0; i < levelCount; i++) {
         double level = sellLevels[i];
         
         // Check if we need to place a sell order at this level
         if(bid >= level && !isOrderAtLevel(level, ORDER_TYPE_SELL)) {
            // Calculate lot size based on position count
            double lotSize = calculateLotSize(countOrdersAbove(level, ORDER_TYPE_SELL));
            
            // Set TP and SL levels
            double tpLevel = TP == 0 || TPType == COMBINE ? 0 : level - (TP * point);
            double slLevel = SL == 0 ? 0 : level + (SL * point);
            
            // Place the order
            if(addPosition(ORDER_TYPE_SELL, lotSize, tpLevel, slLevel, request, result)) {
               Print("Sell position executed at level ", level, " with lot size ", lotSize);
               
               // Update combined TP if needed
               if(TPType == COMBINE) {
                  groupTp(POSITION_TYPE_SELL);
               }
               
               // Break after one order to avoid multiple orders in a single tick
               break;
            }
         }
      }
   }
   
   // Process reopening of positions if enabled
   if(ReopenPosition == YES) {
      monitorClosedLevels();
   }
}

//+------------------------------------------------------------------+
//| Check if an order already exists at the given level              |
//+------------------------------------------------------------------+
bool isOrderAtLevel(double level, ENUM_ORDER_TYPE type) {
   double tolerance = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 2; // Small tolerance for floating point comparison
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!PositionGetTicket(i)) continue;
      
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == gridMagic) {
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         
         if((posType == POSITION_TYPE_BUY && type == ORDER_TYPE_BUY) || 
            (posType == POSITION_TYPE_SELL && type == ORDER_TYPE_SELL)) {
            if(MathAbs(openPrice - level) < tolerance) {
               return true;
            }
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Count orders below the given price level                         |
//+------------------------------------------------------------------+
int countOrdersBelow(double level, ENUM_ORDER_TYPE type) {
   int count = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!PositionGetTicket(i)) continue;
      
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == gridMagic) {
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         
         if((posType == POSITION_TYPE_BUY && type == ORDER_TYPE_BUY) || 
            (posType == POSITION_TYPE_SELL && type == ORDER_TYPE_SELL)) {
            if(openPrice < level) {
               count++;
            }
         }
      }
   }
   
   return count;
}

//+------------------------------------------------------------------+
//| Count orders above the given price level                         |
//+------------------------------------------------------------------+
int countOrdersAbove(double level, ENUM_ORDER_TYPE type) {
   int count = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!PositionGetTicket(i)) continue;
      
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == gridMagic) {
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         
         if((posType == POSITION_TYPE_BUY && type == ORDER_TYPE_BUY) || 
            (posType == POSITION_TYPE_SELL && type == ORDER_TYPE_SELL)) {
            if(openPrice > level) {
               count++;
            }
         }
      }
   }
   
   return count;
}

//+------------------------------------------------------------------+
//| Monitor and reopen closed positions if enabled                   |
//+------------------------------------------------------------------+
void monitorClosedLevels() {
   static datetime lastCheckTime = 0;
   
   // Check only once per minute to avoid excessive processing
   if(TimeCurrent() - lastCheckTime < 60) return;
   lastCheckTime = TimeCurrent();
   
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   // Generate grid levels
   double levels[100];  // Large enough array for all levels
   int levelCount = 0;
   
   // Generate levels above starting point
   for(int i = 0; i < 13; i++) {
      levels[levelCount] = InstrumentStartPoint + (i * GapBetweenPrice * point);
      levelCount++;
   }
   
   // Generate levels below starting point
   for(int i = 1; i < 13; i++) {
      levels[levelCount] = InstrumentStartPoint - (i * GapBetweenPrice * point);
      levelCount++;
   }
   
   // Check each level for both buy and sell
   for(int i = 0; i < levelCount; i++) {
      double level = levels[i];
      
      // Check if we need to reopen a buy position at this level
      if(ask <= level && !isOrderAtLevel(level, ORDER_TYPE_BUY) && 
         (TradeDirection == BUY_ONLY || TradeDirection == BOTH)) {
         int buyCount = typeCount(POSITION_TYPE_BUY);
         
         if(buyCount < MAXBuyOrder) {
            double lotSize = calculateLotSize(countOrdersBelow(level, ORDER_TYPE_BUY));
            double tpLevel = TP == 0 || TPType == COMBINE ? 0 : level + (TP * point);
            double slLevel = SL == 0 ? 0 : level - (SL * point);
            
            MqlTradeRequest request;
            MqlTradeResult result;
            
            if(addPosition(ORDER_TYPE_BUY, lotSize, tpLevel, slLevel, request, result)) {
               Print("Reopened Buy position at level ", level, " with lot size ", lotSize);
               
               if(TPType == COMBINE) {
                  groupTp(POSITION_TYPE_BUY);
               }
            }
         }
      }
      
      // Check if we need to reopen a sell position at this level
      if(bid >= level && !isOrderAtLevel(level, ORDER_TYPE_SELL) && 
         (TradeDirection == SELL_ONLY || TradeDirection == BOTH)) {
         int sellCount = typeCount(POSITION_TYPE_SELL);
         
         if(sellCount < MAXSellOrder) {
            double lotSize = calculateLotSize(countOrdersAbove(level, ORDER_TYPE_SELL));
            double tpLevel = TP == 0 || TPType == COMBINE ? 0 : level - (TP * point);
            double slLevel = SL == 0 ? 0 : level + (SL * point);
            
            MqlTradeRequest request;
            MqlTradeResult result;
            
            if(addPosition(ORDER_TYPE_SELL, lotSize, tpLevel, slLevel, request, result)) {
               Print("Reopened Sell position at level ", level, " with lot size ", lotSize);
               
               if(TPType == COMBINE) {
                  groupTp(POSITION_TYPE_SELL);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Tester function                                                  |
//+------------------------------------------------------------------+
double OnTester() {
   double profit = TesterStatistics(STAT_PROFIT);
   double maxDrawdown = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double trades = TesterStatistics(STAT_TRADES);
   
   // Basic validation
   if(maxDrawdown == 0 || profit <= 0) {
      return(0.0);
   }
   // Simple balance to drawdown ratio
   double balanceDrawdownRatio = profit / maxDrawdown;
   
   // Add weight for number of trades to favor more active strategies
   return(balanceDrawdownRatio + (trades/100));
}
//+------------------------------------------------------------------+