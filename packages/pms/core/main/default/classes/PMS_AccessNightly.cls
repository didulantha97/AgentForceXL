/**
 * Nightly safety net: applies member start / end dates, re-syncs every team group and the Hide
 * permission sets, then recalculates every restricted object (this also catches records whose parent
 * moved to another site during the day).
 *
 * Schedule once:  System.schedule('PMS Access Nightly', '0 30 1 * * ?', new PMS_AccessNightly());
 */
public without sharing class PMS_AccessNightly implements Schedulable {
  public void execute(SchedulableContext ctx) {
    System.enqueueJob(new PMS_AccessGroupSync(null, true));
  }
}
