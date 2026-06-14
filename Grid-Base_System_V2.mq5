//+------------------------------------------------------------------+
//|                                   Grid-Base_System_MA_Filter.mq5 |
//|                                     Copyright 2025, Teenodi Ltd. |
//|                                         https://www.jukwaese.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Teenodi Ltd."
#property link      "https://www.jukwaese.com"
#property version   "1.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots 1
#property indicator_color1 Yellow
#property indicator_width1 2
#define gridMagic 137974

//============================ Enums ===============================
enum TradeDirectionEnum {
   BUY_ONLY,
   SELL_ONLY,
   BOTH
};

enum YesNoEnum {
   NO,
   YES
};

enum LotSizingType {
   FIXED,
   MULTIPLE,
   PLUS
};

enum TPTypeEnum {
   INDIVIDUAL_TP,
   COMBINE_TP
};

//============================ inputs ===============================
// Input parameter for username
input string Username = ""; // Enter your username

input group "Grid Base System"
input double       InstrumentStartPoint = 5553.01;
input TradeDirectionEnum TradeDirection = BOTH;
input int          MaxBuyPositions = 10;
input int          MaxSellPositions = 10;
input double       GridSize = 50;
input YesNoEnum    ReopenPosition = YES;

input group "Moving Average Filter & Reverse Stop"
input int          MAFilterPeriod = 45;       // MA Period for filter and reverse stop
input YesNoEnum    EnableReverseMA = YES;     // Enable MA Reverse Stop

input group "Lot Management"
input LotSizingType LotSizingMethod = FIXED;
input double       FixedLot = 0.01;
input double       MultipleLot = 2;
input double       PlusLot = 0.01;
input double       MAX_BUY_LOT = 5.0;
input double       MAX_SELL_LOT = 5.0;

input group "Take Profit Management"
input double       TP = 200;
input TPTypeEnum   TPType = INDIVIDUAL_TP;

input group "Stoploss Management"
input double       SL = 100;

//=========================== globals ===============================
// Global variables for verification
string g_AuthorizedUsername = "AuthorizedUser"; // Change this to your authorized username
datetime g_ExpiryDate = D'2025.12.31 23:59:59'; // Set your expiry date here in format YYYY.MM.DD
long g_AuthorizedAccount = 12345678;  // Set this to 0 if you want to use the account number from AccountInfoInteger

// Constant inputs
double gridSizePoints;
double slPoints;
double tpPoints;
double lastBuyPrice = 0;
double lastSellPrice = 0;
double buySl = 0;
double buyTp = 0;
double sellSl = 0;
double sellTp = 0;

// Moving Average
int MAHandle;
double MABuffer[];

// Reverse stop variables
bool prevAboveState = false;
bool prevBelowState = false;

// Variables
ENUM_ORDER_TYPE_FILLING orderFill;

//============================ functions =============================
//------------------------------ trade --------------------------------+
bool addPosition(ENUM_ORDER_TYPE type, double vol, double tpx, double slx, MqlTradeRequest &request, MqlTradeResult &result) {
   ZeroMemory(request);
   ZeroMemory(result);
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = NormalizeDouble(vol, 2);
   request.type_filling = orderFill;
   if(tpx != 0) {
      request.tp = NormalizeDouble(tpx, _Digits);
   }
   if(slx != 0) {
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
      slVal = buySl;
      tpVal = (sums + totalTp) / n;
   } else {
      slVal = sellSl;
      tpVal = (sums - totalTp) / n;
   }
   
   // Return values
   groupTp = tpVal;
   groupSl = slVal;
}

void setGroupSlTp(ENUM_POSITION_TYPE type, MqlTradeRequest &request, MqlTradeResult &result) {
   double gsl, gtp;
   groupTp(tpPoints, type, gsl, gtp);
   for(int j = PositionsTotal() - 1; j >= 0; j--) {
      ulong ticket = PositionGetTicket(j);
      if(PositionGetInteger(POSITION_TYPE) == type) {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == gridMagic) {
            setSLTP(ticket, gsl, gtp, request, result);
         }
      }
   }
}

bool posTypeCheck(ENUM_POSITION_TYPE type) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == gridMagic) {
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == type) {
            return true;
         }
      }
   }
   return false;
}

double calculateLotSize(int count, ENUM_POSITION_TYPE type) {
   double lotSize = FixedLot;
   
   switch(LotSizingMethod) {
      case FIXED:
         lotSize = FixedLot;
         break;
      case MULTIPLE:
         lotSize = FixedLot * MathPow(MultipleLot, count);
         break;
      case PLUS:
         lotSize = FixedLot + (PlusLot * count);
         break;
   }
   
   // Cap lot size at maximum allowed
   if(type == POSITION_TYPE_BUY && lotSize > MAX_BUY_LOT) {
      lotSize = MAX_BUY_LOT;
   } else if(type == POSITION_TYPE_SELL && lotSize > MAX_SELL_LOT) {
      lotSize = MAX_SELL_LOT;
   }
   
   return NormalizeDouble(lotSize, 2);
}

