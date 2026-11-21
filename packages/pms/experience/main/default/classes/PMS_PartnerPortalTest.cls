@isTest
private class PMS_PartnerPortalTest {
  private static final String PDF = EncodingUtil.base64Encode(
    Blob.valueOf('%PDF-1.4 test')
  );

  private class World {
    PMS_ExperienceTestFactory.Property p;
    Account owner;
    Account vendor;
    PMS_Booking__c lease;
    PMS_Invoice__c invoice;
    Case request;
  }

  private static World world() {
    World w = new World();
    w.p = PMS_ExperienceTestFactory.property();
    w.owner = PMS_ExperienceTestFactory.account('Owner Holdings AB');
    w.vendor = PMS_ExperienceTestFactory.account('Pipe Fixers AB');
    update new PMS_Site__c(
      Id = w.p.site.Id,
      Owner_Account__c = w.owner.Id,
      Management_Fee_Percent__c = 10,
      Currency_Code__c = 'SEK'
    );

    PMS_BookingService.BookingRequest r = new PMS_BookingService.BookingRequest();
    r.module = 'Property';
    r.siteId = w.p.site.Id;
    r.spaceId = w.p.unit.Id;
    r.accountId = w.p.tenant.Id;
    r.startDate = Date.today().toStartOfMonth().addMonths(-2);
    r.endDate = Date.today().addMonths(10);
    r.status = 'Active';
    w.lease = PMS_BookingService.createBooking(r);
    w.invoice = new PMS_Invoice__c(
      RecordTypeId = PMS_ModuleConfig.invoiceRecordTypeId('Property'),
      Account__c = w.p.tenant.Id,
      Booking__c = w.lease.Id,
      Issue_Date__c = Date.today(),
      Due_Date__c = Date.today(),
      Subtotal__c = 9000,
      Tax_Total__c = 0,
      Amount_Paid__c = 0,
      Status__c = 'Issued'
    );
    insert w.invoice;
    insert new PMS_Payment__c(
      Account__c = w.p.tenant.Id,
      Invoice__c = w.invoice.Id,
      Booking__c = w.lease.Id,
      Amount__c = 9000,
      Payment_Type__c = 'Payment',
      Method__c = 'Bank Transfer',
      Received_Date__c = Date.today(),
      Status__c = 'Succeeded',
      Gateway_Reference__c = 'test-rent-1'
    );
    w.request = new Case(
      Subject = 'Leaking tap in A-101',
      Description = 'Kitchen tap drips constantly.',
      Origin = 'Phone',
      Status = 'New',
      PMS_Module__c = 'Property',
      PMS_Site__c = w.p.site.Id,
      PMS_Space__c = w.p.unit.Id,
      Entry_Permission__c = true
    );
    insert w.request;
    return w;
  }

  private static PMS_Work_Order__c workOrder(World w) {
    PMS_Work_Order__c wo = new PMS_Work_Order__c(
      Case__c = w.request.Id,
      Vendor_Account__c = w.vendor.Id
    );
    insert wo;
    return [
      SELECT
        Id,
        Name,
        Status__c,
        Site__c,
        Space__c,
        Subject__c,
        Description__c,
        Entry_Permission__c,
        Currency_Code__c
      FROM PMS_Work_Order__c
      WHERE Id = :wo.Id
    ];
  }

  private static String money(
    Decimal amount,
    Decimal tax,
    Map<String, Object> extra
  ) {
    Map<String, Object> m = new Map<String, Object>{
      'amount' => amount,
      'tax' => tax
    };
    m.putAll(extra);
    return JSON.serialize(m);
  }

  // ------------------------------------------------------------------ owners

