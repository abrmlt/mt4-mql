/**
 * Snowroller - Pyramiding Grid EA
 *
 * @see 7bit Strategy:   http://www.forexfactory.com/showthread.php?t=226059&page=999
 *      7bit Journal:    http://www.forexfactory.com/showthread.php?t=239717&page=999
 *      7bit Code base:  http://sites.google.com/site/prof7bit/snowball
 *
 * @see Different pyramiding schemes:  http://www.actionforex.com/articles-library/money-management-articles/pyramiding:-a-risky-strategy-200603035356/
 * @see Schwager about pyramiding:     http://www.forexjournal.com/fx-education/money-management/450-pyramiding-and-the-management-of-profitable-trades.html
 */
#include <stdlib.mqh>
#include <win32api.mqh>


#define STATUS_WAITING        0           // m�gliche Sequenzstatus-Werte
#define STATUS_PROGRESSING    1
#define STATUS_FINISHED       2
#define STATUS_DISABLED       3


int Strategy.Id = 103;                    // eindeutige ID der Strategie (Bereich 101-1023)


//////////////////////////////////////////////////////////////// Externe Parameter ////////////////////////////////////////////////////////////////

extern int    GridSize                       = 20;
extern double LotSize                        = 0.1;
extern string StartCondition                 = "";          // {LimitValue}
extern color  Color.Breakeven                = Magenta;
extern string ______________________________ = "==== Sequence to Manage =============";
extern string Sequence.ID                    = "";

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


int      intern.GridSize;                                   // Input-Parameter sind nicht statisch. Werden sie aus einer Preset-Datei geladen,
double   intern.LotSize;                                    // werden sie bei REASON_CHARTCHANGE mit den obigen Default-Werten �berschrieben.
string   intern.StartCondition;                             // Um dies zu verhindern, werden sie in deinit() in intern.* zwischengespeichert
color    intern.Color.Breakeven;                            // und in init() wieder daraus restauriert.
string   intern.Sequence.ID;

int      status = STATUS_WAITING;

int      sequenceId;
string   sequenceSymbol;                                    // f�r Restart
datetime sequenceStartup;                                   // f�r Restart
datetime sequenceShutdown;                                  // f�r Restart

double   Entry.limit;
double   Entry.lastBid;

double   grid.base;
int      grid.level;                                        // aktueller Grid-Level
int      grid.maxLevelLong;                                 // maximal erreichter Long-Level
int      grid.maxLevelShort;                                // maximal erreichter Short-Level

int      grid.stops;                                        // Anzahl der bisher getriggerten Stops
double   grid.stopsPL;                                      // P/L der getriggerten Stops
double   grid.finishedPL;                                   // P/L sonstiger geschlossener Positionen (Sequenzende)
double   grid.floatingPL;                                   // P/L offener Positionen
double   grid.totalPL;                                      // Gesamt-P/L der Sequenz (stopsPL + finishedPL + floatingPL)
double   grid.valueAtRisk;                                  // aktuelles maximales Risiko

double   grid.maxProfitLoss;                                // maximal erreichter Gesamtprofit
datetime grid.maxProfitLoss.time;                           // Zeitpunkt von grid.maxProfitLoss
double   grid.maxDrawdown;                                  // maximal erreichter Drawdown
datetime grid.maxDrawdown.time;                             // Zeitpunkt von grid.maxDrawdown
double   grid.breakevenLong;
double   grid.breakevenShort;

int      orders.ticket      [];
int      orders.level       [];                             // Grid-Level der Order
int      orders.pendingType [];                             // Pending-Orderdaten (falls zutreffend)
datetime orders.pendingTime [];
double   orders.pendingPrice[];
int      orders.type        [];
datetime orders.openTime    [];
double   orders.openPrice   [];
datetime orders.closeTime   [];
double   orders.closePrice  [];
double   orders.stopLoss    [];
double   orders.swap        [];
double   orders.commission  [];
double   orders.profit      [];
string   orders.comment     [];

string   str.LotSize             = "";                      // Speichervariablen f�r schnellere Abarbeitung von ShowStatus()
string   str.Entry.limit         = "";
string   str.grid.base           = "";
string   str.grid.maxLevelLong   = "0";
string   str.grid.maxLevelShort  = "0";
string   str.grid.stops          = "0 stops";
string   str.grid.stopsPL        = "0.00";
string   str.grid.totalPL        = "0.00";
string   str.grid.valueAtRisk    = "0.00";
string   str.grid.maxProfitLoss  = "0.00";
string   str.grid.maxDrawdown    = "0.00";
string   str.grid.breakevenLong  = "-";
string   str.grid.breakevenShort = "-";

color    CLR_LONG  = Blue;
color    CLR_SHORT = Red;
color    CLR_CLOSE = Orange;

bool     firstTick = true;


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int init() {
   if (IsError(onInit(T_EXPERT)))
      return(ShowStatus(true));

   /*
   Zuerst wird die aktuelle Sequenz-ID bestimmt, dann deren Konfiguration geladen und validiert. Zum Schlu� werden die Daten der ggf. laufenden Sequenz restauriert.
   Es gibt 4 unterschiedliche init()-Szenarien:

   (1.1) Recompilation:                    keine internen Daten vorhanden, evt. externe Referenz vorhanden (im Chart)
   (1.2) Neustart des EA, evt. im Tester:  keine internen Daten vorhanden, evt. externe Referenz vorhanden (im Chart)
   (1.3) Parameter�nderung:                alle internen Daten vorhanden, externe Referenz unn�tig
   (1.4) Timeframe-Wechsel:                alle internen Daten vorhanden, externe Referenz unn�tig
   */

   // (1) Sind keine internen Daten vorhanden, befinden wir uns in Szenario 1.1 oder 1.2.
   if (sequenceId == 0) {

      // (1.1) Recompilation ----------------------------------------------------------------------------------------------------------------------------------
      if (UninitializeReason() == REASON_RECOMPILE) {
         if (RestoreChartSequenceId())                               // falls externe Referenz vorhanden: restaurieren und validieren
            if (RestoreStatus())                                     // ohne externe Referenz weiter in (1.2)
               if (ValidateConfiguration())
                  SynchronizeStatus();
      }

      // (1.2) Neustart ---------------------------------------------------------------------------------------------------------------------------------------
      if (sequenceId == 0) {
         if (IsInputSequenceId()) {                                  // Zuerst eine ausdr�cklich angegebene Sequenz-ID restaurieren...
            if (RestoreInputSequenceId())
               if (RestoreStatus())
                  if (ValidateConfiguration())
                     SynchronizeStatus();
         }
         else if (RestoreChartSequenceId()) {                        // ...dann ggf. eine im Chart gespeicherte Sequenz-ID restaurieren...
            if (RestoreStatus())
               if (ValidateConfiguration())
                  SynchronizeStatus();
         }
         else if (RestoreRunningSequenceId()) {                      // ...dann ID aus laufender Sequenz restaurieren.
            if (RestoreStatus())
               if (ValidateConfiguration())
                  SynchronizeStatus();
         }
         else if (ValidateConfiguration()) {                         // Zum Schlu� neue Sequenz anlegen.
            sequenceId = CreateSequenceId();
            if (StartCondition != "")                                // Ohne StartCondition erfolgt sofortiger Einstieg, in diesem Fall wird der
               SaveStatus();                                         // Status erst nach Sicherheitsabfrage in StartSequence() gespeichert.
         }
      }
      ClearChartSequenceId();
   }

   // (1.3) Parameter�nderung ---------------------------------------------------------------------------------------------------------------------------------
   else if (UninitializeReason() == REASON_PARAMETERS) {             // alle internen Daten sind vorhanden
      // TODO: die manuelle Sequence.ID kann ge�ndert worden sein
      if (ValidateConfiguration())
         SaveStatus();
   }

   // (1.4) Timeframewechsel ----------------------------------------------------------------------------------------------------------------------------------
   else if (UninitializeReason() == REASON_CHARTCHANGE) {
      GridSize         = intern.GridSize;                            // Alle internen Daten sind vorhanden, es werden nur die nicht-statischen
      LotSize          = intern.LotSize;                             // Inputvariablen restauriert.
      StartCondition   = intern.StartCondition;
      Color.Breakeven  = intern.Color.Breakeven;
      Sequence.ID      = intern.Sequence.ID;
   }

   // ---------------------------------------------------------------------------------------------------------------------------------------------------------
   else catch("init(1)   unknown init() scenario", ERR_RUNTIME_ERROR);


   // (2) Status anzeigen
   ShowStatus(true);
   if (IsLastError())
      return(last_error);


   // (3) ggf. EA's aktivieren
   int reasons1[] = { REASON_REMOVE, REASON_CHARTCLOSE, REASON_APPEXIT };
   if (IntInArray(UninitializeReason(), reasons1)) /*&&*/ if (!IsExpertEnabled())
      SwitchExperts(true);                                        // TODO: Bug, wenn mehrere EA's den EA-Modus gleichzeitig einschalten


   // (4) nicht auf den n�chsten Tick warten (au�er bei REASON_CHARTCHANGE oder REASON_ACCOUNT)
   int reasons2[] = { REASON_REMOVE, REASON_CHARTCLOSE, REASON_APPEXIT, REASON_PARAMETERS, REASON_RECOMPILE };
   if (IntInArray(UninitializeReason(), reasons2)) /*&&*/ if (!IsTesting())
      SendTick(false);

   return(catch("init(2)"));
}


/**
 * Deinitialisierung
 *
 * @return int - Fehlerstatus
 */
int deinit() {
   if (IsError(onDeinit()))
      return(last_error);

   if (UninitializeReason() == REASON_CHARTCHANGE) {
      // Input-Parameter sind nicht statisch: f�r's n�chste init() in intern.* zwischenspeichern
      intern.GridSize         = GridSize;
      intern.LotSize          = LotSize;
      intern.StartCondition   = StartCondition;
      intern.Color.Breakeven  = Color.Breakeven;
      intern.Sequence.ID      = Sequence.ID;
      return(catch("deinit(1)"));
   }

   bool isConfigFile = IsFile(TerminalPath() + ifString(IsTesting(), "\\tester", "\\experts") +"\\files\\presets\\SR."+ sequenceId +".set");

   if (isConfigFile) {                                            // Ohne Config-Datei wurde Sequenz manuell abgebrochen und nicht gestartet.
      if (UpdateStatus())                                         // Eine abgebrochene Sequenz braucht weder gespeichert noch restauriert zu werden.
         SaveStatus();

      if (UninitializeReason()==REASON_CHARTCLOSE || UninitializeReason()==REASON_RECOMPILE)
         StoreChartSequenceId();
   }
   return(catch("deinit(2)"));
}


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   if (status==STATUS_FINISHED || status==STATUS_DISABLED)
      return(last_error);

   static int last.grid.level;


   if (__SCRIPT__ == "SnowRoller.2") {
      last_error = ERR_CANCELLED_BY_USER;
   }
   else {
      // (1) Sequenz wartet entweder auf Startsignal...
      if (status == STATUS_WAITING) {
         if (IsStartSignal())                    StartSequence();
      }

      // (2) ...oder l�uft: Status pr�fen und Orders aktualisieren
      else if (UpdateStatus()) {
         if      (IsProfitTargetReached())       FinishSequence();
         else if (last.grid.level != grid.level) UpdatePendingOrders();
      }
   }

   last.grid.level = grid.level;
   firstTick       = false;


   // (3) Status anzeigen
   ShowStatus();


   if (IsLastError())
      return(last_error);
   return(catch("onTick()"));
}


/**
 * Pr�ft und synchronisiert die im EA gespeicherten Orders mit den aktuellen Laufzeitdaten.
 *
 * @return bool - Erfolgsstatus
 */
