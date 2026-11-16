/**
 * Runs guarantee work straight after a booking change (queued by PMS_GuaranteeTriggerHandler):
 * emailing card or deposit links for new bookings, or applying a cancellation / no-show policy.
 * Handles 25 bookings per run and chains the rest.
 */
public without sharing class PMS_GuaranteeActionJob implements Queueable, Database.AllowsCallouts {
  public static final String SEND_LINKS = 'links';
  public static final String APPLY_POLICY = 'policy';
  private static final Integer MAX_PER_RUN = 25;

  private String action;
  private Set<Id> bookingIds;

  public PMS_GuaranteeActionJob(String action, Set<Id> bookingIds) {
    this.action = action;
    this.bookingIds = bookingIds;
  }

  public void execute(QueueableContext ctx) {
    Set<Id> now = new Set<Id>();
    Set<Id> later = new Set<Id>();
    for (Id i : bookingIds) {
      if (now.size() < MAX_PER_RUN) {
        now.add(i);
      } else {
        later.add(i);
      }
    }
    if (action == SEND_LINKS) {
      PMS_GuaranteeJob.sendLinks(now);
    } else if (action == APPLY_POLICY) {
      PMS_GuaranteeJob.applyPolicies(now);
    }
    if (!later.isEmpty() && !Test.isRunningTest()) {
      System.enqueueJob(new PMS_GuaranteeActionJob(action, later));
    }
  }
}