  @isTest
  static void ownerSeesLiveFiguresAndOnlyPublishedStatements() {
    World w = world();
    PMS_PartnerPortalController.testAccountId = w.owner.Id;

    PMS_PartnerPortalController.Home h = PMS_PartnerPortalController.getHome();
    Assert.isTrue(h.isOwner);
    Assert.isFalse(h.isVendor);
    Assert.areEqual(1, h.sites.size());
    PMS_PartnerPortalController.SiteSummary s = h.sites[0];
    PMS_ExperienceTestFactory.num(
      9000,
      s.monthToDate.getGross(),
      'income this month'
    );
    PMS_ExperienceTestFactory.num(900, s.monthToDate.getFee(), '10% fee');
    PMS_ExperienceTestFactory.num(8100, s.monthToDate.getNet(), 'net');
    Assert.areEqual(1, s.units.size());
    Assert.areEqual('Let', s.units[0].status);
    Assert.isTrue(
      s.monthToDate.getOccupancyBasis().startsWith('1 of 1 units let'),
      s.monthToDate.getOccupancyBasis()
    );
    Assert.areEqual(0, h.statements.size());

    Assert.areEqual(1, PMS_OwnerStatementService.generate(Date.today()));
    PMS_Owner_Statement__c st = [
      SELECT Id, Status__c, Gross_Rent__c, Net_Payout__c, Occupancy_Percent__c
      FROM PMS_Owner_Statement__c
    ];
    Assert.areEqual('Draft', st.Status__c);
    PMS_ExperienceTestFactory.num(8100, st.Net_Payout__c, 'statement net');
    Assert.areEqual(
      0,
      PMS_PartnerPortalController.getHome().statements.size(),
      'Drafts are not shown'
    );

    st.Status__c = 'Published';
    update st;
    h = PMS_PartnerPortalController.getHome();
    Assert.areEqual(1, h.statements.size());
    PMS_PartnerPortalController.StatementDetail d = PMS_PartnerPortalController.getStatement(
      st.Id
    );
    Assert.areEqual(1, d.income.size());
    PMS_ExperienceTestFactory.num(10, d.feePercent, 'fee %');

    Assert.areEqual(
      0,
      PMS_OwnerStatementService.generate(Date.today()),
      'Published statements are frozen'
    );

    PMS_PartnerPortalController.testAccountId = w.vendor.Id;
    try {
      PMS_PartnerPortalController.getStatement(st.Id);
      Assert.fail('Another account must not see the statement');
    } catch (AuraHandledException e) {
      Assert.areEqual('Statement not found.', e.getMessage());
    }
  }

  @isTest
  static void nightlyJobBuildsStatements() {
    World w = world();
    Test.startTest();
    Database.executeBatch(
      new PMS_OwnerStatementJob(Date.today().toStartOfMonth().addDays(2)),
      10
    );
    Test.stopTest();
    Assert.areEqual(
      2,
      [SELECT COUNT() FROM PMS_Owner_Statement__c],
      'This month and last month (early in the month)'
    );
    new PMS_OwnerStatementJob().execute((SchedulableContext) null);
  }

  @isTest
  static void hotelOccupancyCountsRoomNights() {
    PMS_ExperienceTestFactory.Hotel h = PMS_ExperienceTestFactory.hotel(2);
    Account owner = PMS_ExperienceTestFactory.account('Hotel Owner');
    update new PMS_Site__c(Id = h.site.Id, Owner_Account__c = owner.Id);
    Date monday = PMS_ExperienceTestFactory.futureMonday();
    PMS_BookingService.createBooking(
      PMS_ExperienceTestFactory.hotelRequest(h, monday, 2)
    );
    PMS_OwnerStatementService.Figures f = PMS_OwnerStatementService.compute(
      PMS_OwnerStatementService.site(h.site.Id),
      monday,
      monday.addDays(4)
    );
    Assert.areEqual('2 of 10 room nights', f.getOccupancyBasis());
    PMS_ExperienceTestFactory.num(20.0, f.getOccupancyPct(), 'occupancy');
  }

  // ------------------------------------------------------------------ vendors

