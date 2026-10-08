//+------------------------------------------------------------------+
//| EA_Reporter.mq5                                                    |
//| EA "reportero": no opera, solo lee el estado de la cuenta (saldo, |
//| posiciones abiertas, operaciones cerradas nuevas) y lo envía por  |
//| HTTP a ea-monitor-live (Supabase Edge Function). Un EA reportero  |
//| por cuenta, enganchado a un solo gráfico cualquiera de esa cuenta |
//| — no toca ni sustituye a los EAs de trading que ya tengas puestos.|
//+------------------------------------------------------------------+
#property copyright "ea_monitor"
#property version   "1.11"
#property strict

input string InpServerUrl       = "https://muvioeiwhiwlcvbqiljn.supabase.co/functions/v1/ingest";
input string InpAuthToken       = "";   // token de esta cuenta (te lo doy al darla de alta)
input int    InpPushIntervalSec = 60;   // cada cuanto se manda el estado completo
input int    InpHistoryLookbackMin = 15; // ventana de solape al buscar cierres nuevos (minutos)
input bool   InpSendCandles     = true; // v1.1: mandar velas de los simbolos con posicion abierta (grafico en ea_monitor)
input int    InpCandlesIntervalSec = 300; // cada cuanto se refrescan las velas (un simbolo nuevo se manda enseguida)

datetime g_lastHistoryCheck = 0;
datetime g_lastCandles = 0;        // hora local del ultimo refresco periodico de velas
string   g_candleSymbols = "|";    // simbolos cuyas velas ya se mandaron (formato "|NDX|EURUSD|")

//+------------------------------------------------------------------+
int OnInit() {
  g_lastHistoryCheck = TimeCurrent() - InpHistoryLookbackMin * 60;
  EventSetTimer(InpPushIntervalSec);
  Print("EA_Reporter iniciado. Enviando a ", InpServerUrl, " cada ", InpPushIntervalSec, "s.");
  return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
  EventKillTimer();
}

void OnTimer() {
  SendSnapshot();
  MaybeSendCandles();
}

// Envío inmediato extra al cerrarse una operación, para que no haya que
// esperar al siguiente tick del timer para verla en el panel.
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result) {
  if (trans.type == TRADE_TRANSACTION_DEAL_ADD) {
    SendSnapshot();
  }
}

//+------------------------------------------------------------------+
//| Construye el JSON y lo envía. No revienta si falla — solo avisa. |
//+------------------------------------------------------------------+
void SendSnapshot() {
  if (InpAuthToken == "") {
    Print("EA_Reporter: falta InpAuthToken, no se envía nada.");
    return;
  }

  string json = "{";
  json += "\"mt5_login\":\"" + IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN)) + "\",";
  json += "\"account\":" + BuildAccountJson() + ",";
  json += "\"open_positions\":" + BuildOpenPositionsJson() + ",";
  json += "\"closed_trades\":" + BuildClosedTradesJson();
  json += "}";

  uchar data[];
  int written = StringToCharArray(json, data, 0, StringLen(json), CP_UTF8);
  int len = written;
  while (len > 0 && data[len - 1] == 0) len--; // quita los \0 finales (sin asumir que es solo uno)
  ArrayResize(data, len);

  uchar result[];
  string resultHeaders;
  string headers = "Content-Type: application/json\r\nAuthorization: Bearer " + InpAuthToken + "\r\n";

  ResetLastError();
  int status = WebRequest("POST", InpServerUrl, headers, 5000, data, result, resultHeaders);

  if (status == -1) {
    int err = GetLastError();
    Print("EA_Reporter: WebRequest falló, error ", err,
          err == 4014 ? " (URL no autorizada — añádela en Herramientas > Opciones > Asesores Expertos)" : "");
    return;
  }
  if (status != 200) {
    Print("EA_Reporter: servidor respondió ", status, " -> ", CharArrayToString(result));
    return;
  }
  g_lastHistoryCheck = TimeCurrent() - InpHistoryLookbackMin * 60; // avanza la ventana solo si fue bien
}

