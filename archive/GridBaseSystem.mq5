//+------------------------------------------------------------------+
//|                                               GridBaseSystem.mq5 |
//|                                     Copyright 2025, Teenodi Ltd. |
//|                                         https://www.jukwaese.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Teenodi Ltd."
#property link      "https://www.jukwaese.com"
#property version   "1.00"
#property strict
#define gridMagic 137974
//============================ inputs ===============================
input group "Grid Controls"
input double InstrumentStartPoint = 5553.01;
input string TradeDirection = "Both"; // "Buy Only", "Sell Only", "Both"
input double GapBetweenPrice = 50.0;
input bool ReopenPosition = true;
input bool exactGridEntry = false;

input group "Lot Management"
input double FixedLot = 0.01;
input double MultipleLot = 2.0;
input double PlusLot = 0.01;
input string LotType = "Fixed Lot"; // "Fixed Lot", "Multiple Lot", "Plus Lot"
input int MaxBuyOrder = 10;
input int MaxSellOrder = 10;

input group "Take Profit Management"
input double TP = 100.0; // In points
input string TPType = "Individual TP"; // "Individual TP", "Combine all Position TP"

input group "Stoploss Management"
input double SL = 100.0; // In points

//=========================== globals ===============================
double Sellgridprice;
double Buygridprice;
bool gridActivate = false;
bool priceWasAbove;
bool isBuyAllowed;
bool isSellAllowed;

//============================ functions ============================
ENUM_ORDER_TYPE_FILLING orderFill;

// Function to calculate lot size based on count and lot type
double calculateLotSize(int typeCount, string lotType) {
   double lotSize = FixedLot;
   
   if(lotType == "Multiple Lot") {
      lotSize = FixedLot * MathPow(MultipleLot, typeCount);
   }
   else if(lotType == "Plus Lot") {
      lotSize = FixedLot + (PlusLot * typeCount);
   }
   
   return lotSize;
}

// Function to add a position
bool addPosition(ENUM_ORDER_TYPE type, double vol, double tpx, double slx, MqlTradeRequest &request, MqlTradeResult &result) {
   ZeroMemory(request);
   ZeroMemory(result);
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = NormalizeDouble(vol, 2);
   request.type_filling = orderFill;
   request.tp = NormalizeDouble(tpx, _Digits);
   if(!(SL == 0)) {
      request.sl = NormalizeDouble(slx, _Digits);
   }
   request.magic = gridMagic;
   request.type = type;
   if(OrderSend(request, result)) {
      return true;
   }
   return false;
}

// Function to set SL and TP
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

// Function to count positions by type
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

// Function to set group TP
void groupTp(double totalTp, ENUM_POSITION_TYPE type, double &groupSl, double &groupTp) {
   // Sum opening prices and keep count
   double sums = 0;
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == gridMagic) {
         if(PositionGetInteger(POSITION_TYPE) == type) {
            sums += PositionGetDouble(POSITION_PRICE_OPEN);
            n++;
         }
      }
   }
   
   // Calculate sl & tp values
   double slVal = 0, tpVal = 0;
   if(type == POSITION_TYPE_BUY) {
      tpVal = (sums / n) + totalTp * _Point;
   } else {
      tpVal = (sums / n) - totalTp * _Point;
   }
   
   // Return values
   groupTp = tpVal;
   groupSl = slVal;
}

