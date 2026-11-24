// Guest 360: one-time full rebuild of the guest stats fields on Contact.
// For source-deployed orgs (scratch / sandbox): sf apex run --file packages/pms/scripts/apex/guest-stats-backfill.apex --target-org <alias>
// Installed packages don't need it: PMS_DailyJob runs a full rebuild until the first successful run, then every Sunday.
// Safe to re-run (idempotent). Progress and errors: Setup > Custom Settings > PMS Guest Stats Run, and Apex Jobs.
Id jobId = Database.executeBatch(new PMS_GuestStatsBatch(true), 100);
System.debug(LoggingLevel.INFO, 'PMS_GUEST_STATS|backfill started|' + jobId);
