public class BinanceTicker24hData {
  @AuraEnabled
  @InvocableVariable(label='Success')
  public Boolean success;

  @AuraEnabled
  @InvocableVariable(label='Error Message')
  public String errorMessage;

  @AuraEnabled
  @InvocableVariable(label='Symbol')
  public String symbol;

  @AuraEnabled
  @InvocableVariable(label='Price Change')
  public String priceChange;

  @AuraEnabled
  @InvocableVariable(label='Price Change Percent')
  public String priceChangePercent;

  @AuraEnabled
  @InvocableVariable(label='Weighted Average Price')
  public String weightedAvgPrice;

  @AuraEnabled
  @InvocableVariable(label='Previous Close Price')
  public String prevClosePrice;

  @AuraEnabled
  @InvocableVariable(label='Last Price')
  public String lastPrice;

  @AuraEnabled
  @InvocableVariable(label='Last Quantity')
  public String lastQty;

  @AuraEnabled
  @InvocableVariable(label='Bid Price')
  public String bidPrice;

  @AuraEnabled
  @InvocableVariable(label='Bid Quantity')
  public String bidQty;

  @AuraEnabled
  @InvocableVariable(label='Ask Price')
  public String askPrice;

  @AuraEnabled
  @InvocableVariable(label='Ask Quantity')
  public String askQty;

  @AuraEnabled
  @InvocableVariable(label='Open Price')
  public String openPrice;

  @AuraEnabled
  @InvocableVariable(label='High Price')
  public String highPrice;

  @AuraEnabled
  @InvocableVariable(label='Low Price')
  public String lowPrice;

  @AuraEnabled
  @InvocableVariable(label='Volume')
  public String volume;

  @AuraEnabled
  @InvocableVariable(label='Quote Volume')
  public String quoteVolume;

  @AuraEnabled
  @InvocableVariable(label='Open Time (Epoch Milliseconds)')
  public Long openTime;

  @AuraEnabled
  @InvocableVariable(label='Close Time (Epoch Milliseconds)')
  public Long closeTime;

  @AuraEnabled
  @InvocableVariable(label='First Trade ID')
  public Long firstId;

  @AuraEnabled
  @InvocableVariable(label='Last Trade ID')
  public Long lastId;

  @AuraEnabled
  @InvocableVariable(label='Trade Count')
  public Integer count;
}