bool isOnGrid(double price) {
   return MathAbs(fmod(MathAbs(price - InstrumentStartPoint), gridSizePoints)) < (0.5 * SymbolInfoDouble(_Symbol, SYMBOL_POINT));
}

// This function will check if a price is valid for opening a new position
// It ensures the price is at least gridSize away from any existing position of the same type
bool isValidGridPrice(double price, ENUM_POSITION_TYPE type) {
   double minPrice = DBL_MAX;
   double maxPrice = 0;
   bool hasPositions = false;
   
   // Find the minimum and maximum open position prices for the given type
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == gridMagic) {
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == type) {
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            
            // Update min and max prices
            if(openPrice < minPrice) minPrice = openPrice;
            if(openPrice > maxPrice) maxPrice = openPrice;
            hasPositions = true;
         }
      }
   }
   
   // If no positions exist, any grid point is valid
   if(!hasPositions) return true;
   
   // Check if the price is at least gridSize away from any existing position
   // For a valid position, price must be <= (minPrice - gridSizePoints) OR >= (maxPrice + gridSizePoints)
   if(price <= (minPrice - gridSizePoints) || price >= (maxPrice + gridSizePoints)) {
      return true;
   }
   
   return false;
}

bool isGridValid(double price, ENUM_POSITION_TYPE type) {
   // First check if the price is on a valid grid point
   if(!isOnGrid(price)) return false;
   
   // Then check if this specific price is already used
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == gridMagic) {
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == type) {
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            if(MathAbs(openPrice - price) < (0.5 * SymbolInfoDouble(_Symbol, SYMBOL_POINT))) {
               return false; // Price is already used
            }
         }
      }
   }
   
   // Finally, check if the price respects the grid spacing from other positions
   return isValidGridPrice(price, type);
}

// Function to check the moving average as trade filter
bool CheckMAFilter(ENUM_POSITION_TYPE type) {
   double maValue[1];
   if(CopyBuffer(MAHandle, 0, 0, 1, maValue) != 1) 
      return false;
   
   double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // BUY only allowed above MA, SELL only allowed below MA
   if(type == POSITION_TYPE_BUY && bidPrice > maValue[0])
      return true;
   else if(type == POSITION_TYPE_SELL && askPrice < maValue[0])
      return true;
   
   return false;
}

// Function to check MA reverse stop condition
void CheckReverseStop() {
   // Skip if reverse MA feature is disabled
   if(EnableReverseMA == NO) return;
   
   double maValue[1];
   if(CopyBuffer(MAHandle, 0, 0, 1, maValue) != 1) return;
   
   double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   // Update current states
   bool currentAboveState = (bidPrice > maValue[0]);
   bool currentBelowState = (askPrice < maValue[0]);
   
   // Detect crosses
   if(currentAboveState != prevAboveState || currentBelowState != prevBelowState) {
      // Check for upward cross (bid crosses above MA)
      if(currentAboveState && !prevAboveState) {
         ClosePositionsByType(POSITION_TYPE_SELL);
         Print("Reverse MA upward cross detected - closing sell positions");
      }
      
      // Check for downward cross (ask crosses below MA)
      if(currentBelowState && !prevBelowState) {
         ClosePositionsByType(POSITION_TYPE_BUY);
         Print("Reverse MA downward cross detected - closing buy positions");
      }
      
      // Update previous states
      prevAboveState = currentAboveState;
      prevBelowState = currentBelowState;
   }
}