bool UpdateStatus() {
   if (IsLastError() || status==STATUS_DISABLED)
      return(false);

   grid.floatingPL = 0;

   bool wasPending, isClosed, closedByStop, breakevenUpdated;
   int  orders = ArraySize(orders.ticket);

   for (int i=0; i < orders; i++) {
      if (orders.closeTime[i] == 0) {                                // Ticket pr�fen, wenn es beim letzten Aufruf noch offen war
         if (!OrderSelectByTicket(orders.ticket[i], "UpdateStatus(1)"))
            return(false);

         wasPending = orders.type[i] == OP_UNDEFINED;                // ob die Order beim letzten Aufruf "pending" war

         if (wasPending) {
            // beim letzten Aufruf Pending-Order
            if (OrderType() != orders.pendingType[i]) {              // Order wurde ausgef�hrt
               orders.type      [i] = OrderType();
               orders.openTime  [i] = OrderOpenTime();
               orders.openPrice [i] = OrderOpenPrice();
               orders.swap      [i] = OrderSwap();
               orders.commission[i] = OrderCommission();
               orders.profit    [i] = OrderProfit();

               grid.level        += MathSign(orders.level[i]);
               grid.maxLevelLong  = MathMax(grid.level, grid.maxLevelLong ) +0.1;                        // (int) double
               grid.maxLevelShort = MathMin(grid.level, grid.maxLevelShort) -0.1; SS.Grid.MaxLevel();    // (int) double
               grid.valueAtRisk   = grid.stopsPL - MathAbs(grid.level) * GridSize * PipValue(LotSize); SS.Grid.ValueAtRisk();
               breakevenUpdated   = Grid.UpdateBreakeven();

               if (!ChartMarker.OrderFilled(i)) return(false);
            }
         }
         else {
            // beim letzten Aufruf offene Position
            orders.swap      [i] = OrderSwap();
            orders.commission[i] = OrderCommission();
            orders.profit    [i] = OrderProfit();
         }

         isClosed = OrderCloseTime() != 0;                            // ob die Order jetzt geschlossen ist

         if (!isClosed) {                                            // weiterhin offene Order
            grid.floatingPL += OrderSwap() + OrderCommission() + OrderProfit();
         }
         else {                                                      // jetzt geschlossenes Ticket: gestrichene Order oder geschlossene Position
            orders.closeTime [i] = OrderCloseTime();                 // Bei Spikes kann eine Pending-Order ausgef�hrt *und* bereits geschlossen sein.
            orders.closePrice[i] = OrderClosePrice();

            if (orders.type[i] != OP_UNDEFINED) {                    // geschlossene Position
               if (!ChartMarker.PositionClosed_A(orders.ticket[i], Digits, CLR_CLOSE))
                  return(_false(SetLastError(stdlib_PeekLastError())));

               if (StringIEndsWith(orders.comment[i], "[sl]")) closedByStop = true;
               else if (orders.type[i] == OP_BUY )             closedByStop = LE(orders.closePrice[i], orders.stopLoss[i]);
               else if (orders.type[i] == OP_SELL)             closedByStop = GE(orders.closePrice[i], orders.stopLoss[i]);
               else                                            closedByStop = false;

               if (closedByStop) {                                   // getriggerter Stop
                  grid.level      -= MathSign(orders.level[i]);
                  grid.stops++;
                  grid.stopsPL    += orders.swap[i] + orders.commission[i] + orders.profit[i]; SS.Grid.Stops();
                  grid.valueAtRisk = grid.stopsPL - MathAbs(grid.level) * GridSize * PipValue(LotSize); SS.Grid.ValueAtRisk();
               }
               else {                                                // bei Sequenzende geschlossen (ggf. durch Tester)
                  grid.finishedPL += orders.swap[i] + orders.commission[i] + orders.profit[i];
               }
               breakevenUpdated = Grid.UpdateBreakeven();
            }
         }
      }
   }
   grid.totalPL = grid.stopsPL + grid.finishedPL + grid.floatingPL; SS.Grid.TotalPL();

   if (grid.totalPL > grid.maxProfitLoss) {
      grid.maxProfitLoss      = grid.totalPL; SS.Grid.MaxProfitLoss();
      grid.maxProfitLoss.time = TimeCurrent();
   }
   else if (grid.totalPL < grid.maxDrawdown) {
      grid.maxDrawdown      = grid.totalPL; SS.Grid.MaxDrawdown();
      grid.maxDrawdown.time = TimeCurrent();
   }


   if (!breakevenUpdated) /*&&*/ if (grid.breakevenLong > 0) {
      HandleEvent(EVENT_BAR_OPEN);                                   // BarOpen-Event verarbeiten, wenn Breakeven initialisiert ist und nicht bereits aktualisiert wurde
   }

   return(IsNoError(catch("UpdateStatus(2)")));
}


/**
 * Handler f�r BarOpen-Events.
 *
 * @param int data[] - eventspezifische Informationen
 *
 * @return int - Fehlerstatus
 */
int onBarOpen(int data[]) {
   Grid.DrawBreakeven();
   return(catch("onBarOpen()"));
}


/**
 * Signalgeber f�r StartSequence(). Wurde kein Limit angegeben (StartCondition = 0 oder ""), gibt die Funktion ebenfalls TRUE zur�ck.
 *
 * @return bool - ob die konfigurierte StartCondition erf�llt ist
 */
bool IsStartSignal() {
   // Das Limit ist erreicht, wenn der Bid-Preis es seit dem letzten Tick ber�hrt oder gekreuzt hat.
   if (EQ(Entry.limit, 0))                                           // kein Limit definiert => immer TRUE
      return(true);

   if (EQ(Bid, Entry.limit) || EQ(Entry.lastBid, Entry.limit)) {     // Bid liegt oder lag beim letzten Tick exakt auf dem Limit
      Entry.lastBid = Entry.limit;                                   // Tritt w�hrend der weiteren Verarbeitung des Ticks ein behandelbarer Fehler auf, wird durch
      return(true);                                                  // Entry.lastBid = Entry.limit das Limit, einmal getriggert, nachfolgend immer wieder getriggert.
   }

   static bool lastBid.init = false;

   if (EQ(Entry.lastBid, 0)) {                                       // Entry.lastBid mu� initialisiert sein => ersten Aufruf �berspringen und Status merken,
      lastBid.init = true;                                           // um firstTick bei erstem tats�chlichen Test gegen Entry.lastBid auf TRUE zur�ckzusetzen
   }
   else {
      if (LT(Entry.lastBid, Entry.limit)) {
         if (GT(Bid, Entry.limit)) {                                 // Bid hat Limit von unten nach oben gekreuzt
            Entry.lastBid = Entry.limit;
            return(true);
         }
      }
      else if (LT(Bid, Entry.limit)) {                               // Bid hat Limit von oben nach unten gekreuzt
         Entry.lastBid = Entry.limit;
         return(true);
      }
      if (lastBid.init) {
         lastBid.init = false;
         firstTick    = true;                                        // firstTick nach erstem tats�chlichen Test gegen Entry.lastBid auf TRUE zur�ckzusetzen
      }
   }

   Entry.lastBid = Bid;
   return(false);
}


/**
 * Beginnt eine neue Trade-Sequenz.
 *
 * @return bool - Erfolgsstatus
 */
bool StartSequence() {
   if (IsLastError() || status==STATUS_DISABLED)
      return(false);

   if (firstTick) {                                                  // Sicherheitsabfrage, wenn der erste Tick sofort einen Trade triggert
      if (!IsTesting()) {                                            // jedoch nicht im Tester
         ForceSound("notify.wav");
         int button = ForceMessageBox(ifString(!IsDemo(), "- Live Account -\n\n", "") +"Do you really want to start a new trade sequence now?", __SCRIPT__ +" - StartSequence()", MB_ICONQUESTION|MB_OKCANCEL);
         if (button != IDOK)
            return(_false(SetLastError(ERR_CANCELLED_BY_USER), catch("StartSequence(1)")));
      }
   }

   // Grid-Base definieren
   grid.base = ifDouble(EQ(Entry.limit, 0), Bid, Entry.limit); SS.Grid.Base();

   // Stop-Orders in den Markt legen
   if (!UpdatePendingOrders())
      return(false);

   // Status �ndern und Sequenz extern speichern
   status = STATUS_PROGRESSING;

   return(IsNoError(catch("StartSequence(2)")));
}


/**
 * Setzt dem Grid-Level entsprechend neue bzw. fehlende PendingOrders.
 *
 * @return bool - Erfolgsstatus
 */
bool UpdatePendingOrders() {
   if (IsLastError() || status==STATUS_DISABLED)
      return(false);

   int  nextLevel;
   bool orderExists, ordersChanged;

   if (grid.level > 0) {
      nextLevel = grid.level + 1;

      // unn�tige Pending-Orders l�schen
      for (int i=ArraySize(orders.ticket)-1; i >= 0; i--) {
         if (orders.type[i]==OP_UNDEFINED) /*&&*/ if (orders.closeTime[i]==0) {  // if (isPending && !isClosed)
            if (orders.level[i] == nextLevel) {
               orderExists = true;
               continue;
            }
            if (!Grid.DeleteOrder(orders.ticket[i]))
               return(false);
            ordersChanged = true;
         }
      }
      // wenn n�tig, neue Stop-Order in den Markt legen
      if (!orderExists) {
         if (!Grid.AddOrder(OP_BUYSTOP, nextLevel))
            return(false);
         ordersChanged = true;
      }
   }

   else if (grid.level < 0) {
      nextLevel = grid.level - 1;

      // unn�tige Pending-Orders l�schen
      for (i=ArraySize(orders.ticket)-1; i >= 0; i--) {
         if (orders.type[i]==OP_UNDEFINED) /*&&*/ if (orders.closeTime[i]==0) {  // if (isPending && !isClosed)
            if (orders.level[i] == nextLevel) {
               orderExists = true;
               continue;
            }
            if (!Grid.DeleteOrder(orders.ticket[i]))
               return(false);
            ordersChanged = true;
         }
      }
      // wenn n�tig, neue Stop-Order in den Markt legen
      if (!orderExists) {
         if (!Grid.AddOrder(OP_SELLSTOP, nextLevel))
            return(false);
         ordersChanged = true;
      }
   }

   else /*(grid.level == 0)*/ {
      bool buyOrderExists, sellOrderExists;

      // unn�tige Pending-Orders l�schen
      for (i=ArraySize(orders.ticket)-1; i >= 0; i--) {
         if (orders.type[i]==OP_UNDEFINED) /*&&*/ if (orders.closeTime[i]==0) {  // if (isPending && !isClosed)
            if (orders.level[i] == 1) {
               buyOrderExists = true;
               continue;
            }
            if (orders.level[i] == -1) {
               sellOrderExists = true;
               continue;
            }
            if (!Grid.DeleteOrder(orders.ticket[i]))
               return(false);
            ordersChanged = true;
         }
      }
      // wenn n�tig neue Stop-Orders in den Markt legen
      if (!buyOrderExists) {
         if (!Grid.AddOrder(OP_BUYSTOP, 1))
            return(false);
         ordersChanged = true;
      }
      if (!sellOrderExists) {
         if (!Grid.AddOrder(OP_SELLSTOP, -1))
            return(false);
         ordersChanged = true;
      }
   }

   if (ordersChanged)                                                            // nach jeder �nderung Status speichern
      if (!SaveStatus())
         return(false);

   return(IsNoError(catch("UpdatePendingOrders()")));
}


/**
 * Legt die angegebene Stop-Order in den Markt und f�gt den Grid-Arrays deren Daten hinzu.
 *
 * @param  int type  - Ordertyp: OP_BUYSTOP | OP_SELLSTOP
 * @param  int level - Gridlevel der Order
 *
 * @return bool - Erfolgsstatus
 */
bool Grid.AddOrder(int type, int level) {
   if (IsLastError() || status==STATUS_DISABLED)
      return(false);

   // Order in den Markt legen
   int ticket = PendingStopOrder(type, level);
   if (ticket == -1)
      return(false);

   // Daten speichern
   if (!Grid.PushTicket(ticket))
      return(false);

   return(IsNoError(catch("Grid.AddOrder()")));
}


/**
 * Streicht die angegebene Order beim Broker und entfernt sie aus den Datenarrays des Grids.
 *
 * @param  int ticket - Orderticket
 *
 * @return bool - Erfolgsstatus
 */
bool Grid.DeleteOrder(int ticket) {
   if (IsLastError() || status==STATUS_DISABLED)
      return(false);

   if (!OrderDeleteEx(ticket, CLR_NONE))
      return(_false(SetLastError(stdlib_PeekLastError())));

   if (!Grid.DropTicket(ticket))
      return(false);

   return(IsNoError(catch("Grid.DeleteOrder()")));
}


/**
 * F�gt das angegebene Ticket den Datenarrays des Grids hinzu, ohne den Online-Satus der Order beim Broker zu �ndern.
 *
 * @param  int ticket - Orderticket
 *
 * @return bool - Erfolgsstatus
 */
