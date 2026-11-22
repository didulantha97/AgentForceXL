@isTest
private class PMS_WorkOrderLicenceTest {
  private static PMS_Work_Order__c workOrder(Id siteId, Id spaceId) {
    return new PMS_Work_Order__c(
      Site__c = siteId,
      Space__c = spaceId,
      Subject__c = 'Leaking tap',
      Priority__c = 'Medium',
      Status__c = 'New'
    );
  }

  @isTest
  static void deleteAndUndeleteWorkOrdersAndBillsWhileLicensed() {
    PMS_TestDataFactory.Property p = PMS_TestDataFactory.property();
    PMS_Work_Order__c wo = workOrder(p.site.Id, p.unit.Id);
    insert wo;
    PMS_Vendor_Bill__c bill = new PMS_Vendor_Bill__c(
      Site__c = p.site.Id,
      Work_Order__c = wo.Id,
      Amount__c = 100,
      Status__c = 'Submitted'
    );
    insert bill;
    Test.startTest();
    delete bill;
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM PMS_Vendor_Bill__c WHERE Id = :bill.Id]
    );
    undelete bill;
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM PMS_Vendor_Bill__c WHERE Id = :bill.Id]
    );
    delete wo;
    undelete wo;
    Test.stopTest();
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM PMS_Work_Order__c WHERE Id = :wo.Id]
    );
  }

  @isTest
  static void suspendedLicenceBlocksWorkOrderAndBillWrites() {
    PMS_TestDataFactory.Property p = PMS_TestDataFactory.property();
    PMS_Work_Order__c wo = workOrder(p.site.Id, p.unit.Id);
    insert wo;
    PMS_Vendor_Bill__c bill = new PMS_Vendor_Bill__c(
      Site__c = p.site.Id,
      Work_Order__c = wo.Id,
      Amount__c = 100,
      Status__c = 'Submitted'
    );
    insert bill;
    delete bill;
    delete wo;

    PMS_Entitlements.forceStateForTest(PMS_Entitlements.SUSPENDED);
    Test.startTest();
    Database.UndeleteResult uw = Database.undelete(wo.Id, false);
    Assert.isFalse(uw.isSuccess(), 'restoring a work order is a locked write');
    Database.UndeleteResult ub = Database.undelete(bill.Id, false);
    Assert.isFalse(ub.isSuccess(), 'restoring a bill is a locked write');

    PMS_Entitlements.forceStateForTest(null);
    undelete wo;
    undelete bill;
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.SUSPENDED);

    Assert.isFalse(
      Database.insert(workOrder(p.site.Id, p.unit.Id), false).isSuccess(),
      'insert work order locked'
    );
    wo.Subject__c = 'Changed';
    Assert.isFalse(
      Database.update(wo, false).isSuccess(),
      'update work order locked'
    );
    bill.Amount__c = 200;
    Assert.isFalse(
      Database.update(bill, false).isSuccess(),
      'update bill locked'
    );
    Assert.isFalse(
      Database.delete(bill, false).isSuccess(),
      'delete bill locked'
    );
    Assert.isFalse(
      Database.delete(wo, false).isSuccess(),
      'delete work order locked'
    );
    Test.stopTest();
    PMS_Entitlements.forceStateForTest(null);
    Assert.areEqual(
      'Leaking tap',
      [SELECT Subject__c FROM PMS_Work_Order__c WHERE Id = :wo.Id].Subject__c,
      'a blocked update changes nothing'
    );
  }
}