//+------------------------------------------------------------------+
//| v1.1 -- Velas de los simbolos con posicion abierta                |
//| Un POST aparte por simbolo (cuerpo con "candles_only"), para no   |
//| engordar el envio principal ni arriesgar su timeout. Un simbolo   |
//| NUEVO se manda en el siguiente timer; los ya enviados se refrescan|
//| cada InpCandlesIntervalSec. Si MT5 aun no tiene el historial de   |
//| un simbolo (CopyRates devuelve <=0) se reintenta en el siguiente. |
//+------------------------------------------------------------------+
void MaybeSendCandles() {
  if (!InpSendCandles || InpAuthToken == "") return;

  // Simbolos con posicion abierta ahora mismo.
  string openSyms[];
  int nOpen = 0;
  int total = PositionsTotal();
  for (int i = 0; i < total; i++) {
    ulong ticket = PositionGetTicket(i);
    if (!PositionSelectByTicket(ticket)) continue;
    string sym = PositionGetString(POSITION_SYMBOL);
    bool dup = false;
    for (int k = 0; k < nOpen; k++) if (openSyms[k] == sym) { dup = true; break; }
    if (dup) continue;
    ArrayResize(openSyms, nOpen + 1);
    openSyms[nOpen++] = sym;
  }

  // Olvida los simbolos ya cerrados: si vuelve a abrirse uno, sus velas se mandan enseguida.
  string kept = "|";
  for (int k = 0; k < nOpen; k++)
    if (StringFind(g_candleSymbols, "|" + openSyms[k] + "|") >= 0) kept += openSyms[k] + "|";
  g_candleSymbols = kept;

  bool periodicDue = (TimeLocal() - g_lastCandles) >= InpCandlesIntervalSec;
  bool sentAny = false;
  for (int k = 0; k < nOpen; k++) {
    bool isNew = StringFind(g_candleSymbols, "|" + openSyms[k] + "|") < 0;
    if (!isNew && !periodicDue) continue;
    if (PostCandles(openSyms[k])) {
      if (isNew) g_candleSymbols += openSyms[k] + "|";
      sentAny = true;
    }
  }
  if (periodicDue && (sentAny || nOpen == 0)) g_lastCandles = TimeLocal();
}

bool PostCandles(string sym) {
  ENUM_TIMEFRAMES tfs[4]  = {PERIOD_M5, PERIOD_M15, PERIOD_H1, PERIOD_H4};
  string          names[4] = {"M5", "M15", "H1", "H4"};
  int             counts[4] = {288, 300, 300, 200};
  int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);

  string arr = "[";
  bool firstTf = true;
  for (int t = 0; t < 4; t++) {
    MqlRates rates[];
    ArraySetAsSeries(rates, false);   // orden cronologico (la mas antigua primero)
    int got = CopyRates(sym, tfs[t], 0, counts[t], rates);
    if (got <= 0) continue;
    if (!firstTf) arr += ",";
    firstTf = false;
    arr += "{\"tf\":\"" + names[t] + "\",\"bars\":[";
    for (int i = 0; i < got; i++) {
      if (i > 0) arr += ",";
      arr += "[" + IntegerToString((long)rates[i].time) + "," +
             DoubleToString(rates[i].open, digits) + "," + DoubleToString(rates[i].high, digits) + "," +
             DoubleToString(rates[i].low, digits) + "," + DoubleToString(rates[i].close, digits) + "]";
    }
    arr += "]}";
  }
  arr += "]";
  if (firstTf) return false;   // MT5 aun no tenia historial de este simbolo

  string json = "{\"mt5_login\":\"" + IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN)) + "\"," +
                "\"candles_only\":true,\"symbol\":\"" + JsonEscape(sym) + "\",\"candles\":" + arr + "}";

  uchar data[];
  int written = StringToCharArray(json, data, 0, StringLen(json), CP_UTF8);
  int len = written;
  while (len > 0 && data[len - 1] == 0) len--;
  ArrayResize(data, len);

  uchar result[];
  string resultHeaders;
  string headers = "Content-Type: application/json\r\nAuthorization: Bearer " + InpAuthToken + "\r\n";
  ResetLastError();
  int status = WebRequest("POST", InpServerUrl, headers, 10000, data, result, resultHeaders);
  if (status == -1) {
    Print("EA_Reporter: WebRequest de velas fallo (", sym, "), error ", GetLastError());
    return false;
  }
  if (status != 200) {
    Print("EA_Reporter: velas de ", sym, " -> servidor respondio ", status, " -> ", CharArrayToString(result));
    return false;
  }
  return true;
}