// Function to check if position exists
bool positionExists(int magic) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magic) {
         return true;
      }
   }
   return false;
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
   
   // Validate inputs
   if(FixedLot <= 0) {
      Alert("Fixed Lot must be greater than 0");
      return INIT_FAILED;
   }
   
   if(MultipleLot <= 0) {
      Alert("Multiple Lot must be greater than 0");
      return INIT_FAILED;
   }
   
   if(PlusLot <= 0) {
      Alert("Plus Lot must be greater than 0");
      return INIT_FAILED;
   }
   
   if(MaxBuyOrder <= 0) {
      Alert("Max Buy Order must be greater than 0");
      return INIT_FAILED;
   }
   
   if(MaxSellOrder <= 0) {
      Alert("Max Sell Order must be greater than 0");
      return INIT_FAILED;
   }
   
   // Set trade direction flags
   isBuyAllowed = (TradeDirection == "Buy Only" || TradeDirection == "Both");
   isSellAllowed = (TradeDirection == "Sell Only" || TradeDirection == "Both");
   
   if(!isBuyAllowed && !isSellAllowed) {
      Alert("Invalid Trade Direction. Please choose 'Buy Only', 'Sell Only', or 'Both'.");
      return INIT_FAILED;
   }
   
   // Initialize grid prices
   Sellgridprice = InstrumentStartPoint;
   Buygridprice = InstrumentStartPoint;
   
   // Check if price is above or below start point
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   if(bid > InstrumentStartPoint) {
      priceWasAbove = true;
   } else if(ask < InstrumentStartPoint) {
      priceWasAbove = false;
   } else {
      Alert("Current price is at the Instrument Start Point. Please adjust the start point or try again later.");
      return INIT_FAILED;
   }
   
   // Get possible filling policy types by symbol
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) {
      orderFill = ORDER_FILLING_FOK;
   } else if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) {
      orderFill = ORDER_FILLING_IOC;
   }
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   // Clean up any objects or resources
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
   // Order structures
   MqlTradeRequest request;
   MqlTradeResult result;
   
   // Get current market prices
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   // Handle first execution - this will set gridActivate to true
   if(!gridActivate) {
      // If price was above start point, execute a sell when price crosses below
      if(priceWasAbove && isSellAllowed) {
         bool sellCondition = exactGridEntry ? (bid == Sellgridprice) : (bid <= Sellgridprice);
         if(sellCondition) {
            // Calculate lot size
            double lotSize = calculateLotSize(0, LotType);
            lotSize = lotSize > MaxSellOrder ? MaxSellOrder : lotSize;
            
            // Calculate SL and TP
            double sellSl = SL == 0 ? 0 : ask + SL * _Point;
            double sellTp = TP == 0 ? 0 : bid - TP * _Point;
            
            // Execute sell order
            if(addPosition(ORDER_TYPE_SELL, lotSize, sellTp, sellSl, request, result)) {
               gridActivate = true;
               Sellgridprice = result.price - GapBetweenPrice * _Point;
               Print("First Sell executed at ", result.price, ", Next grid at ", Sellgridprice);
            }
         }
      }
      // If price was below start point, execute a buy when price crosses above
      else if(!priceWasAbove && isBuyAllowed) {
         bool buyCondition = exactGridEntry ? (ask == Buygridprice) : (ask >= Buygridprice);
         if(buyCondition) {
            // Calculate lot size
            double lotSize = calculateLotSize(0, LotType);
            lotSize = lotSize > MaxBuyOrder ? MaxBuyOrder : lotSize;
            
            // Calculate SL and TP
            double buySl = SL == 0 ? 0 : bid - SL * _Point;
            double buyTp = TP == 0 ? 0 : ask + TP * _Point;
            
            // Execute buy order
            if(addPosition(ORDER_TYPE_BUY, lotSize, buyTp, buySl, request, result)) {
               gridActivate = true;
               Buygridprice = result.price + GapBetweenPrice * _Point;
               Print("First Buy executed at ", result.price, ", Next grid at ", Buygridprice);
            }
         }
      }
   }
   
   // Handle subsequent executions
   if(gridActivate) {
      // Handle buy orders
      if(isBuyAllowed) {
         int buyCount = typeCount(POSITION_TYPE_BUY);
         if(buyCount < MaxBuyOrder) {
            bool buyCondition = exactGridEntry ? (ask == Buygridprice) : (ask >= Buygridprice);
            if(buyCondition) {
               // Calculate lot size based on the number of existing buy positions
               double lotSize = calculateLotSize(buyCount, LotType);
               lotSize = lotSize > MaxBuyOrder ? MaxBuyOrder : lotSize;
               
               // Calculate SL and TP
               double buySl = SL == 0 ? 0 : bid - SL * _Point;
               double buyTp = TP == 0 ? 0 : ask + TP * _Point;
               
               // Execute buy order
               if(addPosition(ORDER_TYPE_BUY, lotSize, buyTp, buySl, request, result)) {
                  Buygridprice = result.price + GapBetweenPrice * _Point;
                  Print("Buy executed at ", result.price, ", Next grid at ", Buygridprice);
                  
                  // Update TP for all positions if TPType is "Combine all Position TP"
                  if(TPType == "Combine all Position TP" && TP > 0) {
                     double groupSl, groupTp;
                     groupTp(TP, POSITION_TYPE_BUY, groupSl, groupTp);
                     
                     for(int i = PositionsTotal() - 1; i >= 0; i--) {
                        ulong ticket = PositionGetTicket(i);
                        if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
                           PositionGetInteger(POSITION_MAGIC) == gridMagic &&
                           PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
                           setSLTP(ticket, PositionGetDouble(POSITION_SL), groupTp, request, result);
                        }
                     }
                  }
               }
            }
         }
      }
      
      // Handle sell orders
      if(isSellAllowed) {
         int sellCount = typeCount(POSITION_TYPE_SELL);
         if(sellCount < MaxSellOrder) {
            bool sellCondition = exactGridEntry ? (bid == Sellgridprice) : (bid <= Sellgridprice);
            if(sellCondition) {
               // Calculate lot size based on the number of existing sell positions
               double lotSize = calculateLotSize(sellCount, LotType);
               lotSize = lotSize > MaxSellOrder ? MaxSellOrder : lotSize;
               
               // Calculate SL and TP
               double sellSl = SL == 0 ? 0 : ask + SL * _Point;
               double sellTp = TP == 0 ? 0 : bid - TP * _Point;
               
               // Execute sell order
               if(addPosition(ORDER_TYPE_SELL, lotSize, sellTp, sellSl, request, result)) {
                  Sellgridprice = result.price - GapBetweenPrice * _Point;
                  Print("Sell executed at ", result.price, ", Next grid at ", Sellgridprice);
                  
                  // Update TP for all positions if TPType is "Combine all Position TP"
                  if(TPType == "Combine all Position TP" && TP > 0) {
                     double groupSl, groupTp;
                     groupTp(TP, POSITION_TYPE_SELL, groupSl, groupTp);
                     
                     for(int i = PositionsTotal() - 1; i >= 0; i--) {
                        ulong ticket = PositionGetTicket(i);
                        if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
                           PositionGetInteger(POSITION_MAGIC) == gridMagic &&
                           PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
                           setSLTP(ticket, PositionGetDouble(POSITION_SL), groupTp, request, result);
                        }
                     }
                  }
               }
            }
         }
      }
      
      // Trailing SL for existing positions
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         ulong ticket = PositionGetTicket(i);
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == gridMagic) {
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentSl = PositionGetDouble(POSITION_SL);
            
            if(type == POSITION_TYPE_BUY && SL > 0) {
               double newSl = bid - SL * _Point;
               if(newSl > currentSl && newSl < bid) {
                  setSLTP(ticket, newSl, PositionGetDouble(POSITION_TP), request, result);
               }
            }
            else if(type == POSITION_TYPE_SELL && SL > 0) {
               double newSl = ask + SL * _Point;
               if(newSl < currentSl && newSl > ask) {
                  setSLTP(ticket, newSl, PositionGetDouble(POSITION_TP), request, result);
               }
            }
         }
      }
   }
   
   // Reset grid prices if no positions and reopening is allowed
   if(ReopenPosition) {
      int buyCount = typeCount(POSITION_TYPE_BUY);
      if(buyCount == 0 && gridActivate) {
         Buygridprice = ask + GapBetweenPrice * _Point;
      }
      
      int sellCount = typeCount(POSITION_TYPE_SELL);
      if(sellCount == 0 && gridActivate) {
         Sellgridprice = bid - GapBetweenPrice * _Point;
      }
   }
}
//+------------------------------------------------------------------+
//| Expert tester function                                           |
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