@isTest
private class BinanceTickerFlowActionTest {
  @isTest
  static void returnsBinanceTickerData() {
    Test.setMock(HttpCalloutMock.class, new BinanceMock(200, successBody()));

    BinanceTickerFlowAction.TickerRequest input = new BinanceTickerFlowAction.TickerRequest();
    input.symbol = ' bnbbtc ';

    Test.startTest();
    BinanceTicker24hData result = BinanceTickerFlowAction.getTicker(
        new List<BinanceTickerFlowAction.TickerRequest>{ input }
      )[0]
      .tickerData[0];
    Test.stopTest();

    Assert.isTrue(result.success);
    Assert.areEqual('BNBBTC', result.symbol);
    Assert.areEqual('-94.999998', result.priceChange);
    Assert.areEqual('4.000002', result.lastPrice);
    Assert.areEqual(1499783499040L, result.openTime);
    Assert.areEqual(76, result.count);
  }

  @isTest
  static void returnsApiError() {
    Test.setMock(
      HttpCalloutMock.class,
      new BinanceMock(400, '{"code":-1121,"msg":"Invalid symbol."}')
    );

    BinanceTickerFlowAction.TickerRequest input = new BinanceTickerFlowAction.TickerRequest();
    input.symbol = 'NOTREAL';

    Test.startTest();
    BinanceTicker24hData result = BinanceTickerFlowAction.getTicker(
        new List<BinanceTickerFlowAction.TickerRequest>{ input }
      )[0]
      .tickerData[0];
    Test.stopTest();

    Assert.isFalse(result.success);
    Assert.areEqual('NOTREAL', result.symbol);
    Assert.areEqual(
      'Binance returned HTTP 400: Invalid symbol.',
      result.errorMessage
    );
  }

  @isTest
  static void blankSymbolReturnsAllTickers() {
    Test.setMock(
      HttpCalloutMock.class,
      new BinanceMock(200, '[' + successBody() + ',' + successBody() + ']')
    );
    BinanceTickerFlowAction.TickerRequest input = new BinanceTickerFlowAction.TickerRequest();

    Test.startTest();
    BinanceTickerFlowAction.TickerBatchResponse response = BinanceTickerFlowAction.getTicker(
      new List<BinanceTickerFlowAction.TickerRequest>{ input }
    )[0];
    Test.stopTest();

    Assert.areEqual(2, response.tickerData.size());
    Assert.isTrue(response.tickerData[0].success);
    Assert.isTrue(response.selectedRowsJson.startsWith('[{'));
  }

  @isTest
  static void returnsDataForEverySelectedRow() {
    BinanceTicker24hData firstRow = new BinanceTicker24hData();
    firstRow.symbol = 'BNBBTC';
    firstRow.lastPrice = '4.000002';
    BinanceTicker24hData secondRow = new BinanceTicker24hData();
    secondRow.symbol = 'BTCUSDT';
    secondRow.lastPrice = '90000';

    BinanceTickerFlowAction.TickerRequest input = new BinanceTickerFlowAction.TickerRequest();
    input.selectedRows = new List<BinanceTicker24hData>{ firstRow, secondRow };

    Test.startTest();
    BinanceTickerFlowAction.TickerBatchResponse response = BinanceTickerFlowAction.getTicker(
      new List<BinanceTickerFlowAction.TickerRequest>{ input }
    )[0];
    Test.stopTest();

    Assert.areEqual(2, response.tickerData.size());
    Assert.isNull(response.errorMessage);
    Assert.areEqual('BNBBTC', response.tickerData[0].symbol);
    Assert.areEqual('BTCUSDT', response.tickerData[1].symbol);
    Assert.isTrue(response.selectedRowsJson.contains('BNBBTC'));
    Assert.isTrue(response.selectedRowsJson.contains('BTCUSDT'));
  }

  private static String successBody() {
    return '{' +
      '"symbol":"BNBBTC",' +
      '"priceChange":"-94.999998",' +
      '"priceChangePercent":"-95.96",' +
      '"weightedAvgPrice":"0.29628482",' +
      '"prevClosePrice":"0.10002",' +
      '"lastPrice":"4.000002",' +
      '"lastQty":"200",' +
      '"bidPrice":"4",' +
      '"bidQty":"100",' +
      '"askPrice":"4.000002",' +
      '"askQty":"100",' +
      '"openPrice":"99",' +
      '"highPrice":"100",' +
      '"lowPrice":"0.1",' +
      '"volume":"8913.3",' +
      '"quoteVolume":"15.3",' +
      '"openTime":1499783499040,' +
      '"closeTime":1499869899040,' +
      '"firstId":28385,' +
      '"lastId":28460,' +
      '"count":76' +
      '}';
  }

  private class BinanceMock implements HttpCalloutMock {
    private Integer statusCode;
    private String body;

    private BinanceMock(Integer statusCode, String body) {
      this.statusCode = statusCode;
      this.body = body;
    }

    public HttpResponse respond(HttpRequest request) {
      Assert.areEqual('GET', request.getMethod());
      Assert.isTrue(request.getEndpoint().startsWith('callout:Binance_API/'));

      HttpResponse response = new HttpResponse();
      response.setStatusCode(statusCode);
      response.setBody(body);
      return response;
    }
  }
}
