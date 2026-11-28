@isTest
private class PMS_VendorQuoteTriggerTest {
  private static List<PMS_Work_Order__c> workOrders(
    Id siteId,
    Id spaceId,
    Integer n
  ) {
    List<PMS_Work_Order__c> wos = new List<PMS_Work_Order__c>();
    for (Integer i = 0; i < n; i++) {
      wos.add(
        new PMS_Work_Order__c(
          Site__c = siteId,
          Space__c = spaceId,
          Subject__c = 'Job ' + i,
          Priority__c = 'Medium',
          Status__c = 'New'
        )
      );
    }
    insert wos;
    return wos;
  }

  private static PMS_Vendor_Quote__c quote(
    Id woId,
    Id vendorId,
    Decimal amount,
    Decimal tax
  ) {
    return new PMS_Vendor_Quote__c(
      Work_Order__c = woId,
      Vendor_Account__c = vendorId,
      Amount__c = amount,
      Tax_Amount__c = tax,
      Status__c = 'Submitted'
    );
  }

  @isTest
  static void acceptingOneQuoteApprovesWorkOrderAndRejectsCompetitors() {
    PMS_TestDataFactory.Property p = PMS_TestDataFactory.property();
    Account vendorA = PMS_TestDataFactory.account('Vendor A');
    Account vendorB = PMS_TestDataFactory.account('Vendor B');
    PMS_Work_Order__c wo = workOrders(p.site.Id, p.unit.Id, 1)[0];
    PMS_Vendor_Quote__c qa = quote(wo.Id, vendorA.Id, 1000, 250);
    PMS_Vendor_Quote__c qb = quote(wo.Id, vendorB.Id, 900, 225);
    insert new List<PMS_Vendor_Quote__c>{ qa, qb };

    Test.startTest();
    qa.Status__c = 'Accepted';
    update qa;
    Test.stopTest();

    PMS_Work_Order__c w = [
      SELECT Status__c, Not_To_Exceed__c, Vendor_Account__c
      FROM PMS_Work_Order__c
      WHERE Id = :wo.Id
    ];
    Assert.areEqual('Approved', w.Status__c);
    Assert.areEqual(1250, w.Not_To_Exceed__c, 'amount plus tax');
    Assert.areEqual(vendorA.Id, w.Vendor_Account__c);
    PMS_Vendor_Quote__c other = [
      SELECT Status__c, Decision_Notes__c
      FROM PMS_Vendor_Quote__c
      WHERE Id = :qb.Id
    ];
    Assert.areEqual('Rejected', other.Status__c);
    Assert.areEqual('Another quote was accepted.', other.Decision_Notes__c);
    Assert.areEqual(
      'Accepted',
      [SELECT Status__c FROM PMS_Vendor_Quote__c WHERE Id = :qa.Id].Status__c
    );
  }

  @isTest
  static void acceptWithNullTaxUsesAmountOnly() {
    PMS_TestDataFactory.Property p = PMS_TestDataFactory.property();
    PMS_Work_Order__c wo = workOrders(p.site.Id, p.unit.Id, 1)[0];
    PMS_Vendor_Quote__c q = quote(
      wo.Id,
      PMS_TestDataFactory.account('Vendor A').Id,
      500,
      null
    );
    insert q;
    q.Status__c = 'Accepted';
    update q;
    Assert.areEqual(
      500,
      [SELECT Not_To_Exceed__c FROM PMS_Work_Order__c WHERE Id = :wo.Id]
      .Not_To_Exceed__c
    );
  }

  @isTest
  static void insertedAsAcceptedApprovesWorkOrder() {
    PMS_TestDataFactory.Property p = PMS_TestDataFactory.property();
    PMS_Work_Order__c wo = workOrders(p.site.Id, p.unit.Id, 1)[0];
    PMS_Vendor_Quote__c q = quote(
      wo.Id,
      PMS_TestDataFactory.account('Vendor A').Id,
      300,
      75
    );
    q.Status__c = 'Accepted';
    insert q;
    PMS_Work_Order__c w = [
      SELECT Status__c, Not_To_Exceed__c
      FROM PMS_Work_Order__c
      WHERE Id = :wo.Id
    ];
    Assert.areEqual('Approved', w.Status__c);
    Assert.areEqual(375, w.Not_To_Exceed__c);
  }

