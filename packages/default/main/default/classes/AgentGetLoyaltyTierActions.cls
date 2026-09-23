public with sharing class AgentGetLoyaltyTierActions {
  public class Request {
    @InvocableVariable(
      label='Verified Customer Id'
      description='The Contact Id for the verified customer whose loyalty tier should be returned.'
      required=false
    )
    public Id verifiedCustomerId;

    @InvocableVariable(
      label='Customer Email'
      description='The customer email address (Contact.Email). Provide when you do not have the Contact Id.'
      required=false
    )
    public String customerEmail;
  }

  public class Response {
    @InvocableVariable(
      label='Success'
      description='True when the action executed successfully.'
    )
    public Boolean success;

    @InvocableVariable(
      label='Message'
      description='User-readable status message.'
    )
    public String message;

    @InvocableVariable(
      label='Loyalty Tier'
      description='The customer loyalty tier value (e.g. Explorer, Insider, Pronto Plus, Pronto One, Pronto Elite).'
    )
    public String loyaltyTier;

    @InvocableVariable(
      label='Customer Name'
      description='The customer full name for display.'
    )
    public String customerName;

    @InvocableVariable(
      label='Verified Customer Id'
      description='The Contact Id, useful for subsequent actions.'
    )
    public Id verifiedCustomerId;
  }

  @InvocableMethod(
    label='Get Loyalty Tier'
    description='Returns the loyalty tier for a customer Contact. Accepts either a Contact Id or email address.'
  )
  public static List<Response> invoke(List<Request> requests) {
    Response out = new Response();
    out.success = false;

    Request req = (requests != null && !requests.isEmpty())
      ? requests[0]
      : null;

    try {
      if (req == null) {
        out.message = 'A request is required.';
        return new List<Response>{ out };
      }

      Boolean hasId = (req.verifiedCustomerId != null);
      Boolean hasEmail = String.isNotBlank(req.customerEmail);

      if (!hasId && !hasEmail) {
        out.message = 'Either verifiedCustomerId or customerEmail is required.';
        return new List<Response>{ out };
      }

      Id custId = req.verifiedCustomerId;
      String email = hasEmail ? req.customerEmail.trim() : null;

      String whereClause;
      if (hasId && hasEmail)
        whereClause = 'Id = :custId AND Email = :email';
      else if (hasId)
        whereClause = 'Id = :custId';
      else
        whereClause = 'Email = :email';

      String soql =
        'SELECT Id, Name, Loyalty_Tier__c FROM Contact WHERE ' +
        whereClause +
        ' LIMIT 1';
      List<Contact> contacts = Database.query(soql);

      if (contacts.isEmpty()) {
        out.success = true;
        out.message = 'No customer found.';
        return new List<Response>{ out };
      }

      Contact c = contacts[0];
      out.verifiedCustomerId = c.Id;
      out.customerName = c.Name;
      out.loyaltyTier = c.Loyalty_Tier__c;
      out.success = true;
      out.message =
        c.Name +
        ' is a ' +
        (String.isNotBlank(c.Loyalty_Tier__c)
          ? c.Loyalty_Tier__c
          : 'Explorer') +
        ' member.';
    } catch (Exception e) {
      out.success = false;
      out.message = e.getMessage();
    }

    return new List<Response>{ out };
  }
}