bool Grid.PushTicket(int ticket) {
   if (!OrderSelectByTicket(ticket, "Grid.PushTicket(1)"))
      return(false);

   // Arrays vergr��ern und Daten speichern
   int size = ArraySize(orders.ticket);
   ResizeArrays(size+1);

   orders.ticket      [size] = OrderTicket();
   orders.level       [size] = ifInt(IsLongTradeOperation(OrderType()), 1, -1) * OrderMagicNumber()>>14 & 0xFF;   // 8 Bits (Bits 15-22) => grid.level

   orders.pendingType [size] = ifInt   ( IsPendingTradeOperation(OrderType()), OrderType(), OP_UNDEFINED);
   orders.pendingTime [size] = ifInt   ( IsPendingTradeOperation(OrderType()), OrderOpenTime(),        0);
   orders.pendingPrice[size] = ifDouble( IsPendingTradeOperation(OrderType()), OrderOpenPrice(),       0);

   orders.type        [size] = ifInt   (!IsPendingTradeOperation(OrderType()), OrderType(), OP_UNDEFINED);
   orders.openTime    [size] = ifInt   (!IsPendingTradeOperation(OrderType()), OrderOpenTime(),        0);
   orders.openPrice   [size] = ifDouble(!IsPendingTradeOperation(OrderType()), OrderOpenPrice(),       0);

   orders.closeTime   [size] = OrderCloseTime();
   orders.closePrice  [size] = OrderClosePrice();
   orders.stopLoss    [size] = OrderStopLoss();
   orders.swap        [size] = OrderSwap();
   orders.commission  [size] = OrderCommission();
   orders.profit      [size] = OrderProfit();
   orders.comment     [size] = OrderComment();

   return(IsNoError(catch("Grid.PushTicket(2)")));
}


/**
 * Entfernt das angegebene Ticket aus den Datenarrays des Grids, ohne den Online-Satus der Order beim Broker zu �ndern.
 *
 * @param  int ticket - Orderticket
 *
 * @return bool - Erfolgsstatus
 */
bool Grid.DropTicket(int ticket) {
   // Position in Datenarrays bestimmen
   int i = ArraySearchInt(ticket, orders.ticket);
   if (i == -1)
      return(_false(catch("Grid.DropTicket(1)   #"+ ticket +" not found in grid arrays", ERR_RUNTIME_ERROR)));

   // Eintr�ge entfernen
   int size = ArraySize(orders.ticket);

   if (i < size-1) {                                                 // wenn das zu entfernende Element nicht das Letzte ist
      ArrayCopy(orders.ticket,       orders.ticket,       i, i+1);
      ArrayCopy(orders.level,        orders.level,        i, i+1);
      ArrayCopy(orders.pendingType,  orders.pendingType,  i, i+1);
      ArrayCopy(orders.pendingTime,  orders.pendingTime,  i, i+1);
      ArrayCopy(orders.pendingPrice, orders.pendingPrice, i, i+1);
      ArrayCopy(orders.type,         orders.type,         i, i+1);
      ArrayCopy(orders.openTime,     orders.openTime,     i, i+1);
      ArrayCopy(orders.openPrice,    orders.openPrice,    i, i+1);
      ArrayCopy(orders.closeTime,    orders.closeTime,    i, i+1);
      ArrayCopy(orders.closePrice,   orders.closePrice,   i, i+1);
      ArrayCopy(orders.stopLoss,     orders.stopLoss,     i, i+1);
      ArrayCopy(orders.swap,         orders.swap,         i, i+1);
      ArrayCopy(orders.commission,   orders.commission,   i, i+1);
      ArrayCopy(orders.profit,       orders.profit,       i, i+1);
      ArrayCopy(orders.comment,      orders.comment,      i, i+1);
   }
   ResizeArrays(size-1);

   return(IsNoError(catch("Grid.DropTicket(2)")));
}


/**
 * Ersetzt die Arraydaten des angegebenen Tickets mit den aktuellen Online-Daten.
 *
 * @param  int ticket - Orderticket
 *
 * @return bool - Erfolgsstatus
 */
bool Grid.ReplaceTicket(int ticket) {
   // Position in Datenarrays bestimmen
   int i = ArraySearchInt(ticket, orders.ticket);
   if (i == -1)
      return(_false(catch("Grid.ReplaceTicket(1)   #"+ ticket +" not found in grid arrays", ERR_RUNTIME_ERROR)));

   if (!OrderSelectByTicket(ticket, "Grid.ReplaceTicket(2)"))
      return(false);

   orders.ticket      [i] = OrderTicket();
   orders.level       [i] = ifInt(IsLongTradeOperation(OrderType()), 1, -1) * OrderMagicNumber()>>14 & 0xFF;            // 8 Bits (Bits 15-22) => grid.level

   orders.pendingType [i] = ifInt   ( IsPendingTradeOperation(OrderType()), OrderType(),      orders.pendingType [i]);  // Pending-Orderdaten ggf. bewahren
   orders.pendingTime [i] = ifInt   ( IsPendingTradeOperation(OrderType()), OrderOpenTime(),  orders.pendingTime [i]);
   orders.pendingPrice[i] = ifDouble( IsPendingTradeOperation(OrderType()), OrderOpenPrice(), orders.pendingPrice[i]);

   orders.type        [i] = ifInt   (!IsPendingTradeOperation(OrderType()), OrderType(), OP_UNDEFINED);
   orders.openTime    [i] = ifInt   (!IsPendingTradeOperation(OrderType()), OrderOpenTime(),        0);
   orders.openPrice   [i] = ifDouble(!IsPendingTradeOperation(OrderType()), OrderOpenPrice(),       0);

   orders.closeTime   [i] = OrderCloseTime();
   orders.closePrice  [i] = OrderClosePrice();
   orders.stopLoss    [i] = OrderStopLoss();
   orders.swap        [i] = OrderSwap();
   orders.commission  [i] = OrderCommission();
   orders.profit      [i] = OrderProfit();
   orders.comment     [i] = OrderComment();

   return(IsNoError(catch("Grid.ReplaceTicket(3)")));
}


/**
 * Legt eine Stop-Order in den Markt.
 *
 * @param  int type  - Ordertyp: OP_BUYSTOP | OP_SELLSTOP
 * @param  int level - Gridlevel der Order
 *
 * @return int - Ticket der Order oder -1, falls ein Fehler auftrat
 */
int PendingStopOrder(int type, int level) {
   if (IsLastError() || status==STATUS_DISABLED)
      return(-1);

   if (type == OP_BUYSTOP) {
      if (level <= 0) return(_int(-1, catch("PendingStopOrder(1)   illegal parameter level = "+ level +" for "+ OperationTypeDescription(type), ERR_INVALID_FUNCTION_PARAMVALUE)));
   }
   else if (type == OP_SELLSTOP) {
      if (level >= 0) return(_int(-1, catch("PendingStopOrder(2)   illegal parameter level = "+ level +" for "+ OperationTypeDescription(type), ERR_INVALID_FUNCTION_PARAMVALUE)));
   }
   else               return(_int(-1, catch("PendingStopOrder(3)   illegal parameter type = "+ type, ERR_INVALID_FUNCTION_PARAMVALUE)));

   double stopPrice   = grid.base +                       level * GridSize * Pips;
   double stopLoss    = stopPrice + ifDouble(level<0, GridSize, -GridSize) * Pips;
   int    magicNumber = CreateMagicNumber(level);
   string comment     = StringConcatenate("SR.", sequenceId, ".", NumberToStr(level, "+."));

   int ticket = OrderSendEx(Symbol(), type, LotSize, stopPrice, NULL, stopLoss, NULL, comment, magicNumber, NULL, ifInt(level > 0, CLR_LONG, CLR_SHORT));
   if (ticket == -1)
      SetLastError(stdlib_PeekLastError());

   if (IsError(catch("PendingStopOrder(4)")))
      return(-1);
   return(ticket);
}


/**
 * Ob der konfigurierte TakeProfit-Level erreicht oder �berschritten wurde.
 *
 * @return bool
 */
bool IsProfitTargetReached() {
   return(false);
}


/**
 * Schlie�t alle offenen Positionen der Sequenz und l�scht verbleibende PendingOrders.
 *
 * @return bool - Erfolgsstatus
 */
bool FinishSequence() {
   if (IsLastError() || status==STATUS_DISABLED)
      return(false);

   if (firstTick) {                                                  // Sicherheitsabfrage, wenn der erste Tick sofort einen Trade triggert
      if (!IsTesting()) {                                            // jedoch nicht im Tester
         ForceSound("notify.wav");
         int button = ForceMessageBox(ifString(!IsDemo(), "- Live Account -\n\n", "") +"Do you really want to finish the sequence now?", __SCRIPT__ +" - FinishSequence()", MB_ICONQUESTION|MB_OKCANCEL);
         if (button != IDOK)
            return(_false(SetLastError(ERR_CANCELLED_BY_USER), catch("FinishSequence(1)")));
      }
   }
   return(IsNoError(catch("FinishSequence(2)")));
}


/**
 * Generiert einen Wert f�r OrderMagicNumber() f�r den angegebenen Gridlevel.
 *
 * @param  int level - Gridlevel
 *
 * @return int - MagicNumber oder -1, falls ein Fehler auftrat
 */
int CreateMagicNumber(int level) {
   if (sequenceId < 1000) return(_int(-1, catch("CreateMagicNumber(1)   illegal sequenceId = "+ sequenceId, ERR_RUNTIME_ERROR)));
   if (level == 0)        return(_int(-1, catch("CreateMagicNumber(2)   illegal parameter level = "+ level, ERR_INVALID_FUNCTION_PARAMVALUE)));

   // F�r bessere Obfuscation ist die Reihenfolge der Werte [ea,level,sequence] und nicht [ea,sequence,level]. Dies w�ren aufeinander folgende Werte.
   int ea       = Strategy.Id & 0x3FF << 22;                         // 10 bit (Bits gr��er 10 l�schen und auf 32 Bit erweitern) | in MagicNumber: Bits 23-32
   level        = MathAbs(level) +0.1;                               // (int) double: Wert in MagicNumber ist immer positiv
   level        = level & 0xFF << 14;                                //  8 bit (Bits gr��er 8 l�schen und auf 22 Bit erweitern)  | in MagicNumber: Bits 15-22
   int sequence = sequenceId  & 0x3FFF;                              // 14 bit (Bits gr��er 14 l�schen                           | in MagicNumber: Bits  1-14

   return(ea + level + sequence);
}


/**
 * Zeigt den aktuellen Status der Sequenz an.
 *
 * @param  bool init - ob der Aufruf innerhalb der init()-Funktion erfolgt (default: FALSE)
 *
 * @return int - Fehlerstatus
 */
int ShowStatus(bool init=false) {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return(last_error);

   int error = last_error;                                           // bei Funktionseintritt bereits existierenden Fehler zwischenspeichern

   static string msg, str.error;

   if (IsLastError()) {
      status    = STATUS_DISABLED;
      str.error = StringConcatenate("  [", ErrorDescription(last_error), "]");
   }

   switch (status) {
      case STATUS_WAITING:     msg = StringConcatenate(":  sequence ", sequenceId, " waiting");
                               if (StringLen(StartCondition) > 0)
                                  msg = StringConcatenate(msg, " for crossing of ", str.Entry.limit);                                                                                     break;
      case STATUS_PROGRESSING: msg = StringConcatenate(":  sequence ", sequenceId, " progressing at level ", grid.level, "  (", str.grid.maxLevelLong, "/", str.grid.maxLevelShort, ")"); break;
      case STATUS_FINISHED:    msg = StringConcatenate(":  sequence ", sequenceId, " finished at level ", grid.level, "  (", str.grid.maxLevelLong, "/", str.grid.maxLevelShort, ")");    break;
      case STATUS_DISABLED:    msg = StringConcatenate(":  sequence ", sequenceId, " disabled", str.error);                                                                               break;
      default:
         return(catch("ShowStatus(1)   illegal sequence status = "+ status, ERR_RUNTIME_ERROR));
   }

   msg = StringConcatenate(__SCRIPT__, msg,                                                                                                                NL,
                                                                                                                                                           NL,
                           "Grid:            ", GridSize, " pip @ ", str.grid.base,                                                                        NL,
                           "LotSize:         ", str.LotSize, " lot = ", DoubleToStr(GridSize * PipValue(LotSize), 2), "/stop",                             NL,
                           "Realized:       ", str.grid.stops, " = ", str.grid.stopsPL,                                                                    NL,
                           "Breakeven:   ", str.grid.breakevenLong, " / ", str.grid.breakevenShort,                                                        NL,
                           "Profit/Loss:    ", str.grid.totalPL, "  (", str.grid.maxProfitLoss, "/", str.grid.maxDrawdown, "/", str.grid.valueAtRisk, ")", NL);

   // einige Zeilen Abstand nach oben f�r Instrumentanzeige und ggf. vorhandene Legende
   Comment(StringConcatenate(NL, NL, msg));
   if (init)
      WindowRedraw();

   if (!IsError(catch("ShowStatus(2)")))
      last_error = error;                                            // bei Funktionseintritt bereits existierenden Fehler restaurieren
   return(last_error);
}


