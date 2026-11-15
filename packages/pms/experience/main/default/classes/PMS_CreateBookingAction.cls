/** Agent action: "Create Booking". Picks a free space of the type when none is given. */
public with sharing class PMS_CreateBookingAction {
  public class Request {
    @InvocableVariable(
      required=true
      label='Module'
      description='Property, Hotel, Project or Practice'
    )
    public String module;
    @InvocableVariable(required=true label='Site Id')
    public Id siteId;
    @InvocableVariable(label='Space Type Id')
    public Id spaceTypeId;
    @InvocableVariable(label='Space Id')
    public Id spaceId;
    @InvocableVariable(label='Account Id')
    public Id accountId;
    @InvocableVariable(label='Contact Id')
    public Id contactId;
    @InvocableVariable(label='Start Date')
    public Date startDate;
    @InvocableVariable(label='End Date')
    public Date endDate;
    @InvocableVariable(
      label='Start Date/Time'
      description='Use for appointments'
    )
    public Datetime startDatetime;
    @InvocableVariable(label='Service Id')
    public Id serviceId;
    @InvocableVariable(label='Practitioner Id')
    public Id practitionerId;
    @InvocableVariable(label='Rate Plan Id')
    public Id ratePlanId;
    @InvocableVariable(label='Adults')
    public Integer adults;
    @InvocableVariable(label='Children')
    public Integer children;
    @InvocableVariable(label='Special Requests')
    public String specialRequests;
  }

  public class Result {
    @InvocableVariable(label='Success')
    public Boolean success;
    @InvocableVariable(label='Booking Id')
    public Id bookingId;
    @InvocableVariable(label='Booking Number')
    public String bookingNumber;
    @InvocableVariable(label='Message')
    public String message;
  }

  @InvocableMethod(
    label='PMS: Create Booking'
    description='Creates a confirmed reservation, lease, allocation or appointment after availability has been checked.'
    category='Unified PMS'
  )
  public static List<Result> run(List<Request> requests) {
    List<Result> results = new List<Result>();
    for (Request r : requests) {
      Result res = new Result();
      Savepoint sp = Database.setSavepoint();
      try {
        PMS_BookingService.BookingRequest br = new PMS_BookingService.BookingRequest();
        br.module = r.module;
        br.siteId = r.siteId;
        br.spaceTypeId = r.spaceTypeId;
        br.spaceId = r.spaceId;
        br.accountId = r.accountId;
        br.contactId = r.contactId;
        br.startDate = r.startDate;
        br.endDate = r.endDate;
        br.startDatetime = r.startDatetime;
        br.serviceId = r.serviceId;
        br.practitionerId = r.practitionerId;
        br.ratePlanId = r.ratePlanId;
        br.adults = r.adults;
        br.children = r.children;
        br.specialRequests = r.specialRequests;
        br.channel = 'AI Agent';
        PMS_Booking__c b = PMS_BookingService.createBooking(br);
        b = [
          SELECT Id, Name, Total_Amount__c
          FROM PMS_Booking__c
          WHERE Id = :b.Id
        ];
        res.success = true;
        res.bookingId = b.Id;
        res.bookingNumber = b.Name;
        res.message = 'Booked ' + b.Name + ', total ' + b.Total_Amount__c + '.';
      } catch (Exception e) {
        Database.rollback(sp);
        res.success = false;
        res.message = e.getMessage();
      }
      results.add(res);
    }
    return results;
  }
}