// Helper function to close positions by type
void ClosePositionsByType(ENUM_POSITION_TYPE type) {
   MqlTradeRequest request;
   MqlTradeResult result;
   
   for(int a = PositionsTotal() - 1; a >= 0; a--) { // backwards to avoid effect of queue movement
      ulong ticket = PositionGetTicket(a);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == gridMagic) {
         double volume = PositionGetDouble(POSITION_VOLUME);
         if(PositionGetInteger(POSITION_TYPE) == type) {
            ZeroMemory(request);
            ZeroMemory(result);
            request.action = TRADE_ACTION_DEAL;
            request.position = ticket;
            request.symbol = _Symbol;
            request.type = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.volume = volume;
            request.type_filling = orderFill;
            if(OrderSend(request, result)) {
               Print("[INFO] Closed position #", ticket);
            }
            else {
               Print("[INFO] Failed to close position #", ticket);
            }
         }
      }
   }
   Print("Position closed by reverse MA: ", EnumToString(type));
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
   // Check if verification passes
   if(!VerifyAccess())
   {
      Print("Access denied: Authentication failed");
      MessageBox("Authentication failed. Access denied.\nPlease contact the vendor for assistance.", "Access Denied", MB_ICONERROR);
      return(INIT_FAILED);
   }
   // Check that autotrading is enabled
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) {
      Alert("First Enable autotrading on terminal to take trades");
      return INIT_FAILED;
   }
   
   // Input validations
   if(GridSize <= 0) {
      Alert("Grid size must be greater than 0!");
      return INIT_FAILED;
   }
   
   if(MaxBuyPositions <= 0 || MaxSellPositions <= 0) {
      Alert("Maximum positions must be greater than 0!");
      return INIT_FAILED;
   }
   
   if(FixedLot <= 0) {
      Alert("Fixed lot size must be greater than 0!");
      return INIT_FAILED;
   }
   
   if(MultipleLot <= 0) {
      Alert("Multiple lot factor must be greater than 0!");
      return INIT_FAILED;
   }
   
   if(PlusLot <= 0) {
      Alert("Plus lot value must be greater than 0!");
      return INIT_FAILED;
   }
   
   // Get possible filling policy types by symbol
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   // If the required filling policy is supported, add it to the request
   if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) {
      orderFill = ORDER_FILLING_FOK;
   } else if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) {
      orderFill = ORDER_FILLING_IOC;
   }
   
   // Set up symbol-specific variables
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   gridSizePoints = NormalizeDouble(GridSize * point, _Digits);
   slPoints = NormalizeDouble(SL * point, _Digits);
   tpPoints = NormalizeDouble(TP * point, _Digits);
   
   // Initialize MA indicator for filtering and reverse stop
   MAHandle = iMA(_Symbol, PERIOD_CURRENT, MAFilterPeriod, 0, MODE_SMA, PRICE_CLOSE);
   if(MAHandle == INVALID_HANDLE) {
      Print("Error creating MA indicator");
      return INIT_FAILED;
   }
   
   // Set up MA indicator on chart
   ArraySetAsSeries(MABuffer, true);
   ChartIndicatorAdd(0, 0, MAHandle);
   
   // Initialize MA states for reverse stop (only if reverse MA is enabled)
   if(EnableReverseMA == YES) {
      double maValue[1];
      if(CopyBuffer(MAHandle, 0, 0, 1, maValue) == 1) {
         double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         prevAboveState = (bidPrice > maValue[0]);
         prevBelowState = (askPrice < maValue[0]);
      }
      else {
         prevAboveState = false;
         prevBelowState = false;
      }
   }
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   // Release the MA indicator handle
   if(MAHandle != INVALID_HANDLE) {
      IndicatorRelease(MAHandle);
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
   // Order structures
   MqlTradeRequest request;
   MqlTradeResult result;
   
   // Current tick data
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double spread = ask - bid;
   
   // Check for reverse stop conditions (only if enabled)
   if(EnableReverseMA == YES) {
      CheckReverseStop();
   }
   
   // Check if we can place buy positions
   if((TradeDirection == BUY_ONLY || TradeDirection == BOTH) && typeCount(POSITION_TYPE_BUY) < MaxBuyPositions) {
      // Check if the current price is on a valid grid position and passes MA filter
      if(isOnGrid(ask) && isValidGridPrice(ask, POSITION_TYPE_BUY) && CheckMAFilter(POSITION_TYPE_BUY)) {
         // Calculate lot size based on current buy positions
         int buyCount = typeCount(POSITION_TYPE_BUY);
         double lotSize = calculateLotSize(buyCount, POSITION_TYPE_BUY);
         
         // Calculate SL and TP
         buySl = SL > 0 ? bid - slPoints : 0;
         buyTp = TP > 0 ? ask + tpPoints : 0;
         
         // Place buy order
         if(addPosition(ORDER_TYPE_BUY, lotSize, buyTp, buySl, request, result)) {
            lastBuyPrice = result.price;
            
            // Set combined TP if needed
            if(TPType == COMBINE_TP && typeCount(POSITION_TYPE_BUY) > 1) {
               setGroupSlTp(POSITION_TYPE_BUY, request, result);
            }
         }
      }
   }
   
   // Check if we can place sell positions
   if((TradeDirection == SELL_ONLY || TradeDirection == BOTH) && typeCount(POSITION_TYPE_SELL) < MaxSellPositions) {
      // Check if the current price is on a valid grid position and passes MA filter
      if(isOnGrid(bid) && isValidGridPrice(bid, POSITION_TYPE_SELL) && CheckMAFilter(POSITION_TYPE_SELL)) {
         // Calculate lot size based on current sell positions
         int sellCount = typeCount(POSITION_TYPE_SELL);
         double lotSize = calculateLotSize(sellCount, POSITION_TYPE_SELL);
         
         // Calculate SL and TP
         sellSl = SL > 0 ? ask + slPoints : 0;
         sellTp = TP > 0 ? bid - tpPoints : 0;
         
         // Place sell order
         if(addPosition(ORDER_TYPE_SELL, lotSize, sellTp, sellSl, request, result)) {
            lastSellPrice = result.price;
            
            // Set combined TP if needed
            if(TPType == COMBINE_TP && typeCount(POSITION_TYPE_SELL) > 1) {
               setGroupSlTp(POSITION_TYPE_SELL, request, result);
            }
         }
      }
   }
   
   // Handle reopen positions if enabled
   if(ReopenPosition == YES) {
      // Check closed positions and reopen at the same grid level if appropriate
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--) {
         ulong ticket = HistoryDealGetTicket(i);
         if(HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol && HistoryDealGetInteger(ticket, DEAL_MAGIC) == gridMagic) {
            // Get the position details
            ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
            ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
            
            // Check if it's a position exit
            if(dealEntry == DEAL_ENTRY_OUT) {
               double dealPrice = HistoryDealGetDouble(ticket, DEAL_PRICE);
               
               // Check if the grid level is still valid and not used
               if((dealType == DEAL_TYPE_BUY && TradeDirection != SELL_ONLY) || 
                  (dealType == DEAL_TYPE_SELL && TradeDirection != BUY_ONLY)) {
                  
                  // Make sure this position respects grid spacing
                  ENUM_POSITION_TYPE posType = dealType == DEAL_TYPE_BUY ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
                  double checkPrice = dealType == DEAL_TYPE_BUY ? ask : bid;
                  
                  // Check if the position can be reopened based on current price and valid grid rules
                  if(isOnGrid(checkPrice) && isValidGridPrice(checkPrice, posType)) {
                     
                     // Calculate lot size based on current positions
                     int posCount = typeCount(posType);
                     double lotSize = calculateLotSize(posCount, posType);
                     
                     // Calculate SL and TP
                     double newSl = 0, newTp = 0;
                     if(dealType == DEAL_TYPE_BUY) {
                        newSl = SL > 0 ? bid - slPoints : 0;
                        newTp = TP > 0 ? ask + tpPoints : 0;
                        
                        // Place buy order
                        if(addPosition(ORDER_TYPE_BUY, lotSize, newTp, newSl, request, result)) {
                           lastBuyPrice = result.price;
                           
                           // Set combined TP if needed
                           if(TPType == COMBINE_TP && typeCount(POSITION_TYPE_BUY) > 1) {
                              setGroupSlTp(POSITION_TYPE_BUY, request, result);
                           }
                        }
                     } else {
                        newSl = SL > 0 ? ask + slPoints : 0;
                        newTp = TP > 0 ? bid - tpPoints : 0;
                        
                        // Place sell order
                        if(addPosition(ORDER_TYPE_SELL, lotSize, newTp, newSl, request, result)) {
                           lastSellPrice = result.price;
                           
                           // Set combined TP if needed
                           if(TPType == COMBINE_TP && typeCount(POSITION_TYPE_SELL) > 1) {
                              setGroupSlTp(POSITION_TYPE_SELL, request, result);
                           }
                        }
                     }
                     
                     // Only reopen one position per tick to avoid multiple entries
                     break;
                  }
               }
            }
         }
      }
   }
}
//+------------------------------------------------------------------+
//| Verify if the user has access                                    |
//+------------------------------------------------------------------+
bool VerifyAccess()
{
   // Get current account number
   long currentAccount = AccountInfoInteger(ACCOUNT_LOGIN);
   
   // If authorized account is set to 0, use the current account
   long authorizedAccount = (g_AuthorizedAccount == 0) ? currentAccount : g_AuthorizedAccount;
   
   // Check username
   bool usernameValid = (Username == g_AuthorizedUsername);
   
   // Check account number
   bool accountValid = (currentAccount == authorizedAccount);
   
   // Check if product is expired
   bool notExpired = (TimeCurrent() < g_ExpiryDate);
   
   // Log verification details
   Print("Verification details:");
   Print("Current time: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
   Print("Expiry date: ", TimeToString(g_ExpiryDate, TIME_DATE|TIME_SECONDS));
   Print("Username match: ", usernameValid ? "Yes" : "No");
   Print("Account match: ", accountValid ? "Yes" : "No");
   Print("Product active: ", notExpired ? "Yes" : "No");
   
   // All conditions must be met for verification to pass
   return (usernameValid && accountValid && notExpired);
}
//+------------------------------------------------------------------+