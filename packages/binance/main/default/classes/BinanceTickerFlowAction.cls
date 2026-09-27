public with sharing class BinanceTickerFlowAction {
  @InvocableMethod(
    label='Get Binance 24-Hour Ticker'
    description='Gets Binance ticker data or converts selected ticker rows to JSON.'
    callout=true
  )
  public static List<TickerBatchResponse> getTicker(
    List<TickerRequest> requests
  ) {
    List<TickerBatchResponse> responses = new List<TickerBatchResponse>();

    if (requests == null) {
      return responses;
    }

    for (TickerRequest request : requests) {
      TickerBatchResponse response = new TickerBatchResponse();
      response.tickerData = new List<BinanceTicker24hData>();

      if (request != null && request.selectedRows != null) {
        response.tickerData.addAll(request.selectedRows);
      } else {
        String symbol = request == null ? null : request.symbol;
        response.tickerData.addAll(callBinance(symbol));
      }

      response.selectedRowsJson = JSON.serialize(response.tickerData);
      responses.add(response);
    }

    return responses;
  }

  private static List<BinanceTicker24hData> callBinance(String symbol) {
    List<BinanceTicker24hData> results = new List<BinanceTicker24hData>();
    String normalizedSymbol = String.isBlank(symbol)
      ? null
      : symbol.trim().toUpperCase();

    try {
      HttpRequest request = new HttpRequest();
      String endpoint = 'callout:Binance_API/api/v3/ticker/24hr';
      if (normalizedSymbol != null) {
        endpoint +=
          '?symbol=' + EncodingUtil.urlEncode(normalizedSymbol, 'UTF-8');
      }
      request.setEndpoint(endpoint);
      request.setMethod('GET');
      request.setTimeout(20000);

      HttpResponse response = new Http().send(request);
      if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
        BinanceTicker24hData result = new BinanceTicker24hData();
        result.success = false;
        result.symbol = normalizedSymbol;
        result.errorMessage = getApiError(response);
        results.add(result);
        return results;
      }

      Object payload = JSON.deserializeUntyped(response.getBody());
      if (payload instanceof List<Object>) {
        for (Object item : (List<Object>) payload) {
          results.add(toTicker((Map<String, Object>) item));
        }
      } else {
        results.add(toTicker((Map<String, Object>) payload));
      }
    } catch (Exception ex) {
      BinanceTicker24hData result = new BinanceTicker24hData();
      result.success = false;
      result.symbol = normalizedSymbol;
      result.errorMessage = 'Binance callout failed: ' + ex.getMessage();
      results.add(result);
    }

    return results;
  }

  private static BinanceTicker24hData toTicker(Map<String, Object> payload) {
    BinanceTicker24hData result = new BinanceTicker24hData();
    mapPayload(payload, result);
    result.success = true;
    return result;
  }

  private static void mapPayload(
    Map<String, Object> payload,
    BinanceTicker24hData result
  ) {
    result.symbol = stringValue(payload.get('symbol'));
    result.priceChange = stringValue(payload.get('priceChange'));
    result.priceChangePercent = stringValue(payload.get('priceChangePercent'));
    result.weightedAvgPrice = stringValue(payload.get('weightedAvgPrice'));
    result.prevClosePrice = stringValue(payload.get('prevClosePrice'));
    result.lastPrice = stringValue(payload.get('lastPrice'));
    result.lastQty = stringValue(payload.get('lastQty'));
    result.bidPrice = stringValue(payload.get('bidPrice'));
    result.bidQty = stringValue(payload.get('bidQty'));
    result.askPrice = stringValue(payload.get('askPrice'));
    result.askQty = stringValue(payload.get('askQty'));
    result.openPrice = stringValue(payload.get('openPrice'));
    result.highPrice = stringValue(payload.get('highPrice'));
    result.lowPrice = stringValue(payload.get('lowPrice'));
    result.volume = stringValue(payload.get('volume'));
    result.quoteVolume = stringValue(payload.get('quoteVolume'));
    result.openTime = longValue(payload.get('openTime'));
    result.closeTime = longValue(payload.get('closeTime'));
    result.firstId = longValue(payload.get('firstId'));
    result.lastId = longValue(payload.get('lastId'));
    result.count = integerValue(payload.get('count'));
  }

  private static String getApiError(HttpResponse response) {
    String message = 'Binance returned HTTP ' + response.getStatusCode();

    try {
      Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
        response.getBody()
      );
      if (body.get('msg') != null) {
        message += ': ' + String.valueOf(body.get('msg'));
      }
    } catch (Exception ignored) {
      // Use the HTTP status when the error body is empty or is not JSON.
    }

    return message;
  }

  private static String stringValue(Object value) {
    return value == null ? null : String.valueOf(value);
  }

  private static Long longValue(Object value) {
    return value == null ? null : Long.valueOf(String.valueOf(value));
  }

  private static Integer integerValue(Object value) {
    return value == null ? null : Integer.valueOf(String.valueOf(value));
  }

  public class TickerRequest {
    @InvocableVariable(
      label='Symbol'
      description='Optional Binance symbol. Leave blank to retrieve all tickers.'
    )
    public String symbol;

    @InvocableVariable(
      label='Selected Rows'
      description='Optional selected rows from a BinanceTicker24hData Flow Data Table.'
    )
    public List<BinanceTicker24hData> selectedRows;
  }

  public class TickerBatchResponse {
    @InvocableVariable(label='Ticker Data')
    public List<BinanceTicker24hData> tickerData;

    @InvocableVariable(label='Error Message')
    public String errorMessage;

    @InvocableVariable(label='Selected Rows JSON')
    public String selectedRowsJson;
  }
}