/**
 * ShowStatus(): Aktualisiert die String-Repr�sentation von LotSize.
 */
void SS.LotSize() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   str.LotSize = NumberToStr(LotSize, ".+");
}


/**
 * ShowStatus(): Aktualisiert die String-Repr�sentation von Entry.limit.
 */
void SS.Entry.Limit() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   str.Entry.limit = NumberToStr(Entry.limit, PriceFormat);
}


/**
 * ShowStatus(): Aktualisiert die String-Repr�sentation von grid.base.
 */
void SS.Grid.Base() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   str.grid.base = NumberToStr(grid.base, PriceFormat);
}


/**
 * ShowStatus(): Aktualisiert die String-Repr�sentationen von grid.MaxLevelLong und grid.MaxLevelShort.
 */
void SS.Grid.MaxLevel() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   if (grid.maxLevelLong > 0)
      str.grid.maxLevelLong = StringConcatenate("+", grid.maxLevelLong);
   str.grid.maxLevelShort = grid.maxLevelShort;
}


/**
 * ShowStatus(): Aktualisiert die String-Repr�sentationen von grid.stops und grid.stopsPL.
 */
void SS.Grid.Stops() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   str.grid.stops   = StringConcatenate(grid.stops, " stop", ifString(grid.stops==1, "", "s"));
   str.grid.stopsPL = DoubleToStr(grid.stopsPL, 2);
}


/**
 * ShowStatus(): Aktualisiert die String-Repr�sentation von grid.totalPL.
 */
void SS.Grid.TotalPL() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   str.grid.totalPL = NumberToStr(grid.totalPL, "+.2");
}


/**
 * ShowStatus(): Aktualisiert die String-Repr�sentation von grid.valueAtRisk.
 */
void SS.Grid.ValueAtRisk() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   str.grid.valueAtRisk = NumberToStr(grid.valueAtRisk, "+.2");
}


/**
 * ShowStatus(): Aktualisiert die String-Repr�sentation von grid.maxProfitLoss.
 */
void SS.Grid.MaxProfitLoss() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   str.grid.maxProfitLoss = NumberToStr(grid.maxProfitLoss, "+.2");
}


/**
 * ShowStatus(): Aktualisiert die String-Repr�sentation von grid.maxDrawdown.
 */
void SS.Grid.MaxDrawdown() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   str.grid.maxDrawdown = NumberToStr(grid.maxDrawdown, "+.2");
}


/**
 * ShowStatus(): Aktualisiert die String-Repr�sentation von grid.breakevenLong und grid.breakevenShort.
 */
void SS.Grid.Breakeven() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   str.grid.breakevenLong  = DoubleToStr(grid.breakevenLong, PipDigits);
   str.grid.breakevenShort = DoubleToStr(grid.breakevenShort, PipDigits);
}


/**
 * Berechnet die Breakeven-Werte der Sequenz.
 *
 * @return bool - Erfolgsstatus
 */
bool Grid.UpdateBreakeven() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return(true);

   // wenn floatingPL = -realizedPL, dann totalPL = 0.00      => Breakeven-Punkt auf aktueller Seite
   double distance1 = ProfitToDistance(MathAbs(grid.stopsPL + grid.finishedPL), grid.level);

   if (grid.level == 0) {                                            // realizedPL und valueAtRisk sind identisch, Abstand der Breakeven-Punkte ist gleich
      grid.breakevenLong  = grid.base + distance1*Pips;
      grid.breakevenShort = grid.base - distance1*Pips;
   }
   else {
      // wenn floatingPL = -valueAtRisk, dann totalPL = 0.00  => Breakeven-Punkt auf gegen�berliegender Seite
      double distance2 = ProfitToDistance(MathAbs(grid.valueAtRisk));

      if (grid.level > 0) {
         grid.breakevenLong  = grid.base + distance1*Pips;
         grid.breakevenShort = grid.base - distance2*Pips;
      }
      else /*(grid.level < 0)*/ {
         grid.breakevenLong  = grid.base + distance2*Pips;
         grid.breakevenShort = grid.base - distance1*Pips;
      }
   }

   Grid.DrawBreakeven();
   SS.Grid.Breakeven();
   return(true);
}


/**
 * Aktualisiert den Breakeven-Indikator.
 */
void Grid.DrawBreakeven() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;
   if (EQ(grid.breakevenLong, 0))                                                // ohne initialisiertes Breakeven sofortige R�ckkehr
      return;

   static double   last.grid.breakevenLong, last.grid.breakevenShort;            // Daten der zuletzt gezeichneten Indikatorwerte
   static datetime last.startTimeLong, last.startTimeShort, last.drawingTime;

   datetime now = TimeCurrent();

   // Trendlinien zeichnen
   if (last.drawingTime != 0) {                                                  // "SR.5609.L 1.53024 -> 1.52904 (2012.01.23 10:19:35)"
      string labelL = StringConcatenate("SR.", sequenceId, ".L ", DoubleToStr(last.grid.breakevenLong, Digits), " -> ", DoubleToStr(grid.breakevenLong, Digits), " (", TimeToStr(last.startTimeLong, TIME_DATE|TIME_MINUTES|TIME_SECONDS), ")");
      if (ObjectCreate(labelL, OBJ_TREND, 0, last.drawingTime, last.grid.breakevenLong, now, grid.breakevenLong)) {
         ObjectSet(labelL, OBJPROP_RAY  , false          );
         ObjectSet(labelL, OBJPROP_COLOR, Color.Breakeven);
         if (EQ(last.grid.breakevenLong, grid.breakevenLong)) last.startTimeLong = last.drawingTime;
         else                                                 last.startTimeLong = now;
      }
      else {
         GetLastError();                                                         // ERR_OBJECT_ALREADY_EXISTS
         ObjectSet(labelL, OBJPROP_TIME2, now);                                  // vorhandene Trendlinien werden m�glichst verl�ngert (verhindert Erzeugung unz�hliger gleicher Objekte)
      }

      string labelS = StringConcatenate("SR.", sequenceId, ".S ", DoubleToStr(last.grid.breakevenShort, Digits), " -> ", DoubleToStr(grid.breakevenShort, Digits), " (", TimeToStr(last.startTimeShort, TIME_DATE|TIME_MINUTES|TIME_SECONDS), ")");
      if (ObjectCreate(labelS, OBJ_TREND, 0, last.drawingTime, last.grid.breakevenShort, now, grid.breakevenShort)) {
         ObjectSet(labelS, OBJPROP_RAY  , false          );
         ObjectSet(labelS, OBJPROP_COLOR, Color.Breakeven);
         if (EQ(last.grid.breakevenShort, grid.breakevenShort)) last.startTimeShort = last.drawingTime;
         else                                                   last.startTimeShort = now;
      }
      else {
         GetLastError();                                                         // ERR_OBJECT_ALREADY_EXISTS
         ObjectSet(labelS, OBJPROP_TIME2, now);                                  // vorhandene Trendlinien werden m�glichst verl�ngert (verhindert Erzeugung unz�hliger gleicher Objekte)
   }
   }
   else {
      last.startTimeLong  = now;
      last.startTimeShort = now;
   }

   last.grid.breakevenLong  = grid.breakevenLong;
   last.grid.breakevenShort = grid.breakevenShort;
   last.drawingTime         = now;
}


/**
 * Berechnet den notwendigen Abstand von der Gridbasis, um den angegebenen Gewinn zu erzielen.
 *
 * @param  double profit - zu erzielender Gewinn
 * @param  int    level  - aktueller Gridlevel (Stops zwischen dem Level und dem resultierendenn Abstand werden ber�cksichtigt
 *
 * @return double - Abstand in Pips oder 0, wenn ein Fehler auftrat
 */
double ProfitToDistance(double profit, int level=0) {
   /*
   Formeln gelten f�r Sequenzstart an der Gridbasis:
   -------------------------------------------------
   gs        = GridSize
   n         = Level
   pipV(n)   = PipValue von Level n
   profit(d) = profit(exp) + profit(lin)                                         // Summe aus exponentiellem (ganzer Level) und linearem Anteil (partieller n�chster Level)


   Level des exponentiellen Anteils ermitteln:
   -------------------------------------------
   expProfit(n)   = n * (n+1)/2 * gs * pipV(1)

   =>          0 = n� + n - 2*profit/(gs*pipV(1))                                // Normalform quadratischer Gleichung

   => (n + 0.5)� = n� + n + 0.25

   => (n + 0.5)� - 0.25 - 2*profit/(gs*pipV(1)) = n� + n - 2*profit/(gs*pipV(1))

   => (n + 0.5)� - 0.25 - 2*profit/(gs*pipV(1)) = 0

   => (n + 0.5)� = 2*profit/(gs*pipV(1)) + 0.25

   => (n + 0.5)  = (2*profit/(gs*pipV(1)) + 0.25)�                               // Quadratwurzel

   =>          n = (2*profit/(gs*pipV(1)) + 0.25)� - 0.5                         // n = rationale Zahl
   */

   // TODO: Ber�cksichtigung von level integrieren

   int    gs   = GridSize;
   double pipV = PipValue(LotSize);
   int    n    = MathSqrt(2*profit/(gs*pipV) + 0.25) - 0.5 +0.000000001;         // (int) double

   /*
   Pips des linearen Anteils ermitteln:
   ------------------------------------
   linProfit(n.x) = 0.x * gs * pipV(n+1)

   =>   linProfit = linPips * pipV(n+1)

   =>   linProfit = linPips * (n+1)*pipV(1)

   =>     linPips = linProfit / ((n+1)*pipV(1))
   */
   double linProfit = profit - n * (n+1)/2 * gs * pipV;                          // verbleibender linearer Anteil am Profit
   double linPips   = linProfit / ((n+1) * pipV);

   // Gesamtdistanz berechnen
   n++;                                                                          // GridSize hinzu addieren, da der Sequenzstart erst bei Grid.Base + GridSize erfolgt
   double distance  = n * gs + linPips;

   debug("ProfitToDistance()   profit="+ DoubleToStr(profit, 2) +"  n="+ (n-1) +"  lin="+ DoubleToStr(linProfit, 2) +"  linPips="+ NumberToStr(linPips, ".+") +"  distance="+ NumberToStr(distance, ".+"));
   return(distance);
}


/**
 * Berechnet den theoretischen Profit im angegebenen Abstand von der Gridbasis.
 *
 * @param  double distance - Abstand in Pips von Grid.Base
 *
 * @return double - Profit oder 0, wenn ein Fehler auftrat
 */
double DistanceToProfit(double distance) {
   if (LE(distance, GridSize)) {
      if (LT(distance, 0))
         return(_ZERO(catch("DistanceToProfit()  invalid parameter distance = "+ NumberToStr(distance, ".+"), ERR_INVALID_FUNCTION_PARAMVALUE)));
      return(0);
   }
   /*
   d         = Distanz in Pip
   gs        = GridSize
   n         = Level
   pipV(n)   = PipValue von Level n
   profit(d) = profit(exp) + profit(lin)                             // Summe aus exponentiellem (ganzer Level) und linearem Anteil (partieller n�chster Level)

   F�r Sequenzstart an der Gridbasis gilt:
   ---------------------------------------
   Ganzer Level:      expProfit(n.0) = n * (n+1)/2 * gs * pipV(1)    // am Ende des Levels
   Partieller Level:  linProfit(n.x) =         0.x * gs * pipV(n+1)
   PipValue:          pipV(n)        = n * pipV(LotSize)

   profit(d) = expProfit((int) d) + linProfit(d % gs)
   */
   int    gs   = GridSize;
   double d    = distance - gs;                                      // GridSize von distance abziehen, da Sequenzstart erst bei Grid.Base + GridSize erfolgt
   int    n    = (d+0.000000001) / gs;
   double pipV = PipValue(LotSize);

   double expProfit = n * (n+1)/2 * gs * pipV;
   double linProfit = MathModFix(d, gs) * (n+1) * pipV;
   double profit    = expProfit + linProfit;

   //debug("DistanceToProfit()   gs="+ gs +"  d="+ d +"  n="+ n +"  exp="+ DoubleToStr(expProfit, 2) +"  lin="+ DoubleToStr(linProfit, 2) +"  profit="+ NumberToStr(profit, ".+"));
   return(profit);
}


