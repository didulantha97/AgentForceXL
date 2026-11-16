@isTest
private class PMS_AccessRolloutTest {
  static final String MD = 'http://soap.sforce.com/2006/04/metadata';

  /** Answers the Metadata API calls the way Salesforce does. */
  class MetadataMock implements HttpCalloutMock {
    public Boolean succeed = true;
    public String fault;
    public List<String> bodies = new List<String>();

    public HttpResponse respond(HttpRequest req) {
      String body = req.getBody();
      bodies.add(body);
      HttpResponse res = new HttpResponse();
      res.setHeader('Content-Type', 'text/xml');
      if (fault != null) {
        res.setStatusCode(500);
        res.setBody(
          envelope(
            '<soapenv:Fault><faultcode>sf:INVALID_SESSION_ID</faultcode><faultstring>' +
              fault +
              '</faultstring></soapenv:Fault>'
          )
        );
        return res;
      }
      res.setStatusCode(200);
      if (body.contains('<met:readMetadata><met:type>CustomObject')) {
        String recs = '';
        for (String name : names(body, 'fullNames')) {
          recs +=
            '<records xsi:type="CustomObject"><fullName>' +
            name +
            '</fullName>' +
            '<actionOverrides><actionName>View</actionName><type>Default</type></actionOverrides>' +
            '<deploymentStatus>Deployed</deploymentStatus><enableHistory>true</enableHistory><enableReports>true</enableReports>' +
            '<externalSharingModel>Private</externalSharingModel>' +
            '<fields><fullName>Secret__c</fullName><label>Secret</label><type>Text</type></fields>' +
            '<label>Thing &amp; more</label><nameField><label>Name</label><type>Text</type></nameField>' +
            '<pluralLabel>Things</pluralLabel><sharingModel>ReadWrite</sharingModel></records>';
        }
        res.setBody(
          envelope(
            '<readMetadataResponse><result>' +
              recs +
              '</result></readMetadataResponse>'
          )
        );
      } else if (body.contains('<met:readMetadata>')) {
        res.setBody(
          envelope('<readMetadataResponse><result/></readMetadataResponse>')
        );
      } else {
        String op = body.contains('<met:updateMetadata>')
          ? 'updateMetadataResponse'
          : 'createMetadataResponse';
        String results = '';
        for (String name : names(body, 'fullName')) {
          results += succeed
            ? '<result><fullName>' +
              name +
              '</fullName><success>true</success></result>'
            : '<result><errors><message>Sharing recalculation in progress</message></errors><fullName>' +
              name +
              '</fullName><success>false</success></result>';
        }
        res.setBody(envelope('<' + op + '>' + results + '</' + op + '>'));
      }
      return res;
    }
  }

  static String envelope(String innerXml) {
    // Like Salesforce: response elements carry the metadata namespace, fault children have none.
    String ns = innerXml.startsWith('<soapenv:Fault>')
      ? ''
      : 'xmlns="' + MD + '" ';
    return '<?xml version="1.0" encoding="UTF-8"?><soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" ' +
      ns +
      'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><soapenv:Body>' +
      innerXml +
      '</soapenv:Body></soapenv:Envelope>';
  }

  static List<String> names(String body, String tag) {
    List<String> out = new List<String>();
    Matcher m = Pattern.compile('<met:' + tag + '>([^<]+)</met:' + tag + '>')
      .matcher(body);
    while (m.find()) {
      out.add(m.group(1));
    }
    return out;
  }

  static PMS_Access_Rollout__c row(String name, String target) {
    PMS_Access_Rollout__c r = new PMS_Access_Rollout__c(
      Name = name,
      Target__c = target,
      Step__c = PMS_AccessRollout.STEP_WAITING,
      Attempts__c = 0,
      Ticks__c = 0
    );
    insert r;
    return r;
  }

  static PMS_Access_Rollout__c reload(String name) {
    return [
      SELECT
        Name,
        Target__c,
        Step__c,
        Message__c,
        Requested__c,
        Recalc_Started__c,
        Attempts__c
      FROM PMS_Access_Rollout__c
      WHERE Name = :name
    ];
  }

  static void tick(String owd, Boolean reason, Boolean recalcRunning) {
    PMS_AccessService.owdOverride.put('PMS_Site__c', owd);
    PMS_AccessService.rowCauseOverride = reason ? 'PMS_Access_Rule__c' : null;
    PMS_AccessRollout.recalcRunningOverride = recalcRunning;
    new PMS_AccessRollout().runTick();
  }