  @isTest
  static void twoAcceptedQuotesForSameWorkOrderInOneDmlIsRejected() {
    PMS_TestDataFactory.Property p = PMS_TestDataFactory.property();
    PMS_Work_Order__c wo = workOrders(p.site.Id, p.unit.Id, 1)[0];
    Account v = PMS_TestDataFactory.account('Vendor A');
    PMS_Vendor_Quote__c q1 = quote(wo.Id, v.Id, 100, 0);
    PMS_Vendor_Quote__c q2 = quote(wo.Id, v.Id, 200, 0);
    insert new List<PMS_Vendor_Quote__c>{ q1, q2 };
    q1.Status__c = 'Accepted';
    q2.Status__c = 'Accepted';
    List<Database.SaveResult> res = Database.update(
      new List<PMS_Vendor_Quote__c>{ q1, q2 },
      false
    );
    Assert.isTrue(res[0].isSuccess(), 'first accepted quote wins');
    Assert.isFalse(res[1].isSuccess(), 'second is refused');
    Assert.isTrue(
      res[1].getErrors()[0]
        .getMessage()
        .contains('Only one quote per work order can be accepted.')
    );
    Assert.areEqual(
      100,
      [SELECT Not_To_Exceed__c FROM PMS_Work_Order__c WHERE Id = :wo.Id]
      .Not_To_Exceed__c
    );
  }

  @isTest
  static void rejectingAQuoteDoesNotTouchWorkOrder() {
    PMS_TestDataFactory.Property p = PMS_TestDataFactory.property();
    PMS_Work_Order__c wo = workOrders(p.site.Id, p.unit.Id, 1)[0];
    PMS_Vendor_Quote__c q = quote(
      wo.Id,
      PMS_TestDataFactory.account('Vendor A').Id,
      100,
      0
    );
    insert q;
    q.Status__c = 'Rejected';
    q.Decision_Notes__c = 'Too expensive';
    update q;
    Assert.areEqual(
      'Rejected',
      [SELECT Status__c FROM PMS_Vendor_Quote__c WHERE Id = :q.Id].Status__c
    );
    Assert.areEqual(
      'New',
      [SELECT Status__c FROM PMS_Work_Order__c WHERE Id = :wo.Id].Status__c
    );
  }

  @isTest
  static void insertedAsRejectedIsNotADecisionAndWithdrawnIsIgnored() {
    PMS_TestDataFactory.Property p = PMS_TestDataFactory.property();
    PMS_Work_Order__c wo = workOrders(p.site.Id, p.unit.Id, 1)[0];
    Account v = PMS_TestDataFactory.account('Vendor A');
    PMS_Vendor_Quote__c r = quote(wo.Id, v.Id, 100, 0);
    r.Status__c = 'Rejected';
    PMS_Vendor_Quote__c w = quote(wo.Id, v.Id, 100, 0);
    insert new List<PMS_Vendor_Quote__c>{ r, w };
    w.Status__c = 'Withdrawn';
    update w;
    Assert.areEqual(
      'New',
      [SELECT Status__c FROM PMS_Work_Order__c WHERE Id = :wo.Id].Status__c
    );
  }

  @isTest
  static void updateWithoutStatusChangeIsIgnored() {
    PMS_TestDataFactory.Property p = PMS_TestDataFactory.property();
    PMS_Work_Order__c wo = workOrders(p.site.Id, p.unit.Id, 1)[0];
    PMS_Vendor_Quote__c q = quote(
      wo.Id,
      PMS_TestDataFactory.account('Vendor A').Id,
      100,
      0
    );
    q.Status__c = 'Accepted';
    insert q;
    PMS_Work_Order__c w = [SELECT Id FROM PMS_Work_Order__c WHERE Id = :wo.Id];
    w.Status__c = 'In Progress';
    update w;
    q.Description__c = 'edited';
    update q;
    Assert.areEqual(
      'In Progress',
      [SELECT Status__c FROM PMS_Work_Order__c WHERE Id = :wo.Id].Status__c,
      'no re-approval'
    );
  }