//+------------------------------------------------------------------+
string BuildAccountJson() {
  string s = "{";
  s += "\"balance\":" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + ",";
  s += "\"equity\":" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + ",";
  s += "\"margin\":" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN), 2) + ",";
  s += "\"free_margin\":" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2) + ",";
  s += "\"margin_level\":" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL), 2) + ",";
  s += "\"currency\":\"" + AccountInfoString(ACCOUNT_CURRENCY) + "\",";
  s += "\"broker\":\"" + JsonEscape(AccountInfoString(ACCOUNT_COMPANY)) + "\",";
  // v1.11 -- permisos de trading automatico. ea_monitor avisa por Telegram si el
  // SERVIDOR deja de permitir EAs (trade_expert / trade_allowed = false) o si el
  // boton "Trading algoritmico" del terminal esta apagado (terminal_trade_allowed).
  s += "\"trade_expert\":" + JsonBool(AccountInfoInteger(ACCOUNT_TRADE_EXPERT) != 0) + ",";
  s += "\"trade_allowed\":" + JsonBool(AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) != 0) + ",";
  s += "\"terminal_trade_allowed\":" + JsonBool(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) != 0);
  s += "}";
  return s;
}

string JsonBool(bool b) {
  return b ? "true" : "false";
}

//+------------------------------------------------------------------+
string BuildOpenPositionsJson() {
  string s = "[";
  int total = PositionsTotal();
  for (int i = 0; i < total; i++) {
    ulong ticket = PositionGetTicket(i);
    if (!PositionSelectByTicket(ticket)) continue;
    if (i > 0) s += ",";
    s += "{";
    s += "\"ticket\":\"" + IntegerToString((long)ticket) + "\",";
    s += "\"symbol\":\"" + PositionGetString(POSITION_SYMBOL) + "\",";
    s += "\"type\":\"" + (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? "buy" : "sell") + "\",";
    s += "\"volume\":" + DoubleToString(PositionGetDouble(POSITION_VOLUME), 2) + ",";
    s += "\"open_price\":" + DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN), 5) + ",";
    s += "\"open_time\":\"" + TimeToIsoString((datetime)PositionGetInteger(POSITION_TIME)) + "\",";
    s += "\"sl\":" + DoubleToString(PositionGetDouble(POSITION_SL), 5) + ",";
    s += "\"tp\":" + DoubleToString(PositionGetDouble(POSITION_TP), 5) + ",";
    s += "\"profit\":" + DoubleToString(PositionGetDouble(POSITION_PROFIT), 2) + ",";
    s += "\"swap\":" + DoubleToString(PositionGetDouble(POSITION_SWAP), 2) + ",";
    s += "\"magic\":" + IntegerToString((long)PositionGetInteger(POSITION_MAGIC)) + ",";
    s += "\"comment\":\"" + JsonEscape(PositionGetString(POSITION_COMMENT)) + "\"";
    s += "}";
  }
  s += "]";
  return s;
}

