/**
 * The Experience half of the Core to Experience bypass (PMS_TriggerBypass.policyFees):
 * while the flag is set, booking cancellations get no automatic policy fee and no guarantee job.
 * Core sets and restores the flag around OTA cancellations; that half is tested in Core
 * (PMS_ChannexTest), because Core's PMS_ChannexBookings is not visible to this package.
 */
@isTest
private class PMS_PolicyFeeBypassTest {
  private static final String PROPERTY = '716305c4-561a-4561-a187-7f5b8aeb5920';
  private static final String ROOM_TYPE = 'bab451e7-9ab1-4cc4-aa16-107bf7bbabb2';
  private static final String RATE_PLAN = '445835fb-7956-42ac-9efc-3e6f331f0808';

  @TestSetup
  static void setup() {
    PMS_ExperienceTestFactory.hotel(2);
  }

  private static void activePolicy() {
    insert new PMS_Payment_Policy__c(
      Name = 'Test policy',
      Active__c = true,
      Guarantee_Method__c = 'Card on File',
      Deposit_Basis__c = 'Fixed Amount',
      Deposit_Value__c = 800,
      Deposit_Due_Days__c = 0,
      Preauth_Hours_Before__c = 24,
      Free_Cancellation_Hours__c = 24,
      Late_Cancel_Basis__c = 'Fixed Amount',
      Late_Cancel_Value__c = 500,
      No_Show_Basis__c = 'Fixed Amount',
      No_Show_Value__c = 600,
      Auto_Charge_Fees__c = true,
      Auto_Send_Card_Link__c = false,
      Release_Hold_On_Checkout__c = true,
      Guest_Terms__c = 'Free cancellation up to 24 hours before arrival.'
    );
  }

  @isTest
  static void bypassedCancelGetsNoPolicyFeeAndNoJob() {
    activePolicy();
    PMS_Booking__c b = directBooking();

    Test.startTest();
    Integer queuedBefore = Limits.getQueueableJobs();
    PMS_TriggerBypass.policyFees = true;
    try {
      update new PMS_Booking__c(Id = b.Id, Status__c = 'Cancelled');
    } finally {
      PMS_TriggerBypass.policyFees = false;
    }
    Assert.areEqual(
      queuedBefore,
      Limits.getQueueableJobs(),
      'no guarantee job queued'
    );
    Test.stopTest();

    PMS_Booking__c after = [
      SELECT Status__c, Policy_Pending__c, Policy_Event_At__c
      FROM PMS_Booking__c
      WHERE Id = :b.Id
    ];
    Assert.areEqual('Cancelled', after.Status__c);
    Assert.areNotEqual(
      true,
      after.Policy_Pending__c,
      'no PMS fee while bypassed'
    );
    Assert.isNull(after.Policy_Event_At__c);
  }

  @isTest
  static void bypassedNoShowGetsNoPolicyFee() {
    activePolicy();
    PMS_Booking__c b = directBooking();
    PMS_TriggerBypass.policyFees = true;
    try {
      update new PMS_Booking__c(Id = b.Id, Status__c = 'No Show');
    } finally {
      PMS_TriggerBypass.policyFees = false;
    }
    Assert.areNotEqual(
      true,
      [SELECT Policy_Pending__c FROM PMS_Booking__c WHERE Id = :b.Id]
      .Policy_Pending__c
    );
  }

  @isTest
  static void unbypassedCancelQueuesGuaranteeJob() {
    // Control: same update with the flag off marks the fee and queues the job.
    activePolicy();
    PMS_Booking__c b = directBooking();
    Test.startTest();
    Integer queuedBefore = Limits.getQueueableJobs();
    update new PMS_Booking__c(Id = b.Id, Status__c = 'Cancelled');
    Assert.areEqual(
      queuedBefore + 1,
      Limits.getQueueableJobs(),
      'control: job queued without the bypass'
    );
    // The trigger marks the fee pending; read it before stopTest runs the queued job, which
    // applies the policy and clears the flag.
    Assert.isTrue(
      [SELECT Policy_Pending__c FROM PMS_Booking__c WHERE Id = :b.Id]
      .Policy_Pending__c,
      'trigger marks the fee as pending'
    );
    Test.stopTest();
  }

  @isTest
  static void normalCancelStillGetsPolicyPending() {
    // Control: without the bypass the same Confirmed to Cancelled update marks a fee as pending.
    PMS_Booking__c b = directBooking();
    b.Status__c = 'Cancelled';
    update b;
    PMS_Booking__c after = [
      SELECT Policy_Pending__c, Policy_Event_At__c
      FROM PMS_Booking__c
      WHERE Id = :b.Id
    ];
    Assert.isTrue(after.Policy_Pending__c, 'trigger marks the fee as pending');
    Assert.isNotNull(after.Policy_Event_At__c);
  }

