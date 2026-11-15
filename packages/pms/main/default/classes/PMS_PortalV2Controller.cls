/**
 * Customer Portal v2 (LWC pmsCustomerPortalV2): documents and e-signature, online check-in,
 * project status and approvals. Runs without sharing; every query is pinned to the user's account.
 *
 * E-signature
 *   Staff attach a PDF to a Document Request and set it to Sent. The customer opens it here (the bytes are
 *   served through this class, so no file sharing is needed), types their name, draws a signature and
 *   confirms. signDocument() records the evidence on the request: signed name, the portal user's email,
 *   server time, IP address, browser, and the SHA-256 of the exact file signed; the drawn signature is
 *   kept as a PNG. The page then stamps a signed copy of the PDF (signature page + footer on every page)
 *   with pdf-lib and attachSignedPdf() files it on the request. If stamping fails, the evidence stands.
 */
public without sharing class PMS_PortalV2Controller {
  public static final Integer MAX_DOC_BYTES = 1800000; // Apex heap (6 MB): a file is held as bytes and as base64
  public static final Integer MAX_SIGNED_BYTES = 2000000;
  public static final Set<String> VISIBLE_DOCS = new Set<String>{
    'Sent',
    'Viewed',
    'Signed',
    'Declined'
  };
  public static final Set<String> VISIBLE_APPROVALS = new Set<String>{
    'Pending',
    'Approved',
    'Rejected'
  };

  @TestVisible
  private static Id testAccountId;
  @TestVisible
  private static Id testContactId;

  // ------------------------------------------------------------------ DTOs

  public class Home {
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public String firstName;
    @AuraEnabled
    public List<DocRow> documents = new List<DocRow>();
    @AuraEnabled
    public List<PMS_CheckInService.Eligible> checkIns = new List<PMS_CheckInService.Eligible>();
    @AuraEnabled
    public List<ProjectRow> projects = new List<ProjectRow>();
    @AuraEnabled
    public Integer actionCount = 0;
  }

  public class DocRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Boolean requiresSignature;
    @AuraEnabled
    public Date dueDate;
    @AuraEnabled
    public Datetime signedAt;
    @AuraEnabled
    public String signerName;
    @AuraEnabled
    public String relatedTo;
    @AuraEnabled
    public Boolean canSign = false;
    @AuraEnabled
    public Boolean hasFile = false;
    @AuraEnabled
    public Boolean isPdf = false;
    @AuraEnabled
    public Boolean hasSignedCopy = false;
    @AuraEnabled
    public Boolean needsSignedCopy = false;
  }

  public class ProjectRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String health;
    @AuraEnabled
    public Decimal percentComplete;
    @AuraEnabled
    public Date startDate;
    @AuraEnabled
    public Date endDate;
    @AuraEnabled
    public String siteName;
    @AuraEnabled
    public List<MilestoneRow> milestones = new List<MilestoneRow>();
    @AuraEnabled
    public List<ApprovalRow> approvals = new List<ApprovalRow>();
  }

  public class MilestoneRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Date dueDate;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Boolean canAccept = false;
    @AuraEnabled
    public Datetime acceptedAt;
    @AuraEnabled
    public String comment;
  }

  public class ApprovalRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String type;
    @AuraEnabled
    public String details;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public Decimal scheduleDays;
    @AuraEnabled
    public Date dueDate;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Boolean canDecide = false;
    @AuraEnabled
    public Datetime decidedAt;
    @AuraEnabled
    public String comment;
  }

  public class FileData {
    @AuraEnabled
    public String fileName;
    @AuraEnabled
    public String extension;
    @AuraEnabled
    public String base64;
    @AuraEnabled
    public Integer size;
  }

  public class SignResult {
    @AuraEnabled
    public String requestName;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String signerName;
    @AuraEnabled
    public String signerEmail;
    @AuraEnabled
    public String signedAtLabel;
    @AuraEnabled
    public String ip;
    @AuraEnabled
    public String documentHash;
    @AuraEnabled
    public String companyName;
  }

  // ------------------------------------------------------------------ home

  @AuraEnabled
  public static Home getHome() {
    try {
      Ctx c = ctx();
      Home h = new Home();
      h.accountName = c.accountName;
      h.firstName = UserInfo.getFirstName();
      h.documents = documents(c.accountId);
      h.checkIns = PMS_CheckInService.forAccount(c.accountId);
      h.projects = projects(c.accountId);
      for (DocRow d : h.documents) {
        h.actionCount += d.canSign ? 1 : 0;
      }
      for (PMS_CheckInService.Eligible e : h.checkIns) {
        h.actionCount += e.done ? 0 : 1;
      }
      for (ProjectRow p : h.projects) {
        for (MilestoneRow m : p.milestones) {
          h.actionCount += m.canAccept ? 1 : 0;
        }
        for (ApprovalRow a : p.approvals) {
          h.actionCount += a.canDecide ? 1 : 0;
        }
      }
      return h;
    } catch (Exception e) {
      throw handled(e);
    }
  }

  // ------------------------------------------------------------------ documents

  private static List<DocRow> documents(Id accountId) {
    List<PMS_Document_Request__c> reqs = [
      SELECT
        Id,
        Name,
        Title__c,
        Message__c,
        Status__c,
        Requires_Signature__c,
        Due_Date__c,
        Signed_At__c,
        Signer_Name__c,
        Signed_Version_Id__c,
        Booking__r.Name,
        Project__r.Name
      FROM PMS_Document_Request__c
      WHERE Account__c = :accountId AND Status__c IN :VISIBLE_DOCS
      ORDER BY CreatedDate DESC
      LIMIT 50
    ];
    Map<Id, ContentVersion> originals = originals(
      new Map<Id, PMS_Document_Request__c>(reqs).keySet()
    );
    List<DocRow> rows = new List<DocRow>();
    for (PMS_Document_Request__c r : reqs) {
      DocRow d = new DocRow();
      d.id = r.Id;
      d.name = r.Name;
      d.title = r.Title__c;
      d.message = r.Message__c;
      d.status = r.Status__c;
      d.requiresSignature = r.Requires_Signature__c;
      d.dueDate = r.Due_Date__c;
      d.signedAt = r.Signed_At__c;
      d.signerName = r.Signer_Name__c;
      d.relatedTo = r.Booking__r != null
        ? r.Booking__r.Name
        : (r.Project__r != null ? r.Project__r.Name : null);
      ContentVersion v = originals.get(r.Id);
      d.hasFile = v != null;
      d.isPdf = v != null && v.FileExtension == 'pdf';
      d.canSign =
        d.hasFile &&
        r.Requires_Signature__c &&
        (r.Status__c == 'Sent' ||
        r.Status__c == 'Viewed');
      d.hasSignedCopy = String.isNotBlank(r.Signed_Version_Id__c);
      d.needsSignedCopy =
        r.Status__c == 'Signed' &&
        !d.hasSignedCopy &&
        d.isPdf;
      rows.add(d);
    }
    return rows;
  }

  /** The document to sign: the newest file on the request that isn't a signature or signed copy. */
  private static Map<Id, ContentVersion> originals(Set<Id> requestIds) {
    Map<Id, ContentVersion> result = new Map<Id, ContentVersion>();
    if (requestIds.isEmpty()) {
      return result;
    }
    Map<Id, Id> docToReq = new Map<Id, Id>();
    for (ContentDocumentLink l : [
      SELECT ContentDocumentId, LinkedEntityId
      FROM ContentDocumentLink
      WHERE LinkedEntityId IN :requestIds
    ]) {
      docToReq.put(l.ContentDocumentId, l.LinkedEntityId);
    }
    if (docToReq.isEmpty()) {
      return result;
    }
    for (ContentVersion v : [
      SELECT
        Id,
        Title,
        FileExtension,
        ContentSize,
        Description,
        ContentDocumentId,
        CreatedDate
      FROM ContentVersion
      WHERE ContentDocumentId IN :docToReq.keySet() AND IsLatest = TRUE
      ORDER BY CreatedDate DESC
    ]) {
      if (v.Description != null && v.Description.startsWith('PMS:Sign')) {
        continue; // PMS:Signature (drawn) and PMS:Signed (stamped copy)
      }
      Id reqId = docToReq.get(v.ContentDocumentId);
      if (!result.containsKey(reqId)) {
        result.put(reqId, v);
      }
    }
    return result;
  }

  private static PMS_Document_Request__c myRequest(Id requestId, Id accountId) {
    List<PMS_Document_Request__c> rs = [
      SELECT
        Id,
        Name,
        Title__c,
        Status__c,
        Requires_Signature__c,
        Signed_Version_Id__c,
        OwnerId,
        Account__r.Name,
        Booking__c,
        Project__c
      FROM PMS_Document_Request__c
      WHERE
        Id = :requestId
        AND Account__c = :accountId
        AND Status__c IN :VISIBLE_DOCS
      LIMIT 1
    ];
    if (rs.isEmpty()) {
      throw new PMS_Exception('Document not found.');
    }
    return rs[0];
  }

  @AuraEnabled
  public static FileData getDocument(Id requestId) {
    try {
      Ctx c = ctx();
      PMS_Document_Request__c r = myRequest(requestId, c.accountId);
      ContentVersion meta = originals(new Set<Id>{ r.Id }).get(r.Id);
      if (meta == null) {
        throw new PMS_Exception(
          'The document file is missing. Please contact us.'
        );
      }
      FileData f = fileData(meta.Id, MAX_DOC_BYTES);
      if (r.Status__c == 'Sent') {
        update new PMS_Document_Request__c(
          Id = r.Id,
          Status__c = 'Viewed',
          Viewed_At__c = Datetime.now()
        );
      }
      return f;
    } catch (Exception e) {
      throw handled(e);
    }
  }

  @AuraEnabled
  public static FileData getSignedDocument(Id requestId) {
    try {
      Ctx c = ctx();
      PMS_Document_Request__c r = myRequest(requestId, c.accountId);
      if (String.isBlank(r.Signed_Version_Id__c)) {
        throw new PMS_Exception('The signed copy is not ready yet.');
      }
      return fileData(r.Signed_Version_Id__c, MAX_SIGNED_BYTES);
    } catch (Exception e) {
      throw handled(e);
    }
  }

  @AuraEnabled
  public static SignResult signDocument(
    Id requestId,
    String signerName,
    String signaturePng,
    String userAgent,
    Boolean consent
  ) {
    try {
      Ctx c = ctx();
      PMS_Document_Request__c r = myRequest(requestId, c.accountId);
      if (
        !r.Requires_Signature__c ||
        (r.Status__c != 'Sent' &&
        r.Status__c != 'Viewed')
      ) {
        throw new PMS_Exception('This document can no longer be signed.');
      }
      String name = signerName == null ? '' : signerName.normalizeSpace();
      if (name.length() < 3) {
        throw new PMS_Exception('Type your full name.');
      }
      if (consent != true) {
        throw new PMS_Exception(
          'Please confirm that this is your electronic signature.'
        );
      }
      if (String.isBlank(signaturePng)) {
        throw new PMS_Exception('Draw your signature in the box.');
      }
      ContentVersion meta = originals(new Set<Id>{ r.Id }).get(r.Id);
      if (meta == null) {
        throw new PMS_Exception(
          'The document file is missing. Please contact us.'
        );
      }
      Blob original = [
        SELECT VersionData
        FROM ContentVersion
        WHERE Id = :meta.Id
      ]
      .VersionData;
      String hash = EncodingUtil.convertToHex(
        Crypto.generateDigest('SHA-256', original)
      );
      original = null;
      Blob png = decode(signaturePng);
      if (png.size() > 400000) {
        throw new PMS_Exception(
          'The signature image is too large. Please clear it and sign again.'
        );
      }
      Datetime now = Datetime.now();
      String ip = sourceIp();
      String email = UserInfo.getUserEmail();
      update new PMS_Document_Request__c(
        Id = r.Id,
        Status__c = 'Signed',
        Signed_At__c = now,
        Signer_Name__c = name.left(120),
        Signer_Email__c = email == null ? null : email.left(120),
        Signer_IP__c = ip == null ? null : ip.left(60),
        Signer_User_Agent__c = userAgent == null ? null : userAgent.left(255),
        Document_Hash__c = hash,
        Original_Version_Id__c = meta.Id
      );
      saveFile(
        new List<Id>{ r.Id },
        'signature-' + r.Name + '.png',
        png,
        'PMS:Signature'
      );
      SignResult s = new SignResult();
      s.requestName = r.Name;
      s.title = r.Title__c;
      s.signerName = name;
      s.signerEmail = email;
      s.signedAtLabel = now.format('d MMMM yyyy, HH:mm:ss z');
      s.ip = ip;
      s.documentHash = hash;
      s.companyName = companyName();
      PMS_CustomerNotifications.emailUser(
        r.OwnerId,
        'Signed: ' + r.Title__c + ' (' + r.Name + ')',
        name +
          ' of ' +
          r.Account__r.Name +
          ' signed "' +
          r.Title__c +
          '" on ' +
          s.signedAtLabel +
          '.',
        r.Id
      );
      return s;
    } catch (Exception e) {
      throw handled(e);
    }
  }

  @AuraEnabled
  public static DocRow attachSignedPdf(Id requestId, String base64Data) {
    try {
      Ctx c = ctx();
      PMS_Document_Request__c r = myRequest(requestId, c.accountId);
      if (
        r.Status__c != 'Signed' || String.isNotBlank(r.Signed_Version_Id__c)
      ) {
        throw new PMS_Exception('The signed copy is already filed.');
      }
      String b64 = base64Data == null
        ? ''
        : (base64Data.contains(',')
            ? base64Data.substringAfter(',')
            : base64Data);
      if (!b64.startsWith('JVBER')) {
        // "%PDF" in base64
        throw new PMS_Exception('The signed copy is not a PDF.');
      }
      if (b64.length() > (MAX_SIGNED_BYTES / 3) * 4 + 4) {
        throw new PMS_Exception(
          'The signed copy is too large to file here. Our staff will prepare it.'
        );
      }
      Blob pdf = decode(b64);
      b64 = null;
      List<Id> linkTo = new List<Id>{ r.Id };
      if (r.Booking__c != null) {
        linkTo.add(r.Booking__c);
      }
      if (r.Project__c != null) {
        linkTo.add(r.Project__c);
      }
      Id versionId = saveFile(
        linkTo,
        (r.Title__c +
          ' (signed ' +
          r.Name +
          ').pdf')
          .replaceAll('[\\\\/:*?"<>|]', '_'),
        pdf,
        'PMS:Signed'
      );
      update new PMS_Document_Request__c(
        Id = r.Id,
        Signed_Version_Id__c = versionId
      );
      for (DocRow d : documents(c.accountId)) {
        if (d.id == r.Id) {
          return d;
        }
      }
      return null;
    } catch (Exception e) {
      throw handled(e);
    }
  }

  @AuraEnabled
  public static void declineDocument(Id requestId, String reason) {
    try {
      Ctx c = ctx();
      PMS_Document_Request__c r = myRequest(requestId, c.accountId);
      if (r.Status__c != 'Sent' && r.Status__c != 'Viewed') {
        throw new PMS_Exception('This document can no longer be declined.');
      }
      if (String.isBlank(reason)) {
        throw new PMS_Exception('Tell us why, so we can help.');
      }
      update new PMS_Document_Request__c(
        Id = r.Id,
        Status__c = 'Declined',
        Decline_Reason__c = reason.trim().left(32000)
      );
      PMS_CustomerNotifications.emailUser(
        r.OwnerId,
        'Declined: ' + r.Title__c + ' (' + r.Name + ')',
        r.Account__r.Name +
          ' declined "' +
          r.Title__c +
          '". Reason: ' +
          reason.trim().abbreviate(1000),
        r.Id
      );
    } catch (Exception e) {
      throw handled(e);
    }
  }

  // ------------------------------------------------------------------ check-in

  @AuraEnabled
  public static List<PMS_CheckInService.Eligible> submitCheckIn(
    Id bookingId,
    String formJson
  ) {
    try {
      Ctx c = ctx();
      PMS_Booking__c b = PMS_CheckInService.load(bookingId);
      if (b == null || b.Account__c != c.accountId) {
        throw new PMS_Exception('Booking not found.');
      }
      PMS_CheckInService.submit(b, formJson, 'Customer Portal');
      return PMS_CheckInService.forAccount(c.accountId);
    } catch (Exception e) {
      throw handled(e);
    }
  }

  // ------------------------------------------------------------------ projects and approvals

  private static List<ProjectRow> projects(Id accountId) {
    List<ProjectRow> rows = new List<ProjectRow>();
    for (PMS_Project__c p : [
      SELECT
        Id,
        Name,
        Status__c,
        Health__c,
        Percent_Complete__c,
        Start_Date__c,
        End_Date__c,
        Site__r.Name,
        (
          SELECT
            Id,
            Name,
            Due_Date__c,
            Amount__c,
            Status__c,
            Accepted_At__c,
            Customer_Comment__c
          FROM Milestones__r
          ORDER BY Due_Date__c
        ),
        (
          SELECT
            Id,
            Name,
            Title__c,
            Type__c,
            Details__c,
            Amount__c,
            Schedule_Impact_Days__c,
            Due_Date__c,
            Status__c,
            Decided_At__c,
            Decision_Comment__c
          FROM Approval_Requests__r
          WHERE Status__c IN :VISIBLE_APPROVALS
          ORDER BY CreatedDate DESC
        )
      FROM PMS_Project__c
      WHERE Account__c = :accountId AND Status__c != 'Cancelled'
      ORDER BY Start_Date__c DESC NULLS LAST
      LIMIT 20
    ]) {
      ProjectRow r = new ProjectRow();
      r.id = p.Id;
      r.name = p.Name;
      r.status = p.Status__c;
      r.health = p.Health__c;
      r.percentComplete = p.Percent_Complete__c;
      r.startDate = p.Start_Date__c;
      r.endDate = p.End_Date__c;
      r.siteName = p.Site__r?.Name;
      for (PMS_Milestone__c m : p.Milestones__r) {
        MilestoneRow mr = new MilestoneRow();
        mr.id = m.Id;
        mr.name = m.Name;
        mr.dueDate = m.Due_Date__c;
        mr.amount = m.Amount__c;
        mr.status = m.Status__c;
        mr.canAccept = m.Status__c == 'Completed';
        mr.acceptedAt = m.Accepted_At__c;
        mr.comment = m.Customer_Comment__c;
        r.milestones.add(mr);
      }
      for (PMS_Approval_Request__c a : p.Approval_Requests__r) {
        ApprovalRow ar = new ApprovalRow();
        ar.id = a.Id;
        ar.name = a.Name;
        ar.title = a.Title__c;
        ar.type = a.Type__c;
        ar.details = a.Details__c;
        ar.amount = a.Amount__c;
        ar.scheduleDays = a.Schedule_Impact_Days__c;
        ar.dueDate = a.Due_Date__c;
        ar.status = a.Status__c;
        ar.canDecide = a.Status__c == 'Pending';
        ar.decidedAt = a.Decided_At__c;
        ar.comment = a.Decision_Comment__c;
        r.approvals.add(ar);
      }
      rows.add(r);
    }
    return rows;
  }

  @AuraEnabled
  public static List<ProjectRow> acceptMilestone(
    Id milestoneId,
    String comment
  ) {
    try {
      Ctx c = ctx();
      PMS_Milestone__c m = myMilestone(milestoneId, c.accountId);
      if (m.Status__c != 'Completed') {
        throw new PMS_Exception('Only completed milestones can be accepted.');
      }
      update new PMS_Milestone__c(
        Id = m.Id,
        Status__c = 'Accepted',
        Accepted_By__c = c.contactId,
        Accepted_At__c = Datetime.now(),
        Customer_Comment__c = String.isBlank(comment)
          ? null
          : comment.trim().left(32000)
      );
      PMS_CustomerNotifications.emailUser(
        pmOf(m),
        'Milestone accepted: ' + m.Name,
        c.accountName +
          ' accepted "' +
          m.Name +
          '" on ' +
          m.Project__r.Name +
          '.' +
          (String.isBlank(comment) ? '' : ' Comment: ' + comment.trim()),
        m.Id
      );
      return projects(c.accountId);
    } catch (Exception e) {
      throw handled(e);
    }
  }

  /** The customer doesn't accept a completed milestone yet: their comment opens a Case for the project team. */
  @AuraEnabled
  public static List<ProjectRow> queryMilestone(
    Id milestoneId,
    String comment
  ) {
    try {
      Ctx c = ctx();
      PMS_Milestone__c m = myMilestone(milestoneId, c.accountId);
      if (String.isBlank(comment)) {
        throw new PMS_Exception(
          'Tell us what isn\'t finished or needs another look.'
        );
      }
      update new PMS_Milestone__c(
        Id = m.Id,
        Customer_Comment__c = comment.trim().left(32000)
      );
      Case cs = new Case(
        Subject = ('Milestone query: ' +
          m.Name +
          ' (' +
          m.Project__r.Name +
          ')')
          .left(255),
        Description = comment.trim(),
        Origin = 'Web',
        Status = 'New',
        Priority = 'Medium',
        AccountId = c.accountId,
        ContactId = c.contactId,
        PMS_Module__c = 'Project'
      );
      insert cs;
      PMS_CustomerNotifications.emailUser(
        pmOf(m),
        'Milestone queried: ' + m.Name,
        c.accountName +
          ' has a question about "' +
          m.Name +
          '": ' +
          comment.trim().abbreviate(1000),
        cs.Id
      );
      return projects(c.accountId);
    } catch (Exception e) {
      throw handled(e);
    }
  }

  @AuraEnabled
  public static List<ProjectRow> decideApproval(
    Id requestId,
    Boolean approve,
    String comment
  ) {
    try {
      Ctx c = ctx();
      List<PMS_Approval_Request__c> as2 = [
        SELECT
          Id,
          Name,
          Title__c,
          Status__c,
          OwnerId,
          Project__r.Name,
          Project__r.Project_Manager__c
        FROM PMS_Approval_Request__c
        WHERE Id = :requestId AND Account__c = :c.accountId
        LIMIT 1
      ];
      if (as2.isEmpty()) {
        throw new PMS_Exception('Request not found.');
      }
      PMS_Approval_Request__c a = as2[0];
      if (a.Status__c != 'Pending') {
        throw new PMS_Exception('This request has already been decided.');
      }
      if (approve != true && String.isBlank(comment)) {
        throw new PMS_Exception('Tell us why you are rejecting it.');
      }
      String decision = approve == true ? 'Approved' : 'Rejected';
      update new PMS_Approval_Request__c(
        Id = a.Id,
        Status__c = decision,
        Decided_By__c = c.contactId,
        Decided_At__c = Datetime.now(),
        Decision_Comment__c = String.isBlank(comment)
          ? null
          : comment.trim().left(32000)
      );
      Id notify = a.Project__r?.Project_Manager__c != null
        ? a.Project__r.Project_Manager__c
        : a.OwnerId;
      PMS_CustomerNotifications.emailUser(
        notify,
        decision + ': ' + a.Title__c + ' (' + a.Name + ')',
        c.accountName +
          ' ' +
          decision.toLowerCase() +
          ' "' +
          a.Title__c +
          '"' +
          (String.isBlank(comment) ? '.' : '. Comment: ' + comment.trim()),
        a.Id
      );
      return projects(c.accountId);
    } catch (Exception e) {
      throw handled(e);
    }
  }

  private static PMS_Milestone__c myMilestone(Id milestoneId, Id accountId) {
    List<PMS_Milestone__c> ms = [
      SELECT
        Id,
        Name,
        Status__c,
        Project__r.Name,
        Project__r.Project_Manager__c,
        Project__r.OwnerId
      FROM PMS_Milestone__c
      WHERE Id = :milestoneId AND Project__r.Account__c = :accountId
      LIMIT 1
    ];
    if (ms.isEmpty()) {
      throw new PMS_Exception('Milestone not found.');
    }
    return ms[0];
  }

  private static Id pmOf(PMS_Milestone__c m) {
    return m.Project__r.Project_Manager__c != null
      ? m.Project__r.Project_Manager__c
      : m.Project__r.OwnerId;
  }

  // ------------------------------------------------------------------ helpers

  private class Ctx {
    Id accountId;
    Id contactId;
    String accountName;
  }

  private static Ctx ctx() {
    Ctx c = new Ctx();
    if (Test.isRunningTest() && testAccountId != null) {
      c.accountId = testAccountId;
      c.contactId = testContactId;
    } else {
      User u = [
        SELECT ContactId, Contact.AccountId
        FROM User
        WHERE Id = :UserInfo.getUserId()
      ];
      c.accountId = u.Contact?.AccountId;
      c.contactId = u.ContactId;
    }
    if (c.accountId == null) {
      throw new PMS_Exception(
        'This page is for customers with a portal login.'
      );
    }
    c.accountName = [SELECT Name FROM Account WHERE Id = :c.accountId].Name;
    return c;
  }

  private static FileData fileData(Id versionId, Integer maxBytes) {
    ContentVersion meta = [
      SELECT Id, Title, FileExtension, ContentSize
      FROM ContentVersion
      WHERE Id = :versionId
    ];
    if (meta.ContentSize > maxBytes) {
      throw new PMS_Exception(
        'This file is too large to open here (' +
          (meta.ContentSize / 1000000) +
          ' MB). Please ask us to email it.'
      );
    }
    FileData f = new FileData();
    f.fileName =
      meta.Title +
      (String.isBlank(meta.FileExtension) ? '' : '.' + meta.FileExtension);
    f.extension = meta.FileExtension;
    f.size = meta.ContentSize;
    f.base64 = EncodingUtil.base64Encode(
      [SELECT VersionData FROM ContentVersion WHERE Id = :versionId].VersionData
    );
    return f;
  }

  private static Blob decode(String base64Data) {
    try {
      return EncodingUtil.base64Decode(
        base64Data.contains(',') ? base64Data.substringAfter(',') : base64Data
      );
    } catch (Exception e) {
      throw new PMS_Exception('The file could not be read. Please try again.');
    }
  }

  private static Id saveFile(
    List<Id> linkTo,
    String fileName,
    Blob data,
    String description
  ) {
    ContentVersion v = new ContentVersion(
      Title = fileName.substringBeforeLast('.').left(255),
      PathOnClient = fileName,
      VersionData = data,
      Description = description
    );
    insert v;
    Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :v.Id]
    .ContentDocumentId;
    List<ContentDocumentLink> links = new List<ContentDocumentLink>();
    for (Id target : linkTo) {
      links.add(
        new ContentDocumentLink(
          ContentDocumentId = docId,
          LinkedEntityId = target,
          ShareType = 'V',
          Visibility = 'AllUsers'
        )
      );
    }
    insert links;
    return v.Id;
  }

  private static String companyName() {
    try {
      return [SELECT Name FROM Organization LIMIT 1].Name;
    } catch (Exception e) {
      return null;
    }
  }

  private static String sourceIp() {
    if (Test.isRunningTest()) {
      return null;
    }
    try {
      Map<String, String> s = Auth.SessionManagement.getCurrentSession();
      return s == null ? null : s.get('SourceIp');
    } catch (Exception e) {
      return null;
    }
  }

  private static AuraHandledException handled(Exception e) {
    String msg = e instanceof PMS_Exception
      ? e.getMessage()
      : 'Something went wrong. Please try again or contact us.';
    if (!(e instanceof PMS_Exception)) {
      System.debug(
        LoggingLevel.ERROR,
        'PMS customer portal v2: ' +
          e.getMessage() +
          '\n' +
          e.getStackTraceString()
      );
    }
    AuraHandledException ex = new AuraHandledException(msg);
    ex.setMessage(msg);
    return ex;
  }
}