//+------------------------------------------------------------------+
// Operaciones cerradas desde la última ventana comprobada (con un margen de
// solape de InpHistoryLookbackMin minutos — mandar alguna repetida no pasa
// nada, el servidor la ignora por el ticket, mejor eso que perder alguna).
string BuildClosedTradesJson() {
  string s = "[";
  if (!HistorySelect(g_lastHistoryCheck, TimeCurrent())) return "[]";

  int total = HistoryDealsTotal();
  bool first = true;
  for (int i = 0; i < total; i++) {
    ulong dealTicket = HistoryDealGetTicket(i);
    if (dealTicket == 0) continue;
    // Solo cierres de posición (DEAL_ENTRY_OUT), no las entradas ni depósitos/retiros.
    if ((ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
    ENUM_DEAL_TYPE dtype = (ENUM_DEAL_TYPE)HistoryDealGetInteger(dealTicket, DEAL_TYPE);
    if (dtype != DEAL_TYPE_BUY && dtype != DEAL_TYPE_SELL) continue;

    ulong posId = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
    double openPrice = 0; datetime openTime = 0;
    FindOpeningPrice(posId, dealTicket, openPrice, openTime);

    if (!first) s += ",";
    first = false;
    s += "{";
    s += "\"ticket\":\"" + IntegerToString((long)posId) + "\",";
    s += "\"symbol\":\"" + HistoryDealGetString(dealTicket, DEAL_SYMBOL) + "\",";
    s += "\"type\":\"" + (dtype == DEAL_TYPE_SELL ? "buy" : "sell") + "\","; // el cierre de una compra es una venta y viceversa
    s += "\"volume\":" + DoubleToString(HistoryDealGetDouble(dealTicket, DEAL_VOLUME), 2) + ",";
    s += "\"open_price\":" + DoubleToString(openPrice, 5) + ",";
    s += "\"close_price\":" + DoubleToString(HistoryDealGetDouble(dealTicket, DEAL_PRICE), 5) + ",";
    s += "\"open_time\":\"" + TimeToIsoString(openTime) + "\",";
    s += "\"close_time\":\"" + TimeToIsoString((datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME)) + "\",";
    s += "\"profit\":" + DoubleToString(HistoryDealGetDouble(dealTicket, DEAL_PROFIT), 2) + ",";
    s += "\"commission\":" + DoubleToString(HistoryDealGetDouble(dealTicket, DEAL_COMMISSION), 2) + ",";
    s += "\"swap\":" + DoubleToString(HistoryDealGetDouble(dealTicket, DEAL_SWAP), 2) + ",";
    s += "\"magic\":" + IntegerToString((long)HistoryDealGetInteger(dealTicket, DEAL_MAGIC)) + ",";
    s += "\"comment\":\"" + JsonEscape(HistoryDealGetString(dealTicket, DEAL_COMMENT)) + "\"";
    s += "}";
  }
  s += "]";
  return s;
}

// Busca el deal de apertura (DEAL_ENTRY_IN) de la misma posición para sacar
// precio y hora de entrada — un cierre por sí solo no los trae.
void FindOpeningPrice(ulong posId, ulong closingDeal, double &outPrice, datetime &outTime) {
  outPrice = 0; outTime = 0;
  int total = HistoryDealsTotal();
  for (int i = 0; i < total; i++) {
    ulong t = HistoryDealGetTicket(i);
    if (t == 0 || t == closingDeal) continue;
    if (HistoryDealGetInteger(t, DEAL_POSITION_ID) != posId) continue;
    if ((ENUM_DEAL_ENTRY)HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
    outPrice = HistoryDealGetDouble(t, DEAL_PRICE);
    outTime  = (datetime)HistoryDealGetInteger(t, DEAL_TIME);
    return;
  }
}

//+------------------------------------------------------------------+
string TimeToIsoString(datetime t) {
  if (t <= 0) return "";
  return TimeToString(t, TIME_DATE | TIME_SECONDS);
}

string JsonEscape(string s) {
  StringReplace(s, "\\", "\\\\");
  StringReplace(s, "\"", "\\\"");
  return s;
}
//+------------------------------------------------------------------+