  private static PMS_Booking__c directBooking() {
    PMS_Site__c site = [SELECT Id FROM PMS_Site__c LIMIT 1];
    PMS_Space__c room = [SELECT Id FROM PMS_Space__c LIMIT 1];
    Contact guest = [SELECT Id, AccountId FROM Contact LIMIT 1];
    PMS_Booking__c b = new PMS_Booking__c(
      RecordTypeId = PMS_ExperienceTestFactory.rt(
        PMS_Booking__c.SObjectType,
        'Reservation'
      ),
      Site__c = site.Id,
      Space__c = room.Id,
      Account__c = guest.AccountId,
      Primary_Contact__c = guest.Id,
      Status__c = 'Confirmed',
      Start__c = Datetime.now().addDays(10),
      End__c = Datetime.now().addDays(12)
    );
    insert b;
    return b;
  }

  // ------------------------------------------------------------ handler

  private static Id fakeBookingId() {
    return PMS_Booking__c.SObjectType.getDescribe().getKeyPrefix() +
      '000000000001';
  }

  private static PMS_Booking__c confirmed(Id id) {
    return new PMS_Booking__c(Id = id, Status__c = 'Confirmed');
  }

  @isTest
  static void beforeUpdateDoesNothingWhileBypassed() {
    Id id = fakeBookingId();
    PMS_Booking__c cancelled = new PMS_Booking__c(
      Id = id,
      Status__c = 'Cancelled'
    );
    Map<Id, PMS_Booking__c> oldMap = new Map<Id, PMS_Booking__c>{
      id => confirmed(id)
    };

    PMS_TriggerBypass.policyFees = true;
    PMS_GuaranteeTriggerHandler.beforeUpdate(
      new List<PMS_Booking__c>{ cancelled },
      oldMap
    );
    Assert.areNotEqual(true, cancelled.Policy_Pending__c);
    Assert.isNull(cancelled.Policy_Event_At__c);

    PMS_TriggerBypass.policyFees = false;
    PMS_GuaranteeTriggerHandler.beforeUpdate(
      new List<PMS_Booking__c>{ cancelled },
      oldMap
    );
    Assert.isTrue(
      cancelled.Policy_Pending__c,
      'control: handler marks the fee without the bypass'
    );
    Assert.isNotNull(cancelled.Policy_Event_At__c);
  }

  @isTest
  static void beforeUpdateIgnoresTentativeAndAlreadyChargedBookings() {
    Id id = fakeBookingId();
    PMS_Booking__c tentative = new PMS_Booking__c(
      Id = id,
      Status__c = 'Cancelled'
    );
    PMS_GuaranteeTriggerHandler.beforeUpdate(
      new List<PMS_Booking__c>{ tentative },
      new Map<Id, PMS_Booking__c>{
        id => new PMS_Booking__c(Id = id, Status__c = 'Tentative')
      }
    );
    Assert.areNotEqual(
      true,
      tentative.Policy_Pending__c,
      'tentative holds get no automatic fee'
    );

    PMS_Booking__c charged = new PMS_Booking__c(
      Id = id,
      Status__c = 'No Show',
      Policy_Fee_Charged__c = true
    );
    PMS_GuaranteeTriggerHandler.beforeUpdate(
      new List<PMS_Booking__c>{ charged },
      new Map<Id, PMS_Booking__c>{ id => confirmed(id) }
    );
    Assert.areNotEqual(
      true,
      charged.Policy_Pending__c,
      'a fee is never charged twice'
    );
  }

  @isTest
  static void afterUpdateEnqueuesNothingWhileBypassed() {
    activePolicy();
    Id id = fakeBookingId();
    PMS_Booking__c pending = new PMS_Booking__c(
      Id = id,
      Policy_Pending__c = true
    );
    Map<Id, PMS_Booking__c> oldMap = new Map<Id, PMS_Booking__c>{
      id => new PMS_Booking__c(Id = id, Policy_Pending__c = false)
    };
    Integer before = Limits.getQueueableJobs();

    PMS_TriggerBypass.policyFees = true;
    PMS_GuaranteeTriggerHandler.afterUpdate(
      new List<PMS_Booking__c>{ pending },
      oldMap
    );
    Assert.areEqual(before, Limits.getQueueableJobs(), 'bypassed: no job');

    PMS_TriggerBypass.policyFees = false;
    PMS_GuaranteeTriggerHandler.afterUpdate(
      new List<PMS_Booking__c>{ pending },
      oldMap
    );
    Assert.areEqual(
      before + 1,
      Limits.getQueueableJobs(),
      'control: job queued without the bypass'
    );
    // Deliberately no Test.stopTest(): the control job is never run.
  }

  @isTest
  static void afterInsertEnqueuesNothingWhileBypassed() {
    activePolicy();
    Contact guest = [SELECT Id FROM Contact LIMIT 1];
    PMS_Booking__c b = new PMS_Booking__c(
      Id = fakeBookingId(),
      Status__c = 'Confirmed',
      Primary_Contact__c = guest.Id
    );
    Integer before = Limits.getQueueableJobs();

    PMS_TriggerBypass.policyFees = true;
    PMS_GuaranteeTriggerHandler.afterInsert(new List<PMS_Booking__c>{ b });
    Assert.areEqual(
      before,
      Limits.getQueueableJobs(),
      'bypassed: no card link job'
    );

    PMS_TriggerBypass.policyFees = false;
    PMS_GuaranteeTriggerHandler.afterInsert(new List<PMS_Booking__c>{ b });
    Assert.areEqual(
      before + 1,
      Limits.getQueueableJobs(),
      'control: link job queued without the bypass'
    );
  }
}
