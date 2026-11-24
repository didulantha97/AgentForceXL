/**
 * Flow entry point for PMS_GuestMatchService: finds the guest, or creates an Account and Contact.
 * Used by the PMS Agent: Find or Create Guest flow. Runs with the calling user's record access and
 * field-level security. Never merges: a possible duplicate is only flagged on the new contact.
 */
public with sharing class PMS_GuestMatchInvocable {
  public class Request {
    @InvocableVariable(label='First name')
    public String firstName;
    @InvocableVariable(label='Last name' required=true)
    public String lastName;
    @InvocableVariable(label='Email')
    public String email;
    @InvocableVariable(label='Phone')
    public String phone;
    @InvocableVariable(label='Party role (Guest, Tenant or Practice Client)')
    public String partyRole;
  }

  public class Response {
    @InvocableVariable(label='Contact Id')
    public Id contactId;
    @InvocableVariable(label='Account Id')
    public Id accountId;
    @InvocableVariable(label='Created')
    public Boolean isNew;
  }

  @InvocableMethod(
    label='PMS Find or Create Guest'
    description='Matches a guest by email (never relay addresses), else creates an account and contact and flags possible duplicates.'
  )
  public static List<Response> findOrCreate(List<Request> requests) {
    List<Response> out = new List<Response>();
    if (requests == null || requests.isEmpty()) {
      return out;
    }
    List<PMS_GuestMatchService.GuestInput> inputs = new List<PMS_GuestMatchService.GuestInput>();
    for (Request q : requests) {
      PMS_GuestMatchService.GuestInput g = new PMS_GuestMatchService.GuestInput();
      g.firstName = q.firstName;
      g.lastName = q.lastName;
      g.email = q.email;
      g.phone = q.phone;
      inputs.add(g);
    }
    List<PMS_GuestMatchService.Result> res = PMS_GuestMatchService.match(
      inputs
    );

    List<Integer> toCreate = new List<Integer>();
    List<Account> accounts = new List<Account>();
    for (Integer i = 0; i < requests.size(); i++) {
      out.add(new Response());
      if (res[i].contactId == null) {
        Request q = requests[i];
        String name = ((q.firstName == null ? '' : q.firstName) +
          ' ' +
          q.lastName)
          .trim();
        toCreate.add(i);
        accounts.add(
          new Account(
            Name = name.left(255),
            PMS_Party_Role__c = String.isBlank(q.partyRole)
              ? 'Guest'
              : q.partyRole,
            Phone = q.phone
          )
        );
      }
    }
    if (!accounts.isEmpty()) {
      // Duplicate rules must not block the agent flow: possible duplicates are flagged by PMS_GuestMatchService.
      Database.DMLOptions dml = new Database.DMLOptions();
      dml.OptAllOrNone = true; // DMLOptions default to partial success: keep failures as exceptions
      dml.duplicateRuleHeader.allowSave = true;
      Database.insert(accounts, dml, AccessLevel.USER_MODE);
      List<Contact> contacts = new List<Contact>();
      for (Integer n = 0; n < toCreate.size(); n++) {
        Integer i = toCreate[n];
        inputs[i].accountId = accounts[n].Id;
        Contact full = PMS_GuestMatchService.newContact(inputs[i], res[i]);
        // Match metadata is system-maintained (read-only FLS), so it is written separately below. Copy only the
        // user-editable fields: even a null assignment counts as "set" and fails a USER_MODE insert.
        contacts.add(
          new Contact(
            AccountId = full.AccountId,
            FirstName = full.FirstName,
            LastName = full.LastName,
            Email = full.Email,
            Phone = full.Phone
          )
        );
      }
      Database.insert(contacts, dml, AccessLevel.USER_MODE);
      List<Contact> meta = new List<Contact>();
      for (Integer n = 0; n < toCreate.size(); n++) {
        PMS_GuestMatchService.Result r = res[toCreate[n]];
        if (r.aliasEmail != null || r.possibleDuplicateOf != null) {
          meta.add(
            new Contact(
              Id = contacts[n].Id,
              PMS_OTA_Alias_Email__c = r.aliasEmail,
              PMS_Possible_Duplicate_Of__c = r.possibleDuplicateOf,
              PMS_Duplicate_Reason__c = r.reason
            )
          );
        }
      }
      if (!meta.isEmpty()) {
        // System-maintained match metadata: staff cannot edit these fields, so write in system mode.
        Database.update(meta, dml, AccessLevel.SYSTEM_MODE);
      }
      for (Integer n = 0; n < toCreate.size(); n++) {
        Response r = out[toCreate[n]];
        r.contactId = contacts[n].Id;
        r.accountId = accounts[n].Id;
        r.isNew = true;
      }
    }
    // Matched guests: fetch account ids in one query.
    Set<Id> matched = new Set<Id>();
    for (PMS_GuestMatchService.Result r : res) {
      if (r.contactId != null) {
        matched.add(r.contactId);
      }
    }
    if (!matched.isEmpty()) {
      Map<Id, Contact> found = new Map<Id, Contact>(
        [SELECT Id, AccountId FROM Contact WHERE Id IN :matched WITH USER_MODE]
      );
      for (Integer i = 0; i < res.size(); i++) {
        if (res[i].contactId != null) {
          out[i].contactId = res[i].contactId;
          out[i].accountId = found.containsKey(res[i].contactId)
            ? found.get(res[i].contactId).AccountId
            : null;
          out[i].isNew = false;
        }
      }
    }
    return out;
  }
}
