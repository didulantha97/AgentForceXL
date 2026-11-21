/**
 * Daily: applies approved rent adjustments whose effective date has come ("PMS Rent Adjustments (daily)").
 *   System.schedule('PMS Rent Adjustments (daily)', '0 15 4 * * ?', new PMS_RentAdjustmentJob());
 * Times and Date.today() follow the scheduling user's time zone: for a Colombo user this runs at
 * 23:45 Stockholm, when it is already the next day in Colombo, so a 1 January change is in place
 * shortly before midnight on 31 December Stockholm time, ahead of the January rent run.
 */
public without sharing class PMS_RentAdjustmentJob implements Schedulable {
  public void execute(SchedulableContext ctx) {
    if (PMS_Entitlements.jobsBlocked('PMS_RentAdjustmentJob')) {
      return; // licence suspended: PMS is read-only
    }
    PMS_RentIndexService.applyDue(Date.today());
  }
}
