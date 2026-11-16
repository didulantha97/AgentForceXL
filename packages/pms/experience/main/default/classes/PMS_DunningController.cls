/**
 * Invoice page panel "Dunning" (LWC pmsInvoiceDunning): stage, next step, history and payment plan,
 * with Pause / Resume, Send next step now and Offer payment plan. Checks the user can see the
 * invoice (user mode) before anything runs.
 */
public with sharing class PMS_DunningController {
  public class EventRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String step;
    @AuraEnabled
    public Datetime sentAt;
    @AuraEnabled
    public String sentTo;
    @AuraEnabled
    public Decimal fee;
    @AuraEnabled
    public Decimal interest;
    @AuraEnabled
    public Decimal balance;
    @AuraEnabled
    public String note;
  }

  public class InstalmentRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public Decimal num;
    @AuraEnabled
    public Date dueDate;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public String status;
  }

  public class State {
    @AuraEnabled
    public String invoiceName;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String currencyCode;
    @AuraEnabled
    public Decimal balance;
    @AuraEnabled
    public Integer daysOverdue;
    @AuraEnabled
    public String stage;
    @AuraEnabled
    public Boolean paused = false;
    @AuraEnabled
    public String pauseReason;
    @AuraEnabled
    public String policyName;
    @AuraEnabled
    public Boolean hasPolicy = false;
    @AuraEnabled
    public String nextStep;
    @AuraEnabled
    public Date nextStepDate;
    @AuraEnabled
    public Boolean closed = false;
    @AuraEnabled
    public Boolean canSendNow = false;
    @AuraEnabled
    public Boolean canOfferPlan = false;
    @AuraEnabled
    public Integer defaultInstalments;
    @AuraEnabled
    public String planName;
    @AuraEnabled
    public String planStatus;
    @AuraEnabled
    public List<InstalmentRow> instalments = new List<InstalmentRow>();
    @AuraEnabled
    public List<EventRow> events = new List<EventRow>();
    @AuraEnabled
    public Boolean hasPayLink = false;
  }

  @AuraEnabled
  public static State getState(Id invoiceId) {
    try {
      return state(load(invoiceId));
    } catch (Exception e) {
      throw fail(e);
    }
  }

  @AuraEnabled
  public static State sendNext(Id invoiceId) {
    try {
      PMS_Invoice__c inv = load(invoiceId);
      PMS_Dunning_Policy__c p = requirePolicy(inv);
      if (inv.Dunning_Paused__c == true) {
        throw new PMS_Exception(
          'Dunning is paused on this invoice. Resume it first.'
        );
      }
      String step = PMS_DunningService.nextStep(inv, p, Date.today(), true);
      if (step == null) {
        throw new PMS_Exception(
          'There is no next step for this invoice (not overdue, paid, on a payment plan, or already with collections).'
        );
      }
      PMS_DunningService.Run run = new PMS_DunningService.Run();
      PMS_DunningService.apply(
        inv,
        p,
        step,
        PMS_DunningService.dunningCharges(new Set<Id>{ inv.Id }).get(inv.Id),
        Date.today(),
        run,
        null
      );
      run.commitWork();
      return state(load(invoiceId));
    } catch (Exception e) {
      throw fail(e);
    }
  }

  @AuraEnabled
  public static State offerPlan(Id invoiceId, Integer instalments) {
    try {
      PMS_Invoice__c inv = load(invoiceId);
      PMS_Dunning_Policy__c p = requirePolicy(inv);
      if (
        inv.Balance__c == null ||
        inv.Balance__c <= 0 ||
        PMS_DunningService.CLOSED.contains(inv.Status__c)
      ) {
        throw new PMS_Exception('Nothing is owed on this invoice.');
      }
      if (inv.Due_Date__c == null) {
        throw new PMS_Exception('The invoice has no due date.');
      }
      if (!PMS_DunningService.openPlans(new Set<Id>{ inv.Id }).isEmpty()) {
        throw new PMS_Exception(
          'A payment plan is already open on this invoice.'
        );
      }
      PMS_DunningService.Run run = new PMS_DunningService.Run();
      PMS_DunningService.apply(
        inv,
        p,
        PMS_DunningService.OFFER,
        PMS_DunningService.dunningCharges(new Set<Id>{ inv.Id }).get(inv.Id),
        Date.today(),
        run,
        instalments
      );
      run.commitWork();
      return state(load(invoiceId));
    } catch (Exception e) {
      throw fail(e);
    }
  }

  @AuraEnabled
  public static State pause(Id invoiceId, String reason) {
    try {
      PMS_Invoice__c inv = load(invoiceId);
      update new PMS_Invoice__c(
        Id = inv.Id,
        Dunning_Paused__c = true,
        Dunning_Pause_Reason__c = PMS_DunningService.cut(reason, 255)
      );
      PMS_Dunning_Event__c ev = PMS_DunningService.event(
        inv,
        'Paused',
        String.isBlank(reason) ? 'Paused by ' + UserInfo.getName() : reason
      );
      insert ev;
      return state(load(invoiceId));
    } catch (Exception e) {
      throw fail(e);
    }
  }

  @AuraEnabled
  public static State resume(Id invoiceId) {
    try {
      PMS_Invoice__c inv = load(invoiceId);
      update new PMS_Invoice__c(
        Id = inv.Id,
        Dunning_Paused__c = false,
        Dunning_Pause_Reason__c = null
      );
      PMS_Dunning_Event__c ev = PMS_DunningService.event(
        inv,
        'Resumed',
        'Resumed by ' + UserInfo.getName()
      );
      insert ev;
      return state(load(invoiceId));
    } catch (Exception e) {
      throw fail(e);
    }
  }

  // ---------------------------------------------------------------- helpers

  private static PMS_Invoice__c load(Id invoiceId) {
    List<PMS_Invoice__c> visible = [
      SELECT Id
      FROM PMS_Invoice__c
      WHERE Id = :invoiceId
      WITH USER_MODE
      LIMIT 1
    ];
    if (visible.isEmpty()) {
      throw new PMS_Exception(
        'Invoice not found, or you do not have access to it.'
      );
    }
    return PMS_DunningService.load(new Set<Id>{ invoiceId })[0];
  }

  private static PMS_Dunning_Policy__c requirePolicy(PMS_Invoice__c inv) {
    PMS_Dunning_Policy__c p = PMS_DunningService.policiesFor(
        new List<PMS_Invoice__c>{ inv }
      )
      .get(inv.Id);
    if (p == null) {
      throw new PMS_Exception(
        'No active dunning policy applies. Create a default Dunning Policy, or set one on the site.'
      );
    }
    return p;
  }

  @TestVisible
  private static State state(PMS_Invoice__c inv) {
    PMS_Dunning_Policy__c p = PMS_DunningService.policiesFor(
        new List<PMS_Invoice__c>{ inv }
      )
      .get(inv.Id);
    State s = new State();
    s.invoiceName = inv.Name;
    s.status = inv.Status__c;
    s.currencyCode = PMS_DunningService.currencyOf(inv);
    s.balance = inv.Balance__c;
    s.daysOverdue = inv.Due_Date__c == null ||
      inv.Due_Date__c >= Date.today()
      ? 0
      : inv.Due_Date__c.daysBetween(Date.today());
    s.stage = inv.Dunning_Stage__c;
    s.paused = inv.Dunning_Paused__c == true;
    s.pauseReason = inv.Dunning_Pause_Reason__c;
    s.closed =
      PMS_DunningService.CLOSED.contains(inv.Status__c) ||
      PMS_DunningService.nz(inv.Balance__c) <= 0;
    s.hasPayLink = String.isNotBlank(inv.Pay_Key__c);
    Map<Id, PMS_Payment_Plan__c> plans = PMS_DunningService.openPlans(
      new Set<Id>{ inv.Id }
    );
    PMS_Payment_Plan__c plan = plans.get(inv.Id);
    if (plan != null) {
      s.planName = plan.Name;
      s.planStatus = plan.Status__c;
      for (PMS_Payment_Plan_Instalment__c i : plan.Instalments__r) {
        InstalmentRow r = new InstalmentRow();
        r.id = i.Id;
        r.num = i.Number__c;
        r.dueDate = i.Due_Date__c;
        r.amount = i.Amount__c;
        r.status = i.Status__c;
        s.instalments.add(r);
      }
    }
    if (p != null) {
      s.hasPolicy = true;
      s.policyName = p.Name;
      s.defaultInstalments = p.Plan_Instalments__c == null
        ? 3
        : p.Plan_Instalments__c.intValue();
      if (!s.paused && !s.closed && plan == null) {
        String preview = PMS_DunningService.nextStep(
          inv,
          p,
          Date.today(),
          true
        );
        s.nextStep = preview;
        s.nextStepDate = preview == null
          ? null
          : PMS_DunningService.nextStepDate(inv, p);
        s.canSendNow = preview != null;
      }
      s.canOfferPlan =
        !s.closed &&
        plan == null &&
        s.daysOverdue > 0 &&
        inv.Dunning_Stage__c != PMS_DunningService.COLL;
    }
    for (PMS_Dunning_Event__c e : [
      SELECT
        Id,
        Stage__c,
        Sent_At__c,
        Sent_To__c,
        Fee_Posted__c,
        Interest_Posted__c,
        Balance__c,
        Note__c
      FROM PMS_Dunning_Event__c
      WHERE Invoice__c = :inv.Id
      ORDER BY Sent_At__c DESC, CreatedDate DESC
      LIMIT 20
    ]) {
      EventRow r = new EventRow();
      r.id = e.Id;
      r.step = e.Stage__c;
      r.sentAt = e.Sent_At__c;
      r.sentTo = e.Sent_To__c;
      r.fee = e.Fee_Posted__c;
      r.interest = e.Interest_Posted__c;
      r.balance = e.Balance__c;
      r.note = e.Note__c;
      s.events.add(r);
    }
    return s;
  }

  private static AuraHandledException fail(Exception e) {
    AuraHandledException ex = new AuraHandledException(e.getMessage());
    ex.setMessage(e.getMessage());
    return ex;
  }
}