  @isTest
  static void vendorWorksAJobFromAssignmentToInvoice() {
    World w = world();
    PMS_Work_Order__c wo = workOrder(w);
    Assert.areEqual(
      'Assigned',
      wo.Status__c,
      'A vendor on a new work order means Assigned'
    );
    Assert.areEqual(w.p.site.Id, wo.Site__c, 'Copied from the case');
    Assert.areEqual(w.p.unit.Id, wo.Space__c);
    Assert.areEqual('Leaking tap in A-101', wo.Subject__c);
    Assert.isTrue(wo.Entry_Permission__c);
    Assert.areEqual('SEK', wo.Currency_Code__c);

    PMS_PartnerPortalController.testAccountId = w.vendor.Id;
    PMS_PartnerPortalController.Home h = PMS_PartnerPortalController.getHome();
    Assert.isTrue(h.isVendor);
    Assert.isFalse(h.isOwner);
    Assert.areEqual(1, h.workOrders.size());
    Assert.isTrue(h.workOrders[0].canAccept);

    PMS_PartnerPortalController.WorkOrderRow r = PMS_PartnerPortalController.acceptWorkOrder(
      wo.Id
    );
    Assert.areEqual('Accepted', r.status);

    r = PMS_PartnerPortalController.submitQuote(
      wo.Id,
      money(
        1200,
        300,
        new Map<String, Object>{
          'description' => 'Replace tap cartridge',
          'validUntil' => String.valueOf(Date.today().addDays(30))
        }
      ),
      'quote.pdf',
      PDF
    );
    Assert.areEqual('Quoted', r.status);
    Assert.areEqual(1, r.quotes.size());
    PMS_ExperienceTestFactory.num(1500, r.quotes[0].total, 'quote total');
    Assert.areEqual(1, r.files.size());
    Assert.areEqual('Quote', r.files[0].kind);

    r = PMS_PartnerPortalController.submitQuote(
      wo.Id,
      money(
        1000,
        250,
        new Map<String, Object>{ 'description' => 'Revised: cartridge only' }
      ),
      null,
      null
    );
    Assert.areEqual(2, r.quotes.size());
    Assert.areEqual(
      'Withdrawn',
      [SELECT Status__c FROM PMS_Vendor_Quote__c WHERE Amount__c = 1200]
      .Status__c
    );

    Test.startTest();
    PMS_Vendor_Quote__c q = [
      SELECT Id
      FROM PMS_Vendor_Quote__c
      WHERE Status__c = 'Submitted'
    ];
    q.Status__c = 'Accepted';
    update q;
    PMS_Work_Order__c approved = [
      SELECT Status__c, Not_To_Exceed__c
      FROM PMS_Work_Order__c
      WHERE Id = :wo.Id
    ];
    Assert.areEqual('Approved', approved.Status__c);
    PMS_ExperienceTestFactory.num(
      1250,
      approved.Not_To_Exceed__c,
      'approved amount'
    );

    r = PMS_PartnerPortalController.startWork(wo.Id);
    Assert.areEqual('In Progress', r.status);
    r = PMS_PartnerPortalController.uploadFile(
      wo.Id,
      'Photo',
      'before.jpg',
      'data:image/jpeg;base64,' + PDF
    );
    Assert.areEqual(2, r.files.size());
    try {
      PMS_PartnerPortalController.completeWork(wo.Id, '  ');
      Assert.fail('Notes are required');
    } catch (AuraHandledException e) {
      Assert.areEqual('Describe what was done.', e.getMessage());
    }
    r = PMS_PartnerPortalController.completeWork(
      wo.Id,
      'Replaced cartridge, tested, no leak.'
    );
    Assert.areEqual('Completed', r.status);
    Assert.isTrue(r.canBill);

    r = PMS_PartnerPortalController.submitBill(
      wo.Id,
      money(
        1000,
        250,
        new Map<String, Object>{
          'invoiceNumber' => 'F-2026-118',
          'billDate' => String.valueOf(Date.today())
        }
      ),
      'invoice.pdf',
      PDF
    );
    Integer emailInvocations = Limits.getEmailInvocations();
    Test.stopTest();
    Assert.areEqual(1, r.bills.size());
    Assert.isFalse(r.canBill);
    PMS_Vendor_Bill__c bill = [
      SELECT Id, Site__c, Vendor_Account__c, Status__c, Total__c
      FROM PMS_Vendor_Bill__c
    ];
    Assert.areEqual(w.p.site.Id, bill.Site__c);
    Assert.areEqual('Submitted', bill.Status__c);
    try {
      PMS_PartnerPortalController.submitBill(
        wo.Id,
        money(10, 0, new Map<String, Object>{ 'invoiceNumber' => 'X' }),
        'x.pdf',
        PDF
      );
      Assert.fail('One invoice per job');
    } catch (AuraHandledException e) {
      Assert.isTrue(
        e.getMessage().contains('already been sent'),
        e.getMessage()
      );
    }
    Assert.isTrue(
      emailInvocations > 0,
      'Staff were emailed about vendor actions'
    );

    // Approved bill becomes an owner expense.
    bill.Status__c = 'Approved';
    update bill;
    PMS_OwnerStatementService.generate(Date.today());
    PMS_Owner_Statement__c st = [
      SELECT Expenses__c, Net_Payout__c
      FROM PMS_Owner_Statement__c
    ];
    PMS_ExperienceTestFactory.num(1250, st.Expenses__c, 'expenses');
    PMS_ExperienceTestFactory.num(
      9000 - 1250 - 900,
      st.Net_Payout__c,
      'net after expenses'
    );
    Assert.isNotNull(
      [SELECT Owner_Statement__c FROM PMS_Vendor_Bill__c WHERE Id = :bill.Id]
      .Owner_Statement__c
    );
  }