  @isTest
  static void applyRulesWalksEveryStep() {
    MetadataMock mock = new MetadataMock();
    PMS_AccessMetadataClient.transport = mock;
    row('PMS_Site__c', 'Private');
    Test.startTest();
    tick('ReadWrite', false, false);
    Assert.areEqual(
      'Changing to Public Read Only',
      reload('PMS_Site__c').Step__c
    );
    Assert.areEqual('Read', reload('PMS_Site__c').Requested__c);

    tick('ReadWrite', false, false);
    Assert.areEqual(
      2,
      mock.bodies.size(),
      'read + update only; the pending change is not sent twice'
    );

    tick('Read', true, false);
    Assert.areEqual('Recalculating', reload('PMS_Site__c').Step__c);
    tick('Read', true, true);
    Assert.areEqual(
      'Recalculating',
      reload('PMS_Site__c').Step__c,
      'waits for the recalculation'
    );
    tick('Read', true, false);
    Assert.areEqual('Changing to Private', reload('PMS_Site__c').Step__c);
    tick('Private', true, false);
    Assert.areEqual('Recalculating (last step)', reload('PMS_Site__c').Step__c);
    tick('Private', true, false);
    Test.stopTest();
    PMS_Access_Rollout__c r = reload('PMS_Site__c');
    Assert.areEqual(PMS_AccessRollout.STEP_DONE, r.Step__c);
    Assert.isFalse(new PMS_AccessRollout().runTick(), 'nothing left to do');
  }

  @isTest
  static void decideAddsSharingReason() {
    PMS_Access_Rollout__c r = new PMS_Access_Rollout__c(
      Name = 'PMS_Booking__c',
      Target__c = 'Private',
      Recalc_Started__c = false
    );
    Map<String, String> setModel = new Map<String, String>();
    List<String> reasons = new List<String>();
    List<String> recalc = new List<String>();
    PMS_AccessRollout.decide(
      r,
      'Read',
      false,
      false,
      setModel,
      reasons,
      recalc
    );
    Assert.areEqual(new List<String>{ 'PMS_Booking__c' }, reasons);
    Assert.areEqual('Adding sharing reason', r.Step__c);
    reasons.clear();
    PMS_AccessRollout.decide(
      r,
      'Read',
      false,
      false,
      setModel,
      reasons,
      recalc
    );
    Assert.isTrue(reasons.isEmpty(), 'not sent twice while pending');

    PMS_Access_Rollout__c child = new PMS_Access_Rollout__c(
      Name = 'PMS_Space__c',
      Target__c = 'Private'
    );
    PMS_AccessRollout.decide(
      child,
      'ControlledByParent',
      false,
      false,
      setModel,
      reasons,
      recalc
    );
    Assert.areEqual(PMS_AccessRollout.STEP_FAILED, child.Step__c);

    PMS_Access_Rollout__c back = new PMS_Access_Rollout__c(
      Name = 'PMS_Invoice__c',
      Target__c = 'Read',
      Recalc_Started__c = false
    );
    PMS_AccessRollout.decide(
      back,
      'Private',
      true,
      false,
      setModel,
      reasons,
      recalc
    );
    Assert.areEqual(
      'Read',
      setModel.get('PMS_Invoice__c'),
      'Private back to Read Only'
    );
  }

  @isTest
  static void turnRulesOffAndCreateReason() {
    MetadataMock mock = new MetadataMock();
    PMS_AccessMetadataClient.transport = mock;
    row('PMS_Site__c', 'ReadWrite');
    Test.startTest();
    tick('Private', true, false);
    Assert.areEqual(
      'Changing to Public Read/Write',
      reload('PMS_Site__c').Step__c
    );
    String sent = mock.bodies[1];
    Assert.isTrue(
      sent.contains('<met:sharingModel>ReadWrite</met:sharingModel>')
    );
    Assert.isTrue(
      sent.contains('<met:enableHistory>true</met:enableHistory>'),
      'object settings are kept'
    );
    Assert.isTrue(sent.contains('<met:actionOverrides>'), 'overrides are kept');
    Assert.isTrue(sent.contains('Thing &amp; more'), 'text is escaped again');
    Assert.isFalse(sent.contains('Secret__c'), 'fields are not sent');
    tick('ReadWrite', true, false);
    List<PMS_AccessMetadataClient.Result> rs = PMS_AccessMetadataClient.createSharingReasons(
      new List<String>{ 'PMS_Site__c' }
    );
    Test.stopTest();
    Assert.areEqual(PMS_AccessRollout.STEP_DONE, reload('PMS_Site__c').Step__c);
    Assert.isTrue(rs[0].success);
    Assert.areEqual('PMS_Site__c', rs[0].fullName);
  }

  @isTest
  static void refusedChangesFailAfterThreeTries() {
    MetadataMock mock = new MetadataMock();
    mock.succeed = false;
    PMS_AccessMetadataClient.transport = mock;
    row('PMS_Site__c', 'Read');
    Test.startTest();
    tick('ReadWrite', false, false);
    Assert.isTrue(reload('PMS_Site__c').Message__c.startsWith('Retrying'));
    tick('ReadWrite', false, false);
    tick('ReadWrite', false, false);
    Test.stopTest();
    PMS_Access_Rollout__c r = reload('PMS_Site__c');
    Assert.areEqual(PMS_AccessRollout.STEP_FAILED, r.Step__c);
    Assert.isTrue(r.Message__c.contains('in progress'));
  }