/**
 * Ob in den Input-Parametern ausdr�cklich eine zu benutzende Sequenz-ID angegeben wurde. Hier wird nur gepr�ft,
 * ob ein Wert angegeben wurde. Die G�ltigkeit einer ID wird erst in RestoreInputSequenceId() �berpr�ft.
 *
 * @return bool
 */
bool IsInputSequenceId() {
   return(StringLen(StringTrim(Sequence.ID)) > 0);
}


/**
 * Validiert und setzt die in der Konfiguration angegebene Sequenz-ID.
 *
 * @return bool - ob eine g�ltige Sequenz-ID gefunden und restauriert wurde
 */
bool RestoreInputSequenceId() {
   if (IsInputSequenceId()) {
      string strValue = StringTrim(Sequence.ID);

      if (StringIsInteger(strValue)) {
         int iValue = StrToInteger(strValue);
         if (1000 <= iValue) /*&&*/ if (iValue <= 16383) {
            sequenceId  = iValue;
            Sequence.ID = strValue;
            return(true);
         }
      }
      catch("RestoreInputSequenceId()  Invalid input parameter Sequence.ID = \""+ Sequence.ID +"\"", ERR_INVALID_INPUT_PARAMVALUE);
   }
   return(false);
}


/**
 * Speichert die aktuelle Sequenz-ID im Chart, soda� die Sequenz sp�ter daraus restauriert werden kann.
 *
 * @return int - Fehlerstatus
 */
int StoreChartSequenceId() {
   string label = __SCRIPT__ +".sequenceId";

   if (ObjectFind(label) != -1)
      ObjectDelete(label);
   ObjectCreate(label, OBJ_LABEL, 0, 0, 0);
   ObjectSet(label, OBJPROP_XDISTANCE, -sequenceId);                 // negativer Wert (im nicht sichtbaren Bereich)

   return(catch("StoreChartSequenceId()"));
}


/**
 * Restauriert eine im Chart ggf. gespeicherte Sequenz-ID.
 *
 * @return bool - ob eine Sequenz-ID gefunden und restauriert wurde
 */
bool RestoreChartSequenceId() {
   string label = __SCRIPT__ +".sequenceId";

   if (ObjectFind(label)!=-1) /*&&*/ if (ObjectType(label)==OBJ_LABEL) {
      sequenceId = MathAbs(ObjectGet(label, OBJPROP_XDISTANCE)) +0.1;   // (int) double
      return(_true(catch("RestoreChartSequenceId(1)")));
   }
   return(_false(catch("RestoreChartSequenceId(2)")));
}


/**
 * L�scht im Chart gespeicherte Sequenzdaten.
 *
 * @return int - Fehlerstatus
 */
int ClearChartSequenceId() {
   string label = __SCRIPT__ +".sequenceId";

   if (ObjectFind(label) != -1)
      ObjectDelete(label);

   return(catch("ClearChartSequenceId()"));
}


/**
 * Restauriert die Sequenz-ID einer laufenden Sequenz.
 *
 * @return bool - ob eine laufende Sequenz gefunden und die ID restauriert wurde
 */
bool RestoreRunningSequenceId() {
   for (int i=OrdersTotal()-1; i >= 0; i--) {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))               // FALSE: w�hrend des Auslesens wurde in einem anderen Thread eine offene Order entfernt
         continue;

      if (IsMyOrder()) {
         sequenceId = OrderMagicNumber() & 0x3FFF;                   // 14 Bits (Bits 1-14) => sequenceId
         return(_true(catch("RestoreRunningSequenceId(1)")));
      }
   }
   return(_false(catch("RestoreRunningSequenceId(2)")));
}


/**
 * Ob die aktuell selektierte Order zu dieser Strategie geh�rt. Wird eine Sequenz-ID angegeben, wird zus�tzlich �berpr�ft,
 * ob die Order zur angegebenen Sequenz geh�rt.
 *
 * @param  int sequenceId - ID einer Sequenz (default: NULL)
 *
 * @return bool
 */
bool IsMyOrder(int sequenceId = NULL) {
   if (OrderSymbol() == Symbol()) {
      if (OrderMagicNumber() >> 22 == Strategy.Id) {
         if (sequenceId == NULL)
            return(true);
         return(sequenceId == OrderMagicNumber() & 0x3FFF);          // 14 Bits (Bits 1-14) => sequenceId
      }
   }
   return(false);
}


/**
 * Generiert eine neue Sequenz-ID.
 *
 * @return int - Sequenz-ID im Bereich 1000-16383 (14 bit)
 */
int CreateSequenceId() {
   MathSrand(GetTickCount());
   int id;
   while (id < 2000) {
      id = MathRand();
   }
   return(id >> 1);                                                  // Das abschlie�ende Shiften halbiert den Wert und wir wollen mindestens eine 4-stellige ID haben.
}


/**
 * Validiert die aktuelle Konfiguration.
 *
 * @return bool - ob die Konfiguration g�ltig ist
 */
bool ValidateConfiguration() {
   // GridSize
   if (GridSize < 1)                        return(_false(catch("ValidateConfiguration(1)  Invalid input parameter GridSize = "+ GridSize, ERR_INVALID_INPUT_PARAMVALUE)));

   // LotSize
   if (LE(LotSize, 0))                      return(_false(catch("ValidateConfiguration(2)  Invalid input parameter LotSize = "+ NumberToStr(LotSize, ".+"), ERR_INVALID_INPUT_PARAMVALUE)));

   double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   int error = GetLastError();
   if (IsError(error))                      return(_false(catch("ValidateConfiguration(3)   symbol=\""+ Symbol() +"\"", error)));
   if (LT(LotSize, minLot))                 return(_false(catch("ValidateConfiguration(4)   Invalid input parameter LotSize = "+ NumberToStr(LotSize, ".+") +" (MinLot="+  NumberToStr(minLot, ".+" ) +")", ERR_INVALID_INPUT_PARAMVALUE)));
   if (GT(LotSize, maxLot))                 return(_false(catch("ValidateConfiguration(5)   Invalid input parameter LotSize = "+ NumberToStr(LotSize, ".+") +" (MaxLot="+  NumberToStr(maxLot, ".+" ) +")", ERR_INVALID_INPUT_PARAMVALUE)));
   if (NE(MathModFix(LotSize, lotStep), 0)) return(_false(catch("ValidateConfiguration(6)   Invalid input parameter LotSize = "+ NumberToStr(LotSize, ".+") +" (LotStep="+ NumberToStr(lotStep, ".+") +")", ERR_INVALID_INPUT_PARAMVALUE)));
   SS.LotSize();

   // StartCondition
   StartCondition = StringReplace(StartCondition, " ", "");
   if (StringLen(StartCondition) == 0) {
      Entry.limit = 0;
   }
   else if (StringIsNumeric(StartCondition)) {
      Entry.limit = StrToDouble(StartCondition); SS.Entry.Limit();
      if (LT(Entry.limit, 0))               return(_false(catch("ValidateConfiguration(7)  Invalid input parameter StartCondition = \""+ StartCondition +"\"", ERR_INVALID_INPUT_PARAMVALUE)));
      if (EQ(Entry.limit, 0))
         StartCondition = "";
   }
   else                                     return(_false(catch("ValidateConfiguration(8)  Invalid input parameter StartCondition = \""+ StartCondition +"\"", ERR_INVALID_INPUT_PARAMVALUE)));

   // Sequence.ID: falls gesetzt, wurde sie schon in RestoreInputSequenceId() validiert

   // TODO: Nach Parameter�nderung die neue Konfiguration mit einer evt. bereits laufenden Sequenz abgleichen
   //       oder Parameter werden ge�ndert, ohne vorher im Input-Dialog die Konfigurationsdatei der Sequenz zu laden.

   return(IsNoError(catch("ValidateConfiguration(9)")));
}


/**
 * Speichert den aktuellen Status der Instanz, um sp�ter die nahtlose Re-Initialisierung im selben oder einem anderen Terminal
 * zu erm�glichen.
 *
 * @return bool - Erfolgsstatus
 */
bool SaveStatus() {
   if (IsLastError() || status==STATUS_DISABLED)
      return(false);
   if (sequenceId == 0)
      return(_false(catch("SaveStatus(1)   illegal value of sequenceId = "+ sequenceId, ERR_RUNTIME_ERROR)));

   if (__SCRIPT__ == "SnowRoller.2")
      return(true);
   /*
   F�r's Re-Initialisieren wird der komplette Laufzeitstatus abgespeichert (nicht nur die Input-Parameter).
   --------------------------------------------------------------------------------------------------------
   Speichernotwendigkeit der einzelnen Variablen:

   int      status;                    // nein: kann aus Orderdaten und offenen Positionen restauriert werden

   string   sequenceSymbol;            // ja: History und Original-Tickets sind beim Restart u.U. nicht mehr erreichbar
   datetime sequenceStartup;           // ja: History und Original-Tickets sind beim Restart u.U. nicht mehr erreichbar
   datetime sequenceShutdown;          // ja: History und Original-Tickets sind beim Restart u.U. nicht mehr erreichbar

   double   Entry.limit;               // nein: wird aus StartCondition abgeleitet
   double   Entry.lastBid;             // nein: unn�tig

   double   grid.base;                 // ja: k�nnte zwar u.U. aus den Orderdaten restauriert werden, dies k�nnte sich jedoch �ndern
   int      grid.level;                // nein: kann aus Orderdaten restauriert werden
   int      grid.maxLevelLong;         // nein: kann aus Orderdaten restauriert werden
   int      grid.maxLevelShort;        // nein: kann aus Orderdaten restauriert werden
   int      grid.stops;                // nein: kann aus Orderdaten restauriert werden
   double   grid.stopsPL;              // nein: kann aus Orderdaten restauriert werden
   double   grid.finishedPL;           // nein: kann aus Orderdaten restauriert werden
   double   grid.floatingPL;           // nein: kann aus offenen Positionen restauriert werden
   double   grid.totalPL;              // nein: kann aus stopsPL, finishedPL und floatingPL restauriert werden
   double   grid.valueAtRisk;          // nein: kann aus stopsPL und grid.level restauriert werden
   double   grid.maxProfitLoss;        // ja
   datetime grid.maxProfitLoss.time;   // ja
   double   grid.maxDrawdown;          // ja
   datetime grid.maxDrawdown.time;     // ja
   double   grid.breakevenLong;        // nein: wird mit dem aktuellen TickValue als N�herung neuberechnet
   double   grid.breakevenShort;       // nein: wird mit dem aktuellen TickValue als N�herung neuberechnet

   int      orders.ticket      [];     // ja
   int      orders.level       [];     // ja
   int      orders.pendingType [];     // ja
   datetime orders.pendingTime [];     // ja
   double   orders.pendingPrice[];     // ja
   int      orders.type        [];     // ja
   datetime orders.openTime    [];     // ja
   double   orders.openPrice   [];     // ja
   datetime orders.closeTime   [];     // ja
   double   orders.closePrice  [];     // ja
   double   orders.stopLoss    [];     // ja
   double   orders.swap        [];     // ja
   double   orders.commission  [];     // ja
   double   orders.profit      [];     // ja
   string   orders.comment     [];     // ja
   */

   // (1.1) Input-Parameter zusammenstellen
   string lines[];  ArrayResize(lines, 0);
   ArrayPushString(lines, /*string*/ "Sequence.ID="   +             sequenceId    );
   ArrayPushString(lines, /*int   */ "GridSize="      +             GridSize      );
   ArrayPushString(lines, /*double*/ "LotSize="       + NumberToStr(LotSize, ".+"));
   ArrayPushString(lines, /*string*/ "StartCondition="+             StartCondition);

   // (1.2) Laufzeit-Variablen zusammenstellen
   int size = ArraySize(orders.ticket);
   if (size > 0) {
      ArrayPushString(lines, /*double*/   "rt.grid.base="              + NumberToStr(grid.base, ".+")         );
      ArrayPushString(lines, /*double*/   "rt.grid.maxProfitLoss="     + NumberToStr(grid.maxProfitLoss, ".+"));
      ArrayPushString(lines, /*datetime*/ "rt.grid.maxProfitLoss.time="+             grid.maxProfitLoss.time  );
      ArrayPushString(lines, /*double*/   "rt.grid.maxDrawdown="       + NumberToStr(grid.maxDrawdown, ".+")  );
      ArrayPushString(lines, /*datetime*/ "rt.grid.maxDrawdown.time="  +             grid.maxDrawdown.time    );
   }
   for (int i=0; i < size; i++) {
      int      ticket       = orders.ticket      [i];
      int      level        = orders.level       [i];
      int      pendingType  = orders.pendingType [i];
      datetime pendingTime  = orders.pendingTime [i];
      double   pendingPrice = orders.pendingPrice[i];
      int      type         = orders.type        [i];
      datetime openTime     = orders.openTime    [i];
      double   openPrice    = orders.openPrice   [i];
      datetime closeTime    = orders.closeTime   [i];
      double   closePrice   = orders.closePrice  [i];
      double   stopLoss     = orders.stopLoss    [i];
      double   swap         = orders.swap        [i];
      double   commission   = orders.commission  [i];
      double   profit       = orders.profit      [i];
      string   comment      = orders.comment     [i];
      ArrayPushString(lines, StringConcatenate("rt.order.", i, "=", level, ",", ticket, ",", pendingType, ",", pendingTime, ",", NumberToStr(pendingPrice, ".+"), ",", type, ",", openTime, ",", NumberToStr(openPrice, ".+"), ",", closeTime, ",", NumberToStr(closePrice, ".+"), ",", NumberToStr(stopLoss, ".+"), ",", NumberToStr(swap, ".+"), ",", NumberToStr(commission, ".+"), ",", NumberToStr(profit, ".+"), ",", comment));
   }


   // (2) Daten in lokaler Datei (�ber-)schreiben
   string filename = "presets\\SR."+ sequenceId +".set";             // "experts\files\presets" ist ein Softlink auf "experts\presets", dadurch ist
                                                                     // das Presets-Verzeichnis f�r die MQL-Dateifunktionen erreichbar.
   int hFile = FileOpen(filename, FILE_CSV|FILE_WRITE);
   if (hFile < 0)
      return(_false(catch("SaveStatus(2)->FileOpen(\""+ filename +"\")")));

   for (i=0; i < ArraySize(lines); i++) {
      if (FileWrite(hFile, lines[i]) < 0) {
         catch("SaveStatus(3)->FileWrite(line #"+ (i+1) +")");
         FileClose(hFile);
         return(false);
      }
   }
   FileClose(hFile);


   // (3) Datei auf Server laden
   int error = UploadStatus(ShortAccountCompany(), AccountNumber(), StdSymbol(), filename);
   if (IsError(error))
      return(false);

   return(IsNoError(catch("SaveStatus(4)")));
}