  @isTest
  static void bulk200QuotesInsertedAsSubmittedMakeNoDecisions() {
    PMS_TestDataFactory.Property p = PMS_TestDataFactory.property();
    List<PMS_Work_Order__c> wos = workOrders(p.site.Id, p.unit.Id, 200);
    Account v = PMS_TestDataFactory.account('Vendor A');
    List<PMS_Vendor_Quote__c> qs = new List<PMS_Vendor_Quote__c>();
    for (PMS_Work_Order__c wo : wos) {
      qs.add(quote(wo.Id, v.Id, 100, 25));
    }
    Test.startTest();
    insert qs;
    Test.stopTest();
    Assert.areEqual(
      200,
      [SELECT COUNT() FROM PMS_Vendor_Quote__c WHERE Status__c = 'Submitted']
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM PMS_Work_Order__c WHERE Status__c = 'Approved']
    );
  }

  @isTest
  static void bulkAcceptAcrossManyWorkOrdersApprovesEachOnce() {
    PMS_TestDataFactory.Property p = PMS_TestDataFactory.property();
    Integer n = 200;
    List<PMS_Work_Order__c> wos = workOrders(p.site.Id, p.unit.Id, n);
    Account v = PMS_TestDataFactory.account('Vendor A');
    Account loser = PMS_TestDataFactory.account('Vendor B');
    List<PMS_Vendor_Quote__c> winners = new List<PMS_Vendor_Quote__c>();
    List<PMS_Vendor_Quote__c> losers = new List<PMS_Vendor_Quote__c>();
    for (PMS_Work_Order__c wo : wos) {
      winners.add(quote(wo.Id, v.Id, 100, 25));
      losers.add(quote(wo.Id, loser.Id, 90, 0));
    }
    insert winners;
    insert losers;
    for (PMS_Vendor_Quote__c q : winners) {
      q.Status__c = 'Accepted';
    }
    Test.startTest();
    update winners;
    Test.stopTest();
    Assert.areEqual(
      n,
      [
        SELECT COUNT()
        FROM PMS_Work_Order__c
        WHERE
          Status__c = 'Approved'
          AND Not_To_Exceed__c = 125
          AND Vendor_Account__c = :v.Id
      ]
    );
    Assert.areEqual(
      n,
      [
        SELECT COUNT()
        FROM PMS_Vendor_Quote__c
        WHERE Status__c = 'Rejected' AND Vendor_Account__c = :loser.Id
      ]
    );
    Assert.areEqual(
      n,
      [SELECT COUNT() FROM PMS_Vendor_Quote__c WHERE Status__c = 'Accepted']
    );
  }

  @isTest
  static void suspendedLicenceBlocksInsertUpdateDeleteAndUndelete() {
    PMS_TestDataFactory.Property p = PMS_TestDataFactory.property();
    PMS_Work_Order__c wo = workOrders(p.site.Id, p.unit.Id, 1)[0];
    Account v = PMS_TestDataFactory.account('Vendor A');
    PMS_Vendor_Quote__c q = quote(wo.Id, v.Id, 100, 0);
    PMS_Vendor_Quote__c gone = quote(wo.Id, v.Id, 50, 0);
    insert new List<PMS_Vendor_Quote__c>{ q, gone };
    delete gone;

    PMS_Entitlements.forceStateForTest(PMS_Entitlements.SUSPENDED);
    Assert.isFalse(
      Database.insert(quote(wo.Id, v.Id, 1, 0), false).isSuccess(),
      'insert locked'
    );
    q.Amount__c = 999;
    Assert.isFalse(Database.update(q, false).isSuccess(), 'update locked');
    q.Status__c = 'Accepted';
    Assert.isFalse(Database.update(q, false).isSuccess(), 'accept locked');
    Assert.isFalse(Database.delete(q, false).isSuccess(), 'delete locked');
    Assert.isFalse(
      Database.undelete(gone.Id, false).isSuccess(),
      'undelete locked'
    );
    Assert.areEqual(
      'New',
      [SELECT Status__c FROM PMS_Work_Order__c WHERE Id = :wo.Id].Status__c
    );

    PMS_Entitlements.forceStateForTest(null);
    undelete gone;
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM PMS_Vendor_Quote__c WHERE Id = :gone.Id]
    );
    Assert.areEqual(
      100,
      [SELECT Amount__c FROM PMS_Vendor_Quote__c WHERE Id = :q.Id].Amount__c,
      'nothing changed while locked'
    );
  }
}