  @isTest
  static void connectionErrorsAreExplained() {
    MetadataMock mock = new MetadataMock();
    mock.fault = 'INVALID_SESSION_ID: This session is not valid for use with the API';
    PMS_AccessMetadataClient.transport = mock;
    row('PMS_Site__c', 'Read');
    Test.startTest();
    try {
      PMS_AccessMetadataClient.ping();
      Assert.fail('expected an error');
    } catch (PMS_AccessMetadataClient.MetadataException e) {
      Assert.isTrue(e.getMessage().contains('Allow Formulas in HTTP Body'));
    }
    tick('ReadWrite', false, false);
    Test.stopTest();
    Assert.isTrue(
      reload('PMS_Site__c').Message__c.contains('INVALID_SESSION_ID')
    );
  }

  static User manager() {
    User me = new User(Id = UserInfo.getUserId());
    System.runAs(me) {
      PermissionSet ps = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = 'PMS_Access_Manager'
      ];
      if (
        [
          SELECT COUNT()
          FROM PermissionSetAssignment
          WHERE PermissionSetId = :ps.Id AND AssigneeId = :me.Id
        ] == 0
      ) {
        insert new PermissionSetAssignment(
          PermissionSetId = ps.Id,
          AssigneeId = me.Id
        );
      }
    }
    return me;
  }

  @isTest
  static void consoleStartsAndStopsRollouts() {
    User me = manager();
    MetadataMock mock = new MetadataMock();
    PMS_AccessMetadataClient.transport = mock;
    System.runAs(me) {
      Test.startTest();
      Integer n = PMS_AccessConsoleController.startRollout(
        new List<String>{ 'PMS_Site__c', 'PMS_Booking__c' },
        'apply',
        null
      );
      Assert.areEqual(2, n);
      PMS_AccessConsoleController.Overview o = PMS_AccessConsoleController.getOverview();
      Assert.isTrue(o.rolloutActive);
      Boolean seen = false;
      for (PMS_AccessConsoleController.ObjectRow r : o.objects) {
        if (r.objectApi == 'PMS_Site__c') {
          seen = true;
          Assert.areEqual('Private', r.rolloutTarget);
          Assert.areEqual(PMS_AccessRollout.STEP_WAITING, r.rolloutStep);
        }
      }
      Assert.isTrue(seen);

      // Starting the same change again keeps its progress; a different one is refused while it runs.
      Assert.areEqual(
        1,
        PMS_AccessConsoleController.startRollout(
          new List<String>{ 'PMS_Site__c' },
          'apply',
          null
        )
      );
      try {
        PMS_AccessConsoleController.startRollout(
          new List<String>{ 'PMS_Site__c' },
          'set',
          'ReadWrite'
        );
        Assert.fail('expected a busy error');
      } catch (AuraHandledException e) {
        Assert.isNotNull(e);
      }
      Assert.areEqual(
        1,
        PMS_AccessConsoleController.cancelRollout(
          new List<String>{ 'PMS_Booking__c' }
        )
      );
      Assert.areEqual(1, PMS_AccessConsoleController.cancelRollout(null));
      Test.stopTest();
    }
    Assert.areEqual(
      PMS_AccessRollout.STEP_CANCELLED,
      reload('PMS_Site__c').Step__c
    );
  }

  @isTest
  static void plainPrivateNeedsRulesFirst() {
    User me = manager();
    PMS_AccessMetadataClient.transport = new MetadataMock();
    System.runAs(me) {
      Test.startTest();
      PMS_AccessService.owdOverride.put('PMS_Invoice__c', 'ReadWrite');
      for (
        List<Object> bad : new List<List<Object>>{
          new List<Object>{
            new List<String>{ 'PMS_Invoice__c' },
            'set',
            'Private'
          },
          new List<Object>{ new List<String>(), 'apply', null },
          new List<Object>{ new List<String>{ 'Account' }, 'apply', null },
          new List<Object>{
            new List<String>{ 'PMS_Invoice__c' },
            'set',
            'Nonsense'
          }
        }
      ) {
        try {
          PMS_AccessConsoleController.startRollout(
            (List<String>) bad[0],
            (String) bad[1],
            (String) bad[2]
          );
          Assert.fail('expected an error');
        } catch (AuraHandledException e) {
          Assert.isNotNull(e);
        }
      }
      Assert.areEqual(
        1,
        PMS_AccessConsoleController.startRollout(
          new List<String>{ 'PMS_Invoice__c' },
          'set',
          'Read'
        )
      );
      Test.stopTest();
    }
    Assert.areEqual('Read', reload('PMS_Invoice__c').Target__c);
  }

  @isTest
  static void hintOnlyForConnectionProblems() {
    Assert.isFalse(
      PMS_AccessMetadataClient.connectionHint('Something else')
        .contains('Allow Formulas')
    );
    Assert.isTrue(
      PMS_AccessMetadataClient.connectionHint(null).contains('failed')
    );
  }

  @isTest
  static void queueableStopsWhenNothingIsLeft() {
    Test.startTest();
    System.enqueueJob(new PMS_AccessRollout());
    PMS_AccessRollout.ensureRunning();
    Test.stopTest();
    Assert.isTrue(PMS_AccessRollout.activeRows().isEmpty());
  }
}