/**
 * L�dt die angegebene Statusdatei auf den Server.
 *
 * @param  string company     - Account-Company
 * @param  int    account     - Account-Number
 * @param  string symbol      - Symbol der Sequenz
 * @param  string presetsFile - Dateiname, relativ zu "{terminal-directory}\experts"
 *
 * @return int - Fehlerstatus
 */
int UploadStatus(string company, int account, string symbol, string presetsFile) {
   if (IsLastError() || status==STATUS_DISABLED)
      return(last_error);

   if (IsTesting())                                                     // skipping in Tester
      return(NO_ERROR);

   // TODO: Existenz von wget.exe pr�fen

   string parts[]; int size = Explode(presetsFile, "\\", parts, NULL);
   string file = parts[size-1];                                         // einfacher Dateiname ohne Verzeichnisse

   // Befehlszeile f�r Shellaufruf zusammensetzen
   string presetsPath  = TerminalPath() +"\\experts\\" + presetsFile;   // Dateinamen mit vollst�ndigen Pfaden
   string responsePath = presetsPath +".response";
   string logPath      = presetsPath +".log";
   string url          = "http://sub.domain.tld/uploadSRStatus.php?company="+ UrlEncode(company) +"&account="+ account +"&symbol="+ UrlEncode(symbol) +"&name="+ UrlEncode(file);
   string cmdLine      = "wget.exe -b \""+ url +"\" --post-file=\""+ presetsPath +"\" --header=\"Content-Type: text/plain\" -O \""+ responsePath +"\" -a \""+ logPath +"\"";

   // Existenz der Datei pr�fen
   if (!IsFile(presetsPath))
      return(catch("UploadStatus(1)   file not found: \""+ presetsPath +"\"", ERR_FILE_NOT_FOUND));

   // Datei hochladen, WinExec() kehrt ohne zu warten zur�ck, wget -b beschleunigt zus�tzlich
   int error = WinExec(cmdLine, SW_HIDE);                               // SW_SHOWNORMAL|SW_HIDE
   if (error < 32)
      return(catch("UploadStatus(2) ->kernel32::WinExec(cmdLine=\""+ cmdLine +"\"), error="+ error +" ("+ ShellExecuteErrorToStr(error) +")", ERR_WIN32_ERROR));

   return(catch("UploadStatus(3)"));
}


/**
 * Liest den Status einer Sequenz ein und restauriert die internen Variablen. Bei fehlender lokaler Statusdatei wird versucht,
 * die Datei vom Server zu laden.
 *
 * @return bool - ob der Status erfolgreich restauriert wurde
 */
bool RestoreStatus() {
   if (IsLastError() || status==STATUS_DISABLED)
      return(false);

   if (sequenceId == 0)
      return(_false(catch("RestoreStatus(1)   illegal value of sequenceId = "+ sequenceId, ERR_RUNTIME_ERROR)));

   // (1) bei nicht existierender lokaler Konfiguration die Datei neu vom Server laden
   string filesDir = TerminalPath() + ifString(IsTesting(), "\\tester", "\\experts") +"\\files\\";
   string fileName = "presets\\SR."+ sequenceId +".set";             // "experts\files\presets" ist ein Softlink auf "experts\presets", dadurch
                                                                     // ist das Presets-Verzeichnis f�r die MQL-Dateifunktionen erreichbar.
   if (!IsFile(filesDir + fileName)) {
      if (IsTesting())
         return(_false(catch("RestoreStatus(2)   status file for sequence "+ sequenceId +" not found", ERR_FILE_NOT_FOUND)));

      // TODO: Existenz von wget.exe pr�fen

      // Befehlszeile f�r Shellaufruf zusammensetzen
      string url        = "http://sub.domain.tld/downloadSRStatus.php?company="+ UrlEncode(ShortAccountCompany()) +"&account="+ AccountNumber() +"&symbol="+ UrlEncode(StdSymbol()) +"&sequence="+ sequenceId;
      string targetFile = filesDir +"\\"+ fileName;
      string logFile    = filesDir +"\\"+ fileName +".log";
      string cmd        = "wget.exe \""+ url +"\" -O \""+ targetFile +"\" -o \""+ logFile +"\"";

      debug("RestoreStatus()   downloading status file for sequence "+ sequenceId);

      int error = WinExecAndWait(cmd, SW_HIDE);                      // SW_SHOWNORMAL|SW_HIDE
      if (IsError(error))
         return(_false(SetLastError(error)));

      debug("RestoreStatus()   status file for sequence "+ sequenceId +" successfully downloaded");
      FileDelete(fileName +".log");
   }

   // (2) Datei einlesen
   string lines[];
   int size = FileReadLines(fileName, lines, true);
   if (size < 0)
      return(_false(SetLastError(stdlib_PeekLastError())));
   if (size == 0) {
      FileDelete(fileName);
      return(_false(catch("RestoreStatus(3)   status for sequence "+ sequenceId +" not found", ERR_RUNTIME_ERROR)));
   }


   // (3) Zeilen in Schl�ssel-Wert-Paare aufbrechen, Datentypen validieren und Daten �bernehmen
   int keys[4]; ArrayInitialize(keys, 0);
   #define I_SEQUENCE_ID    0
   #define I_GRIDSIZE       1
   #define I_LOTSIZE        2
   #define I_STARTCONDITION 3

   string parts[];
   for (int i=0; i < size; i++) {
      if (Explode(lines[i], "=", parts, 2) < 2)          return(_false(catch("RestoreStatus(4)   invalid status file \""+ fileName +"\" (line \""+ lines[i] +"\")", ERR_RUNTIME_ERROR)));
      string key=StringTrim(parts[0]), value=StringTrim(parts[1]);

      if (key == "Sequence.ID") {
         if (value != StringConcatenate("", sequenceId)) return(_false(catch("RestoreStatus(5)   invalid status file \""+ fileName +"\" (line \""+ lines[i] +"\")", ERR_RUNTIME_ERROR)));
         Sequence.ID = sequenceId;
         keys[I_SEQUENCE_ID] = 1;
      }
      else if (key == "GridSize") {
         if (!StringIsDigit(value))                      return(_false(catch("RestoreStatus(6)   invalid status file \""+ fileName +"\" (line \""+ lines[i] +"\")", ERR_RUNTIME_ERROR)));
         GridSize = StrToInteger(value);
         keys[I_GRIDSIZE] = 1;
      }
      else if (key == "LotSize") {
         if (!StringIsNumeric(value))                    return(_false(catch("RestoreStatus(7)   invalid status file \""+ fileName +"\" (line \""+ lines[i] +"\")", ERR_RUNTIME_ERROR)));
         LotSize = StrToDouble(value); SS.LotSize();
         keys[I_LOTSIZE] = 1;
      }
      else if (key == "StartCondition") {
         StartCondition = value;
         keys[I_STARTCONDITION] = 1;
      }
      else if (StringStartsWith(key, "rt.")) {                       // Laufzeitvariable
         if (!RestoreStatus.Runtime(fileName, lines[i], StringRight(key, -3), value))
            return(false);
      }
   }
   if (IntInArray(0, keys))                              return(_false(catch("RestoreStatus(8)   one or more configuration values missing in file \""+ fileName +"\"", ERR_RUNTIME_ERROR)));
   if (IntInArray(0, orders.ticket))                     return(_false(catch("RestoreStatus(9)   one or more order entries missing in file \""+ fileName +"\"", ERR_RUNTIME_ERROR)));

   return(IsNoError(catch("RestoreStatus(10)")));
}


/**
 * Restauriert eine oder mehrere Laufzeitvariablen.
 *
 * @param  string file  - Name der Statusdatei, aus der die Einstellung stammt (nur f�r evt. Fehlermeldung)
 * @param  string line  - Statuszeile der Einstellung                          (nur f�r evt. Fehlermeldung)
 * @param  string key   - Schl�ssel der Einstellung
 * @param  string value - Wert der Einstellung
 *
 * @return bool - Erfolgsstatus
 */