  @isTest
  static void vendorsAreFencedAndInputIsChecked() {
    World w = world();
    PMS_Work_Order__c wo = workOrder(w);
    Account other = PMS_ExperienceTestFactory.account('Other Vendor');
    PMS_PartnerPortalController.testAccountId = other.Id;
    Assert.areEqual(0, PMS_PartnerPortalController.getHome().workOrders.size());
    try {
      PMS_PartnerPortalController.acceptWorkOrder(wo.Id);
      Assert.fail('Not their job');
    } catch (AuraHandledException e) {
      Assert.areEqual('Work order not found.', e.getMessage());
    }

    PMS_PartnerPortalController.testAccountId = w.vendor.Id;
    try {
      PMS_PartnerPortalController.submitQuote(
        wo.Id,
        money(-5, 0, new Map<String, Object>{ 'description' => 'x' }),
        null,
        null
      );
      Assert.fail('Negative amount');
    } catch (AuraHandledException e) {
      Assert.areEqual('Enter the amount excluding tax.', e.getMessage());
    }
    try {
      PMS_PartnerPortalController.submitQuote(wo.Id, 'not json', null, null);
      Assert.fail('Bad JSON');
    } catch (AuraHandledException e) {
      Assert.isNotNull(e.getMessage());
    }
    try {
      PMS_PartnerPortalController.uploadFile(wo.Id, 'Photo', 'virus.exe', PDF);
      Assert.fail('Bad extension');
    } catch (AuraHandledException e) {
      Assert.isTrue(e.getMessage().startsWith('Upload a PDF'), e.getMessage());
    }
    try {
      PMS_PartnerPortalController.completeWork(wo.Id, 'done');
      Assert.fail('Not started');
    } catch (AuraHandledException e) {
      Assert.areEqual('Start the job before completing it.', e.getMessage());
    }
    try {
      PMS_PartnerPortalController.submitBill(
        wo.Id,
        money(5, 0, new Map<String, Object>{ 'invoiceNumber' => '1' }),
        'a.pdf',
        PDF
      );
      Assert.fail('Not completed');
    } catch (AuraHandledException e) {
      Assert.isTrue(
        e.getMessage().startsWith('Complete the job'),
        e.getMessage()
      );
    }

    PMS_PartnerPortalController.testAccountId = null;
    try {
      PMS_PartnerPortalController.getHome();
      Assert.fail('An internal user has no partner account');
    } catch (AuraHandledException e) {
      Assert.isTrue(
        e.getMessage().startsWith('This portal is for owners and vendors'),
        e.getMessage()
      );
    }
  }

  @isTest
  static void staffDecisionsEmailTheVendor() {
    World w = world();
    // Notifications look up the vendor's portal users; a contact is enough to exercise the query path.
    PMS_ExperienceTestFactory.contact(w.vendor.Id, 'Fixer');
    PMS_Work_Order__c wo = workOrder(w);
    insert new PMS_Vendor_Quote__c(
      Work_Order__c = wo.Id,
      Vendor_Account__c = w.vendor.Id,
      Amount__c = 100,
      Tax_Amount__c = 25,
      Status__c = 'Submitted'
    );
    insert new PMS_Vendor_Quote__c(
      Work_Order__c = wo.Id,
      Vendor_Account__c = w.vendor.Id,
      Amount__c = 90,
      Tax_Amount__c = 0,
      Status__c = 'Submitted'
    );
    PMS_Vendor_Quote__c first = [
      SELECT Id
      FROM PMS_Vendor_Quote__c
      WHERE Amount__c = 100
    ];
    first.Status__c = 'Accepted';
    update first;
    Assert.areEqual(
      'Rejected',
      [SELECT Status__c FROM PMS_Vendor_Quote__c WHERE Amount__c = 90]
      .Status__c,
      'Other open quotes are rejected'
    );

    PMS_Vendor_Bill__c b = new PMS_Vendor_Bill__c(
      Work_Order__c = wo.Id,
      Vendor_Invoice_Number__c = 'INV-9',
      Bill_Date__c = Date.today(),
      Amount__c = 100,
      Tax_Amount__c = 25
    );
    insert b;
    b = [
      SELECT Id, Site__c, Vendor_Account__c
      FROM PMS_Vendor_Bill__c
      WHERE Id = :b.Id
    ];
    Assert.areEqual(
      w.vendor.Id,
      b.Vendor_Account__c,
      'Copied from the work order'
    );
    b.Status__c = 'Paid';
    b.Paid_Date__c = Date.today();
    update b;

    update new PMS_Work_Order__c(Id = wo.Id, Status__c = 'Quote Requested');
    Assert.isTrue(PMS_WorkOrderService.money(3500, 'SEK').endsWith(' SEK'));
    Assert.areEqual('', PMS_WorkOrderService.money(null, 'SEK'));
  }

  @isTest
  static void partnerUsersGetThePortalPermissionSet() {
    Map<String, String> m = PMS_PortalUserSetup.PERMSET_BY_PROFILE;
    Assert.areEqual(
      PMS_PortalUserSetup.PARTNER_PERMSET,
      m.get(PMS_PortalUserSetup.PARTNER_PROFILE)
    );
    Assert.areEqual(
      PMS_PortalUserSetup.STRIPE_PERMSET,
      m.get(PMS_PortalUserSetup.PORTAL_PROFILE)
    );
    PMS_PortalUserSetup.assign(new Set<Id>{ UserInfo.getUserId() }); // an internal user gets nothing
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM PermissionSetAssignment
        WHERE
          AssigneeId = :UserInfo.getUserId()
          AND PermissionSet.Name = :PMS_PortalUserSetup.PARTNER_PERMSET
      ]
    );
  }
}