bool RestoreStatus.Runtime(string file, string line, string key, string value) {
   if (IsLastError() || status==STATUS_DISABLED)
      return(false);
   /*
   [rt.]grid.base=1.32677
   [rt.]grid.maxProfitLoss=200.13
   [rt.]grid.maxProfitLoss.time=1328701713
   [rt.]grid.maxDrawdown=-127.80
   [rt.]grid.maxDrawdown.time=1328691713
   [rt.]order.0=1,61845848,2,1328705611,1.32757,0,1328705811,1.32757,1328705920,1.32677,1.32677,0,0,-8,
   int      level        = values[ 0];
   int      ticket       = values[ 1];
   int      pendingType  = values[ 2];
   datetime pendingTime  = values[ 3];
   double   pendingPrice = values[ 4];
   int      type         = values[ 5];
   datetime openTime     = values[ 6];
   double   openPrice    = values[ 7];
   datetime closeTime    = values[ 8];
   double   closePrice   = values[ 9];
   double   stopLoss     = values[10];
   double   swap         = values[11];
   double   commission   = values[12];
   double   profit       = values[13];
   string   comment      = values[14];
   */
   if (key == "grid.base") {
      if (!StringIsNumeric(value))                                          return(_false(catch("RestoreStatus.Runtime(1)   illegal grid.base \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      grid.base = StrToDouble(value); SS.Grid.Base();
      if (LT(grid.base, 0))                                                 return(_false(catch("RestoreStatus.Runtime(2)   illegal grid.base "+ NumberToStr(grid.base, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
   }
   else if (key == "grid.maxProfitLoss") {
      if (!StringIsNumeric(value))                                          return(_false(catch("RestoreStatus.Runtime(3)   illegal grid.maxProfitLoss \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      grid.maxProfitLoss = StrToDouble(value); SS.Grid.MaxProfitLoss();
   }
   else if (key == "grid.maxProfitLoss.time") {
      if (!StringIsDigit(value))                                            return(_false(catch("RestoreStatus.Runtime(4)   illegal grid.maxProfitLoss.time \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      grid.maxProfitLoss.time = StrToInteger(value);
      if (grid.maxProfitLoss.time==0 && NE(grid.maxProfitLoss, 0))          return(_false(catch("RestoreStatus.Runtime(5)   grid.maxProfitLoss/grid.maxProfitLoss.time mis-match "+ NumberToStr(grid.maxProfitLoss, ".2") +"/\""+ TimeToStr(grid.maxProfitLoss.time, TIME_DATE|TIME_MINUTES|TIME_SECONDS) +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
   }
   else if (key == "grid.maxDrawdown") {
      if (!StringIsNumeric(value))                                          return(_false(catch("RestoreStatus.Runtime(6)   illegal grid.maxDrawdown \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      grid.maxDrawdown = StrToDouble(value); SS.Grid.MaxDrawdown();
   }
   else if (key == "grid.maxDrawdown.time") {
      if (!StringIsDigit(value))                                            return(_false(catch("RestoreStatus.Runtime(7)   illegal grid.maxDrawdown.time \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      grid.maxDrawdown.time = StrToInteger(value);
      if (grid.maxDrawdown.time==0 && NE(grid.maxDrawdown, 0))              return(_false(catch("RestoreStatus.Runtime(8)   grid.maxDrawdown/grid.maxDrawdown.time mis-match "+ NumberToStr(grid.maxDrawdown, ".2") +"/\""+ TimeToStr(grid.maxDrawdown.time, TIME_DATE|TIME_MINUTES|TIME_SECONDS) +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
   }
   else if (StringStartsWith(key, "order.")) {
      // Orderindex
      string strIndex = StringRight(key, -6);
      if (!StringIsDigit(strIndex))                                         return(_false(catch("RestoreStatus.Runtime(9)   illegal order index \""+ key +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      int i = StrToInteger(strIndex);
      if (ArraySize(orders.ticket) > i) /*&&*/ if (orders.ticket[i]!=0)     return(_false(catch("RestoreStatus.Runtime(10)   duplicate order index "+ key +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // Orderdaten
      string values[];
      if (Explode(value, ",", values, 15) < 15)                             return(_false(catch("RestoreStatus.Runtime(11)   illegal number of order details ("+ ArraySize(values) +") in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // level
      string strLevel = StringTrim(values[0]);
      if (!StringIsInteger(strLevel))                                       return(_false(catch("RestoreStatus.Runtime(12)   illegal order level \""+ strLevel +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      int level = StrToInteger(strLevel);
      if (level == 0)                                                       return(_false(catch("RestoreStatus.Runtime(13)   illegal order level "+ level +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // ticket
      string strTicket = StringTrim(values[1]);
      if (!StringIsDigit(strTicket))                                        return(_false(catch("RestoreStatus.Runtime(14)   illegal order ticket \""+ strTicket +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      int ticket = StrToInteger(strTicket);
      if (ticket == 0)                                                      return(_false(catch("RestoreStatus.Runtime(15)   illegal order ticket #"+ ticket +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (IntInArray(ticket, orders.ticket))                                return(_false(catch("RestoreStatus.Runtime(16)   duplicate order ticket #"+ ticket +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // pendingType
      string strPendingType = StringTrim(values[2]);
      if (!StringIsInteger(strPendingType))                                 return(_false(catch("RestoreStatus.Runtime(17)   illegal pending order type \""+ strPendingType +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      int pendingType = StrToInteger(strPendingType);
      if (pendingType!=OP_UNDEFINED && !IsTradeOperation(pendingType))      return(_false(catch("RestoreStatus.Runtime(18)   illegal pending order type \""+ strPendingType +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // pendingTime
      string strPendingTime = StringTrim(values[3]);
      if (!StringIsDigit(strPendingTime))                                   return(_false(catch("RestoreStatus.Runtime(19)   illegal pending order time \""+ strPendingTime +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      datetime pendingTime = StrToInteger(strPendingTime);
      if (pendingType==OP_UNDEFINED && pendingTime!=0)                      return(_false(catch("RestoreStatus.Runtime(20)   pending order type/time mis-match OP_UNDEFINED/\""+ TimeToStr(pendingTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS) +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (pendingType!=OP_UNDEFINED && pendingTime==0)                      return(_false(catch("RestoreStatus.Runtime(21)   pending order type/time mis-match "+ OperationTypeToStr(pendingType) +"/0 in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // pendingPrice
      string strPendingPrice = StringTrim(values[4]);
      if (!StringIsNumeric(strPendingPrice))                                return(_false(catch("RestoreStatus.Runtime(22)   illegal pending order price \""+ strPendingPrice +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double pendingPrice = StrToDouble(strPendingPrice);
      if (LT(pendingPrice, 0))                                              return(_false(catch("RestoreStatus.Runtime(23)   illegal pending order price "+ NumberToStr(pendingPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (pendingType==OP_UNDEFINED && NE(pendingPrice, 0))                 return(_false(catch("RestoreStatus.Runtime(24)   pending order type/price mis-match OP_UNDEFINED/"+ NumberToStr(pendingPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (pendingType!=OP_UNDEFINED && EQ(pendingPrice, 0))                 return(_false(catch("RestoreStatus.Runtime(25)   pending order type/price mis-match "+ OperationTypeToStr(pendingType) +"/"+ NumberToStr(pendingPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // type
      string strType = StringTrim(values[5]);
      if (!StringIsInteger(strType))                                        return(_false(catch("RestoreStatus.Runtime(26)   illegal order type \""+ strType +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      int type = StrToInteger(strType);
      if (type!=OP_UNDEFINED && !IsTradeOperation(type))                    return(_false(catch("RestoreStatus.Runtime(27)   illegal order type \""+ strType +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (pendingType == OP_UNDEFINED) {
         if (type==OP_UNDEFINED)                                            return(_false(catch("RestoreStatus.Runtime(28)   pending order type/open order type mis-match OP_UNDEFINED/OP_UNDEFINED in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      }
      else if (type != OP_UNDEFINED) {
         if (IsLongTradeOperation(pendingType)!=IsLongTradeOperation(type)) return(_false(catch("RestoreStatus.Runtime(29)   pending order type/open order type mis-match "+ OperationTypeToStr(pendingType) +"/"+ OperationTypeToStr(type) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      }

      // openTime
      string strOpenTime = StringTrim(values[6]);
      if (!StringIsDigit(strOpenTime))                                      return(_false(catch("RestoreStatus.Runtime(30)   illegal order open time \""+ strOpenTime +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      datetime openTime = StrToInteger(strOpenTime);
      if (type==OP_UNDEFINED && openTime!=0)                                return(_false(catch("RestoreStatus.Runtime(31)   order type/time mis-match OP_UNDEFINED/\""+ TimeToStr(openTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS) +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (type!=OP_UNDEFINED && openTime==0)                                return(_false(catch("RestoreStatus.Runtime(32)   order type/time mis-match "+ OperationTypeToStr(type) +"/0 in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // openPrice
      string strOpenPrice = StringTrim(values[7]);
      if (!StringIsNumeric(strOpenPrice))                                   return(_false(catch("RestoreStatus.Runtime(33)   illegal order open price \""+ strOpenPrice +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double openPrice = StrToDouble(strOpenPrice);
      if (LT(openPrice, 0))                                                 return(_false(catch("RestoreStatus.Runtime(34)   illegal order open price "+ NumberToStr(openPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (type==OP_UNDEFINED && NE(openPrice, 0))                           return(_false(catch("RestoreStatus.Runtime(35)   order type/price mis-match OP_UNDEFINED/"+ NumberToStr(openPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (type!=OP_UNDEFINED && EQ(openPrice, 0))                           return(_false(catch("RestoreStatus.Runtime(36)   order type/price mis-match "+ OperationTypeToStr(type) +"/"+ NumberToStr(openPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // closeTime
      string strCloseTime = StringTrim(values[8]);
      if (!StringIsDigit(strCloseTime))                                     return(_false(catch("RestoreStatus.Runtime(37)   illegal order close time \""+ strCloseTime +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      datetime closeTime = StrToInteger(strCloseTime);
      if (closeTime!=0 && closeTime < pendingTime)                          return(_false(catch("RestoreStatus.Runtime(38)   pending order open/delete time mis-match \""+ TimeToStr(pendingTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS) +"\"/\""+ TimeToStr(closeTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS) +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (closeTime!=0 && closeTime < openTime)                             return(_false(catch("RestoreStatus.Runtime(39)   order open/close time mis-match \""+ TimeToStr(openTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS) +"\"/\""+ TimeToStr(closeTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS) +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // closePrice
      string strClosePrice = StringTrim(values[9]);
      if (!StringIsNumeric(strClosePrice))                                  return(_false(catch("RestoreStatus.Runtime(40)   illegal order close price \""+ strClosePrice +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double closePrice = StrToDouble(strClosePrice);
      if (LT(closePrice, 0))                                                return(_false(catch("RestoreStatus.Runtime(41)   illegal order close price "+ NumberToStr(closePrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // stopLoss
      string strStopLoss = StringTrim(values[10]);
      if (!StringIsNumeric(strStopLoss))                                    return(_false(catch("RestoreStatus.Runtime(42)   illegal order stoploss \""+ strStopLoss +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double stopLoss = StrToDouble(strStopLoss);
      if (LT(stopLoss, 0))                                                  return(_false(catch("RestoreStatus.Runtime(43)   illegal order stoploss "+ NumberToStr(stopLoss, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // swap
      string strSwap = StringTrim(values[11]);
      if (!StringIsNumeric(strSwap))                                        return(_false(catch("RestoreStatus.Runtime(44)   illegal order swap \""+ strSwap +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double swap = StrToDouble(strSwap);
      if (type==OP_UNDEFINED && NE(swap, 0))                                return(_false(catch("RestoreStatus.Runtime(45)   pending order/swap mis-match "+ OperationTypeToStr(pendingType) +"->OP_UNDEFINED/"+ NumberToStr(swap, 2) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // commission
      string strCommission = StringTrim(values[12]);
      if (!StringIsNumeric(strCommission))                                  return(_false(catch("RestoreStatus.Runtime(46)   illegal order commission \""+ strCommission +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double commission = StrToDouble(strCommission);
      if (type==OP_UNDEFINED && NE(commission, 0))                          return(_false(catch("RestoreStatus.Runtime(47)   pending order/commission mis-match "+ OperationTypeToStr(pendingType) +"->OP_UNDEFINED/"+ NumberToStr(commission, 2) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // profit
      string strProfit = StringTrim(values[13]);
      if (!StringIsNumeric(strProfit))                                      return(_false(catch("RestoreStatus.Runtime(48)   illegal order profit \""+ strProfit +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double profit = StrToDouble(strProfit);
      if (type==OP_UNDEFINED && NE(profit, 0))                              return(_false(catch("RestoreStatus.Runtime(49)   pending order/profit mis-match "+ OperationTypeToStr(pendingType) +"->OP_UNDEFINED/"+ NumberToStr(profit, 2) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // comment
      string comment = StringTrim(values[14]);

      // ggf. Datenarrays vergr��ern
      if (ArraySize(orders.ticket) < i+1)
         ResizeArrays(i+1);

      // Daten speichern
      orders.ticket      [i] = ticket;
      orders.level       [i] = level;
      orders.pendingType [i] = pendingType;
      orders.pendingTime [i] = pendingTime;
      orders.pendingPrice[i] = pendingPrice;
      orders.type        [i] = type;
      orders.openTime    [i] = openTime;
      orders.openPrice   [i] = openPrice;
      orders.closeTime   [i] = closeTime;
      orders.closePrice  [i] = closePrice;
      orders.stopLoss    [i] = stopLoss;
      orders.swap        [i] = swap;
      orders.commission  [i] = commission;
      orders.profit      [i] = profit;
      orders.comment     [i] = comment;
   }
   return(IsNoError(catch("RestoreStatus.Runtime(50)")));
}


/**
 * Gleicht den gespeicherten Laufzeitstatus mit den Online-Daten der laufenden Sequenz ab.
 *
 * @return bool - Erfolgsstatus
 */
bool SynchronizeStatus() {
   if (IsLastError() || status==STATUS_DISABLED)
      return(false);

   // (1.1) alle offenen Tickets in Datenarrays mit Online-Status synchronisieren
   for (int i=ArraySize(orders.ticket)-1; i >= 0; i--) {
      // Daten synchronisieren, wenn das Ticket beim letzten Mal noch offen war
      if (orders.closeTime[i] == 0) {
         if (!OrderSelectByTicket(orders.ticket[i], "SynchronizeStatus(1)   cannot synchronize "+ OperationTypeDescription(ifInt(orders.type[i]==OP_UNDEFINED, orders.pendingType[i], orders.type[i])) +" order, #"+ orders.ticket[i] +" not found"))
            return(false);
         if (!Grid.ReplaceTicket(orders.ticket[i]))
            return(false);
      }
   }

   // (1.2) alle erreichbaren Online-Tickets mit Datenarrays synchronisieren
   for (i=OrdersTotal()-1; i >= 0; i--) {                            // offene Tickets
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))               // FALSE: w�hrend des Auslesens wurde in einem anderen Thread eine offene Order entfernt
         continue;
      if (IsMyOrder(sequenceId)) {
         if (IntInArray(OrderTicket(), orders.ticket)) {             // bekannte Order
            if (!Grid.ReplaceTicket(OrderTicket()))
               return(false);
         }
         else if (!Grid.PushTicket(OrderTicket())) {                 // neue Order
            return(false);
         }
      }
   }
   for (i=OrdersHistoryTotal()-1; i >= 0; i--) {                     // geschlossene Tickets
      if (!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))              // FALSE: w�hrend des Auslesens wurde der Anzeigezeitraum der History ver�ndert
         continue;
      if (IsMyOrder(sequenceId)) {
         if (IntInArray(OrderTicket(), orders.ticket)) {             // bekannte Order
            if (!Grid.ReplaceTicket(OrderTicket()))
               return(false);
         }
         else if (!Grid.PushTicket(OrderTicket())) {                 // neue Order
            return(false);
         }
      }
   }

   // (1.3) gestrichene Orders aus Datenarrays entfernen
   for (i=ArraySize(orders.ticket)-1; i >= 0; i--) {
      if (orders.type[i]==OP_UNDEFINED) /*&&*/ if (orders.closeTime[i]!=0)
         if (!Grid.DropTicket(orders.ticket[i]))
            return(false);
   }


   // (2) �brige Laufzeitvariablen restaurieren
   /*
   int    status;                   // ok
   int    grid.level;               // ok
   int    grid.maxLevelLong;        // ok
   int    grid.maxLevelShort;       // ok
   int    grid.stops;               // ok
   double grid.stopsPL;             // ok
   double grid.finishedPL;          // ok
   double grid.floatingPL;          // ok
   double grid.totalPL;             // ok
   double grid.valueAtRisk;         // ok
   double grid.breakevenLong;       //    wird mit dem aktuellen TickValue als N�herung neuberechnet
   double grid.breakevenShort;      //    wird mit dem aktuellen TickValue als N�herung neuberechnet
   */
   int size = ArraySize(orders.ticket);
   status = ifInt(size==0, STATUS_WAITING, STATUS_PROGRESSING);

   bool pendingOrder, openPosition, closedPosition, closedByStop, closedByFinish, openPositions, finishedPositions;
   int levels[]; ArrayResize(levels, 0);

   for (i=0; i < size; i++) {
      pendingOrder   = orders.type[i] == OP_UNDEFINED;
      openPosition   = !pendingOrder && orders.closeTime[i]==0;
      closedPosition = !pendingOrder && !openPosition;

      if (closedPosition) {                                                            // geschlossenes Ticket
         if (StringIEndsWith(orders.comment[i], "[sl]")) closedByStop = true;
         else if (orders.type[i] == OP_BUY )             closedByStop = LE(orders.closePrice[i], orders.stopLoss[i]);
         else if (orders.type[i] == OP_SELL)             closedByStop = GE(orders.closePrice[i], orders.stopLoss[i]);
         else                                            closedByStop = false;
         closedByFinish = !closedByStop;
      }

      if (!pendingOrder) {
         grid.maxLevelLong  = MathMax(grid.maxLevelLong,  orders.level[i]) +0.1;                      // (int) double
         grid.maxLevelShort = MathMin(grid.maxLevelShort, orders.level[i]) -0.1; SS.Grid.MaxLevel();  // (int) double

         if (openPosition) {
            openPositions = true;
            grid.floatingPL += orders.swap[i] + orders.commission[i] + orders.profit[i];

            if (orders.level[i] > 0) {
               if (grid.level < 0) return(_false(catch("SynchronizeStatus(2)   illegal sequence status, both long and short open positions found", ERR_RUNTIME_ERROR)));
               grid.level = MathMax(grid.level, orders.level[i]) +0.1;                 // (int) double
            }
            else if (orders.level[i] < 0) {
               if (grid.level > 0) return(_false(catch("SynchronizeStatus(3)   illegal sequence status, both long and short open positions found", ERR_RUNTIME_ERROR)));
               grid.level = MathMin(grid.level, orders.level[i]) -0.1;                 // (int) double
            }
            else return(_false(catch("SynchronizeStatus(4)   illegal order level "+ orders.level[i] +" of open position #"+ orders.ticket[i], ERR_RUNTIME_ERROR)));

            if (IntInArray(orders.level[i], levels))
               return(_false(catch("SynchronizeStatus(5)   duplicate order level "+ orders.level[i] +" of open position #"+ orders.ticket[i], ERR_RUNTIME_ERROR)));

            ArrayPushInt(levels, orders.level[i]);
            grid.valueAtRisk = grid.stopsPL - MathAbs(grid.level) * GridSize * PipValue(LotSize); SS.Grid.ValueAtRisk();
         }
         else if (closedByStop) {
            grid.stops++;
            grid.stopsPL    += orders.swap[i] + orders.commission[i] + orders.profit[i]; SS.Grid.Stops();
            grid.valueAtRisk = grid.stopsPL - MathAbs(grid.level) * GridSize * PipValue(LotSize); SS.Grid.ValueAtRisk();
         }
         else if (closedByFinish) {
            grid.finishedPL  += orders.swap[i] + orders.commission[i] + orders.profit[i];
            finishedPositions = true;
         }
         else return(_false(catch("SynchronizeStatus(6)   illegal order status of #"+ orders.ticket[i], ERR_RUNTIME_ERROR)));
      }

      // (2.1) Order visualisieren
      bool success = true;
      if      (pendingOrder) {                       success = ChartMarker.OrderSent_B(orders.ticket[i], Digits, ifInt(IsLongTradeOperation(orders.pendingType[i]), CLR_LONG, CLR_SHORT), orders.pendingType[i], LotSize, Symbol(), orders.pendingTime[i], orders.pendingPrice[i], orders.stopLoss[i], 0, orders.comment[i]);
      }
      else if (openPosition) {                       // openPosition ist Folge von Pending- oder Market-Order
         if (orders.pendingType[i]!=OP_UNDEFINED)    success = ChartMarker.OrderFilled(i);
         else                                        success = ChartMarker.OrderSent_B(orders.ticket[i], Digits, ifInt(orders.type[i]==OP_BUY, CLR_LONG, CLR_SHORT), orders.type[i], LotSize, Symbol(), orders.openTime[i], orders.openPrice[i], orders.stopLoss[i], 0, orders.comment[i]);
      }
      else /*(closedPosition)*/ {                    // closedPosition ist Folge von openPosition
         if (closedByFinish) {
            if (orders.pendingType[i]!=OP_UNDEFINED) success = ChartMarker.OrderFilled(i);
            else                                     success = ChartMarker.OrderSent_B(orders.ticket[i], Digits, ifInt(orders.type[i]==OP_BUY, CLR_LONG, CLR_SHORT), orders.type[i], LotSize, Symbol(), orders.openTime[i], orders.openPrice[i], orders.stopLoss[i], 0, orders.comment[i]);
            if (success)                             success = ChartMarker.PositionClosed_B(orders.ticket[i], Digits, CLR_CLOSE, orders.type[i], LotSize, Symbol(), orders.openTime[i], orders.openPrice[i], orders.closeTime[i], orders.closePrice[i]);
         }
      }
      if (!success && !IsLastError())
         return(_false(SetLastError(stdlib_PeekLastError())));
   }

   grid.totalPL = grid.stopsPL + grid.finishedPL + grid.floatingPL; SS.Grid.TotalPL();
   Grid.UpdateBreakeven();

   if (openPositions) {
      if (finishedPositions) return(_false(catch("SynchronizeStatus(7)   illegal sequence status, both open and finished positions found", ERR_RUNTIME_ERROR)));

      if (grid.level > 0) {
         if (ArraySize(levels) != levels[ArrayMaximum(levels)])
            return(_false(catch("SynchronizeStatus(8)   illegal sequence status, one or more open positions missed", ERR_RUNTIME_ERROR)));
      }
      else if (ArraySize(levels) != -levels[ArrayMinimum(levels)]) {
         return(_false(catch("SynchronizeStatus(9)   illegal sequence status, one or more open positions missed", ERR_RUNTIME_ERROR)));
      }
   }
   else if (finishedPositions) {
      status = STATUS_FINISHED;
   }

   return(IsNoError(catch("SynchronizeStatus(10)")));
}


/**
 * Korrigiert die vom Terminal beim Ausf�hren einer Pending-Order gesetzten oder nicht gesetzten Chart-Marker.
 *
 * @param  int i - Index des Ordertickets in den Datenarrays
 *
 * @return bool - Erfolgsstatus
 */
bool ChartMarker.OrderFilled(int i) {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return(true);

   if (i < 0 || ArraySize(orders.ticket) < i+1)
      return(_false(catch("ChartMarker.OrderFilled()   illegal parameter i = "+ i, ERR_INVALID_FUNCTION_PARAMVALUE)));

   if (!ChartMarker.OrderFilled_B(orders.ticket[i], orders.pendingType[i], orders.pendingPrice[i], Digits, ifInt(orders.type[i]==OP_BUY, CLR_LONG, CLR_SHORT), LotSize, Symbol(), orders.openTime[i], orders.openPrice[i], orders.comment[i]))
      return(_false(SetLastError(stdlib_PeekLastError())));

   return(true);
}


/**
 * Setzt die Gr��e der Datenarrays auf den angegebenen Wert.
 *
 * @param  int  size  - neue Gr��e
 * @param  bool reset - ob die Arrays komplett zur�ckgesetzt werden sollen
 *                      (default: nur neu hinzugef�gte Felder werden initialisiert)
 *
 * @return int - Fehlerstatus
 */
int ResizeArrays(int size, bool reset=false) {
   int oldSize = ArraySize(orders.ticket);

   if (size != oldSize) {
      ArrayResize(orders.ticket,       size);
      ArrayResize(orders.level,        size);
      ArrayResize(orders.pendingType,  size);
      ArrayResize(orders.pendingTime,  size);
      ArrayResize(orders.pendingPrice, size);
      ArrayResize(orders.type,         size);
      ArrayResize(orders.openTime,     size);
      ArrayResize(orders.openPrice,    size);
      ArrayResize(orders.closeTime,    size);
      ArrayResize(orders.closePrice,   size);
      ArrayResize(orders.stopLoss,     size);
      ArrayResize(orders.swap,         size);
      ArrayResize(orders.commission,   size);
      ArrayResize(orders.profit,       size);
      ArrayResize(orders.comment,      size);
   }

   if (reset) {                                                      // alle Felder zur�cksetzen
      if (size != 0) {
         ArrayInitialize(orders.ticket,                 0);
         ArrayInitialize(orders.level,                  0);
         ArrayInitialize(orders.pendingType, OP_UNDEFINED);
         ArrayInitialize(orders.pendingTime,            0);
         ArrayInitialize(orders.pendingPrice,           0);
         ArrayInitialize(orders.type,        OP_UNDEFINED);
         ArrayInitialize(orders.openTime,               0);
         ArrayInitialize(orders.openPrice,              0);
         ArrayInitialize(orders.closeTime,              0);
         ArrayInitialize(orders.closePrice,             0);
         ArrayInitialize(orders.stopLoss,               0);
         ArrayInitialize(orders.swap,                   0);
         ArrayInitialize(orders.commission,             0);
         ArrayInitialize(orders.profit,                 0);
         for (int i=0; i < size; i++) {
            orders.comment[i] = "";
         }
      }
   }
   else {
      for (i=oldSize; i < size; i++) {                               // hinzugef�gte pendingType- und type-Felder initialisieren
         orders.pendingType[i] = OP_UNDEFINED;
         orders.type       [i] = OP_UNDEFINED;
      }
   }

   return(catch("ResizeArrays()"));

   // Dummy-Calls
   DistanceToProfit(NULL);
   SequenceStatusToStr(NULL);
}


/**
 * Gibt die lesbare Konstante eines Sequenzstatus-Codes zur�ck.
 *
 * @param  int status - Status-Code
 *
 * @return string
 */
string SequenceStatusToStr(int status) {
   switch (status) {
      case STATUS_WAITING    : return("STATUS_WAITING"    );
      case STATUS_PROGRESSING: return("STATUS_PROGRESSING");
      case STATUS_FINISHED   : return("STATUS_FINISHED"   );
      case STATUS_DISABLED   : return("STATUS_DISABLED"   );
   }
   return(_empty(catch("SequenceStatusToStr()  invalid parameter status = "+ status, ERR_INVALID_FUNCTION_PARAMVALUE)));
}
