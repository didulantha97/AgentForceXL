/**
 * Demo data steps for money: invoices, charges, payments, payment plans and reminder history (billing),
 * plus the overdue-wave and month-end packs. Called by PMS_DemoData, one step per transaction.
 *
 * Invoices are inserted first, then their charges, then payments, so the real finance triggers work out totals,
 * balances and the Paid / Partially Paid / Overdue status exactly as they do in production.
 */
public with sharing class PMS_DemoDataBilling {
  /** Invoices created in this step, by key, plus what each one adds up to (tax included). */
  private class Books {
    PMS_DemoData.Ctx c;
    Map<String, PMS_Invoice__c> invs = new Map<String, PMS_Invoice__c>();
    Map<String, Decimal> gross = new Map<String, Decimal>();
    Map<String, Integer> overdue = new Map<String, Integer>();
    Books(PMS_DemoData.Ctx c) {
      this.c = c;
    }

    /** An invoice. Status Issued lets the finance trigger decide Paid, Partially Paid or Overdue. */
    void invoice(
      String key,
      String recordType,
      String account,
      String booking,
      String project,
      String matter,
      Integer issueDay,
      Integer dueDay,
      String status,
      String stage
    ) {
      PMS_Invoice__c i = new PMS_Invoice__c(
        RecordTypeId = c.rt(PMS_Invoice__c.SObjectType, recordType),
        Account__c = c.ref('a.' + account),
        Booking__c = booking == null ? null : c.ref(booking),
        Project__c = project == null ? null : c.ref(project),
        Matter__c = matter == null ? null : c.ref(matter),
        Issue_Date__c = c.day(issueDay),
        Due_Date__c = c.day(dueDay),
        Status__c = status,
        Currency_Code__c = 'SEK',
        Dunning_Stage__c = stage,
        // Demo invoices must never be chased by the real dunning job (the reminder history is hand-made).
        Dunning_Paused__c = true,
        Dunning_Pause_Reason__c = 'Demo data'
      );
      invs.put(key, i);
      overdue.put(key, dueDay < 0 ? -dueDay : 0);
      c.add(i, key);
    }

    /** A charge on an invoice (call after the invoices are saved). */
    void charge(
      String invoiceKey,
      String type,
      String description,
      Decimal qty,
      Decimal price,
      Decimal tax,
      Integer serviceDay
    ) {
      PMS_Invoice__c i = invs.get(invoiceKey);
      c.add(
        new PMS_Charge__c(
          Invoice__c = i.Id,
          Booking__c = i.Booking__c,
          Project__c = i.Project__c,
          Matter__c = i.Matter__c,
          Account__c = i.Account__c,
          Charge_Type__c = type,
          Description__c = description,
          Quantity__c = qty,
          Unit_Price__c = price,
          Tax_Rate__c = tax,
          Service_Date__c = c.day(serviceDay),
          Status__c = 'Invoiced'
        ),
        'chg.' + invoiceKey
      );
      Decimal add = qty * price * (1 + tax / 100);
      gross.put(
        invoiceKey,
        (gross.containsKey(invoiceKey) ? gross.get(invoiceKey) : 0) + add
      );
    }

    /** What the invoice adds up to; a fraction below 1 gives a part payment. */
    Decimal part(String invoiceKey, Decimal fraction) {
      return (gross.get(invoiceKey) * fraction).setScale(2);
    }

    /** A payment against an invoice, a booking, or both. */
    void payment(
      String invoiceKey,
      String booking,
      String account,
      Decimal amount,
      String type,
      String method,
      String status,
      Integer receivedDay
    ) {
      c.add(
        new PMS_Payment__c(
          Invoice__c = invoiceKey == null ? null : invs.get(invoiceKey).Id,
          Booking__c = booking == null ? null : c.ref(booking),
          Account__c = c.ref('a.' + account),
          Amount__c = amount.setScale(2),
          Payment_Type__c = type,
          Method__c = method,
          Status__c = status,
          Received_Date__c = receivedDay == null ? null : c.day(receivedDay)
        ),
        'pay.' + (invoiceKey == null ? booking : invoiceKey)
      );
    }

    /** Reminder history for an invoice: one event per step reached, dated relative to how late it is now. */
    void history(String invoiceKey, List<String> stages, List<Integer> atDays) {
      PMS_Invoice__c i = invs.get(invoiceKey);
      Integer late = overdue.get(invoiceKey);
      for (Integer k = 0; k < stages.size(); k++) {
        c.add(
          new PMS_Dunning_Event__c(
            Invoice__c = i.Id,
            Stage__c = stages[k],
            Days_Overdue__c = atDays[k],
            Balance__c = gross.get(invoiceKey).setScale(2),
            Sent_At__c = c.nowDt.addDays(-Math.max(0, late - atDays[k])),
            Sent_To__c = 'ekonomi@example.com',
            Fee_Posted__c = stages[k] == 'Reminder 2' ? 60 : 0,
            Note__c = 'Skickat av demodata.'
          ),
          'dun.' + invoiceKey + '.' + k
        );
      }
    }

    /** A payment plan for an overdue invoice: first instalment paid, second late, third coming. */
    void plan(String planKey, String invoiceKey, String account) {
      PMS_Invoice__c i = invs.get(invoiceKey);
      c.add(
        new PMS_Payment_Plan__c(
          Invoice__c = i.Id,
          Account__c = i.Account__c,
          Total__c = gross.get(invoiceKey).setScale(2),
          Paid_At_Start__c = 0,
          Status__c = 'Active',
          Accepted_At__c = c.nowDt.addDays(-40)
        ),
        planKey
      );
    }

    void instalments(String planKey, String invoiceKey) {
      Decimal each = (gross.get(invoiceKey) / 3).setScale(2);
      List<Integer> due = new List<Integer>{ -35, -7, 21 };
      List<String> status = new List<String>{ 'Paid', 'Overdue', 'Due' };
      for (Integer k = 0; k < 3; k++) {
        c.add(
          new PMS_Payment_Plan_Instalment__c(
            Plan__c = c.ref(planKey),
            Number__c = k + 1,
            Amount__c = each,
            Due_Date__c = c.day(due[k]),
            Status__c = status[k]
          ),
          'pli.' + planKey + '.' + k
        );
      }
    }
  }

  // ------------------------------------------------------------------ billing (baseline)

  public static void billing(PMS_DemoData.Ctx c) {
    Books b = new Books(c);

    // Hotel folios
    b.invoice(
      'iv.h1',
      'Folio',
      'g5',
      'bk.h5',
      null,
      null,
      -1,
      13,
      'Issued',
      null
    );
    b.invoice(
      'iv.h2',
      'Folio',
      'g4',
      'bk.h4',
      null,
      null,
      0,
      7,
      'Issued',
      null
    );
    b.invoice(
      'iv.h3',
      'Folio',
      'g3',
      'bk.h3',
      null,
      null,
      0,
      14,
      'Issued',
      null
    );
    b.invoice(
      'iv.h4',
      'Folio',
      'g2',
      'bk.p2',
      null,
      null,
      -30,
      -15,
      'Issued',
      'Reminder 1'
    );
    b.invoice(
      'iv.h5',
      'Folio',
      'g1',
      'bk.p1',
      null,
      null,
      -57,
      -45,
      'Issued',
      'Reminder 2'
    );
    b.invoice(
      'iv.h6',
      'Folio',
      'g3',
      'bk.p0',
      null,
      null,
      -108,
      -90,
      'Issued',
      'Payment Plan'
    );
    b.invoice(
      'iv.h7',
      'Folio',
      'g1',
      'bk.u5',
      null,
      null,
      0,
      30,
      'Draft',
      null
    );
    b.invoice(
      'iv.h8',
      'Folio',
      'g5',
      'bk.p3',
      null,
      null,
      -10,
      4,
      'Issued',
      null
    );
    b.invoice(
      'iv.h9',
      'Folio',
      'g6',
      'bk.p4',
      null,
      null,
      -6,
      8,
      'Issued',
      null
    );
    b.invoice(
      'iv.x1',
      'Folio',
      'g7',
      'bk.c1',
      null,
      null,
      -3,
      11,
      'Void',
      null
    );
    // Rent invoices
    b.invoice(
      'iv.p1',
      'Rent_Invoice',
      't1',
      'bk.l1',
      null,
      null,
      -12,
      -2,
      'Issued',
      null
    );
    b.invoice(
      'iv.p2',
      'Rent_Invoice',
      't2',
      'bk.l2',
      null,
      null,
      -2,
      10,
      'Issued',
      null
    );
    b.invoice(
      'iv.p3',
      'Rent_Invoice',
      't3',
      'bk.l3',
      null,
      null,
      -2,
      3,
      'Issued',
      null
    );
    b.invoice(
      'iv.p4',
      'Rent_Invoice',
      't5',
      'bk.l5',
      null,
      null,
      -30,
      -15,
      'Issued',
      'Reminder 1'
    );
    b.invoice(
      'iv.p5',
      'Rent_Invoice',
      't4',
      'bk.l4',
      null,
      null,
      -60,
      -45,
      'Issued',
      'Payment Plan'
    );
    b.invoice(
      'iv.p6',
      'Rent_Invoice',
      't5',
      'bk.l5',
      null,
      null,
      -110,
      -95,
      'Issued',
      'Collections'
    );
    b.invoice(
      'iv.p7',
      'Rent_Invoice',
      't2',
      'bk.l2',
      null,
      null,
      0,
      30,
      'Draft',
      null
    );
    b.invoice(
      'iv.p8',
      'Rent_Invoice',
      't1',
      'bk.l1',
      null,
      null,
      -43,
      -33,
      'Issued',
      null
    );
    b.invoice(
      'iv.p9',
      'Rent_Invoice',
      't3',
      'bk.l3',
      null,
      null,
      -72,
      -62,
      'Issued',
      null
    );
    b.invoice(
      'iv.x2',
      'Rent_Invoice',
      't7',
      'bk.l7',
      null,
      null,
      -20,
      -6,
      'Credited',
      null
    );
    // Project invoices
    b.invoice(
      'iv.j1',
      'Project_Invoice',
      'p2',
      null,
      'pj.1',
      null,
      -25,
      -5,
      'Issued',
      null
    );
    b.invoice(
      'iv.j2',
      'Project_Invoice',
      'p2',
      null,
      'pj.1',
      null,
      -3,
      17,
      'Issued',
      null
    );
    b.invoice(
      'iv.j3',
      'Project_Invoice',
      'p1',
      null,
      'pj.2',
      null,
      -30,
      -15,
      'Issued',
      'Reminder 1'
    );
    b.invoice(
      'iv.j4',
      'Project_Invoice',
      'p1',
      null,
      'pj.2',
      null,
      -60,
      -45,
      'Issued',
      'Payment Plan'
    );
    b.invoice(
      'iv.j5',
      'Project_Invoice',
      'p2',
      null,
      'pj.3',
      null,
      0,
      30,
      'Draft',
      null
    );
    b.invoice(
      'iv.j6',
      'Project_Invoice',
      'p1',
      null,
      'pj.2',
      null,
      -8,
      6,
      'Issued',
      null
    );
    b.invoice(
      'iv.j7',
      'Project_Invoice',
      'p2',
      null,
      'pj.1',
      null,
      -6,
      8,
      'Issued',
      null
    );
    b.invoice(
      'iv.j8',
      'Project_Invoice',
      'p1',
      null,
      'pj.4',
      null,
      -105,
      -95,
      'Issued',
      null
    );
    b.invoice(
      'iv.j9',
      'Project_Invoice',
      'p1',
      null,
      'pj.4',
      null,
      -140,
      -130,
      'Issued',
      null
    );
    // Client bills
    b.invoice(
      'iv.c1',
      'Client_Bill',
      'c1',
      'bk.a.p1',
      null,
      'mt.3',
      -2,
      12,
      'Issued',
      null
    );
    b.invoice(
      'iv.c2',
      'Client_Bill',
      'c6',
      'bk.a.t5',
      null,
      'mt.6',
      0,
      14,
      'Issued',
      null
    );
    b.invoice(
      'iv.c3',
      'Client_Bill',
      'c2',
      'bk.a.p6',
      null,
      'mt.4',
      -30,
      -15,
      'Issued',
      'Reminder 1'
    );
    b.invoice(
      'iv.c4',
      'Client_Bill',
      'c3',
      'bk.a.p4',
      null,
      'mt.5',
      -60,
      -45,
      'Issued',
      'Payment Plan'
    );
    b.invoice(
      'iv.c5',
      'Client_Bill',
      'c4',
      null,
      null,
      'mt.1',
      0,
      30,
      'Draft',
      null
    );
    b.invoice(
      'iv.c6',
      'Client_Bill',
      'c1',
      null,
      null,
      'mt.3',
      -5,
      9,
      'Issued',
      null
    );
    c.save();

    // Charges (the finance trigger totals each invoice and sets its status)
    b.charge('iv.h1', 'Room Night', 'Dubbelrum, 1 natt', 1, 1290, 12, -1);
    b.charge(
      'iv.h1',
      'Food and Beverage',
      'Middag i restaurangen',
      1,
      285,
      12,
      -1
    );
    b.charge('iv.h2', 'Room Night', 'Dubbelrum, 3 nätter', 3, 1290, 12, -2);
    b.charge('iv.h2', 'Extra', 'Minibar', 1, 245, 25, -1);
    b.charge(
      'iv.h3',
      'Room Night',
      'Superior dubbelrum, 4 nätter',
      4,
      1690,
      12,
      -3
    );
    b.charge(
      'iv.h4',
      'Room Night',
      'Superior dubbelrum, 2 nätter',
      2,
      1690,
      12,
      -31
    );
    b.charge(
      'iv.h5',
      'Room Night',
      'Superior dubbelrum, 3 nätter',
      3,
      1690,
      12,
      -58
    );
    b.charge('iv.h5', 'Extra', 'Parkering', 3, 150, 25, -58);
    b.charge(
      'iv.h6',
      'Room Night',
      'Superior dubbelrum, 2 nätter',
      2,
      1690,
      12,
      -109
    );
    b.charge('iv.h7', 'Room Night', 'Dubbelrum, 2 nätter', 2, 1290, 12, 14);
    b.charge('iv.h8', 'Room Night', 'Dubbelrum, 2 nätter', 2, 1290, 12, -12);
    b.charge('iv.h9', 'Room Night', 'Dubbelrum, 2 nätter', 2, 1290, 12, -8);
    b.charge('iv.p1', 'Rent', 'Hyra A-101', 1, 11900, 0, -12);
    b.charge('iv.p2', 'Rent', 'Lokalhyra A-102', 1, 28500, 25, -2);
    b.charge('iv.p2', 'Service Charge', 'Serviceavgift A-102', 1, 3200, 25, -2);
    b.charge('iv.p3', 'Rent', 'Hyra A-103', 1, 14200, 0, -2);
    b.charge('iv.p3', 'Parking', 'Garageplats', 1, 1200, 25, -2);
    b.charge('iv.p4', 'Rent', 'Lokalhyra A-105', 1, 33000, 25, -30);
    b.charge(
      'iv.p4',
      'Service Charge',
      'Serviceavgift A-105',
      1,
      4100,
      25,
      -30
    );
    b.charge('iv.p5', 'Rent', 'Hyra A-104', 1, 9800, 0, -60);
    b.charge('iv.p5', 'Utilities', 'El och vatten', 1, 640, 0, -60);
    b.charge(
      'iv.p6',
      'Service Charge',
      'Serviceavgift kvartal 3',
      1,
      12400,
      25,
      -110
    );
    b.charge('iv.p7', 'Rent', 'Lokalhyra A-102', 1, 28500, 25, 30);
    b.charge('iv.p8', 'Rent', 'Hyra A-101', 1, 11900, 0, -43);
    b.charge('iv.p9', 'Rent', 'Hyra A-103', 1, 14200, 0, -72);
    b.charge(
      'iv.j1',
      'Milestone',
      'Milstolpe: Rivning klar',
      1,
      300000,
      25,
      -25
    );
    b.charge(
      'iv.j2',
      'Milestone',
      'Milstolpe: Stomme, första delen',
      1,
      450000,
      25,
      -3
    );
    b.charge(
      'iv.j3',
      'Fixed Fee',
      'Fast arvode fasadprojektering',
      1,
      150000,
      25,
      -30
    );
    b.charge(
      'iv.j4',
      'Billable Hours',
      'Projektledning, 38 timmar',
      38,
      1250,
      25,
      -60
    );
    b.charge(
      'iv.j5',
      'Billable Hours',
      'Energikartläggning, 30 timmar',
      30,
      1100,
      25,
      0
    );
    b.charge('iv.j6', 'Fixed Fee', 'Fast arvode etapp 1', 1, 100000, 25, -8);
    b.charge(
      'iv.j7',
      'Billable Hours',
      'Byggledning, 120 timmar',
      120,
      1250,
      25,
      -6
    );
    b.charge(
      'iv.j8',
      'Fixed Fee',
      'Slutfakturering flytt',
      1,
      200000,
      25,
      -105
    );
    b.charge('iv.j9', 'Fixed Fee', 'Delfakturering flytt', 1, 100000, 25, -140);
    b.charge(
      'iv.c1',
      'Consultation Fee',
      'Fysioterapi, första besök',
      1,
      950,
      0,
      -2
    );
    b.charge(
      'iv.c2',
      'Consultation Fee',
      'Fysioterapi, återbesök',
      1,
      750,
      0,
      0
    );
    b.charge('iv.c3', 'Consultation Fee', 'Hälsokontroll', 1, 1400, 25, -30);
    b.charge(
      'iv.c4',
      'Consultation Fee',
      'Samtalsterapi, 2 besök',
      2,
      1100,
      0,
      -60
    );
    b.charge('iv.c4', 'Expense', 'Testmaterial', 1, 300, 0, -60);
    b.charge('iv.c5', 'Fixed Fee', 'Utredning och intyg', 1, 2500, 0, 0);
    b.charge('iv.c6', 'Fixed Fee', 'Rehabiliteringsprogram', 1, 4500, 0, -5);
    c.save();

    // Payments: paid in full, part paid, pending, failed, refunded, and older months for the revenue trend
    b.payment(
      'iv.h1',
      null,
      'g5',
      b.part('iv.h1', 1),
      'Payment',
      'Card',
      'Succeeded',
      0
    );
    b.payment(
      'iv.h2',
      null,
      'g4',
      1000,
      'Payment',
      'Bank Transfer',
      'Pending',
      null
    );
    b.payment(
      'iv.h3',
      null,
      'g3',
      b.part('iv.h3', 0.5),
      'Deposit',
      'Bank Transfer',
      'Succeeded',
      -2
    );
    b.payment('iv.h4', null, 'g2', 3800, 'Payment', 'Card', 'Failed', null);
    b.payment(
      'iv.h8',
      null,
      'g5',
      b.part('iv.h8', 1),
      'Payment',
      'Card',
      'Succeeded',
      -9
    );
    b.payment(
      'iv.h9',
      null,
      'g6',
      b.part('iv.h9', 1),
      'Payment',
      'Card',
      'Succeeded',
      -5
    );
    b.payment(
      'iv.p1',
      null,
      't1',
      b.part('iv.p1', 1),
      'Payment',
      'Direct Debit',
      'Succeeded',
      0
    );
    b.payment(
      'iv.p3',
      null,
      't3',
      10000,
      'Payment',
      'Bank Transfer',
      'Succeeded',
      -1
    );
    b.payment(
      'iv.p8',
      null,
      't1',
      b.part('iv.p8', 1),
      'Payment',
      'Direct Debit',
      'Succeeded',
      -33
    );
    b.payment(
      'iv.p9',
      null,
      't3',
      b.part('iv.p9', 1),
      'Payment',
      'Bank Transfer',
      'Succeeded',
      -62
    );
    b.payment(
      'iv.j1',
      null,
      'p2',
      b.part('iv.j1', 1),
      'Payment',
      'Bank Transfer',
      'Succeeded',
      -20
    );
    b.payment(
      'iv.j6',
      null,
      'p1',
      b.part('iv.j6', 1),
      'Payment',
      'Bank Transfer',
      'Succeeded',
      0
    );
    b.payment(
      'iv.j7',
      null,
      'p2',
      100000,
      'Payment',
      'Bank Transfer',
      'Succeeded',
      -1
    );
    b.payment(
      'iv.j8',
      null,
      'p1',
      b.part('iv.j8', 1),
      'Payment',
      'Bank Transfer',
      'Succeeded',
      -95
    );
    b.payment(
      'iv.j9',
      null,
      'p1',
      b.part('iv.j9', 1),
      'Payment',
      'Bank Transfer',
      'Succeeded',
      -130
    );
    b.payment(
      'iv.c1',
      null,
      'c1',
      b.part('iv.c1', 1),
      'Payment',
      'Swish',
      'Succeeded',
      0
    );
    b.payment('iv.c2', null, 'c6', 750, 'Payment', 'Swish', 'Pending', null);
    b.payment('iv.c3', null, 'c2', 1750, 'Payment', 'Card', 'Failed', null);
    b.payment('iv.c6', null, 'c1', 2000, 'Payment', 'Swish', 'Succeeded', -1);
    // Booking-level money (deposits, rent received, retainers) from earlier months
    b.payment(
      null,
      'bk.p0',
      'g3',
      2000,
      'Deposit',
      'Bank Transfer',
      'Succeeded',
      -130
    );
    b.payment(null, 'bk.p1', 'g1', 2500, 'Deposit', 'Card', 'Succeeded', -75);
    b.payment(null, 'bk.p2', 'g2', 1800, 'Deposit', 'Card', 'Succeeded', -45);
    b.payment(null, 'bk.c2', 'g8', 2400, 'Deposit', 'Card', 'Succeeded', -12);
    b.payment(null, 'bk.c1', 'g7', 600, 'Payment', 'Card', 'Refunded', -4);
    b.payment(
      null,
      'bk.l1',
      't1',
      11900,
      'Payment',
      'Bank Transfer',
      'Succeeded',
      -95
    );
    b.payment(
      null,
      'bk.l3',
      't3',
      14200,
      'Payment',
      'Bank Transfer',
      'Succeeded',
      -125
    );
    b.payment(
      null,
      'bk.l5',
      't5',
      33000,
      'Payment',
      'Bank Transfer',
      'Succeeded',
      -155
    );
    b.payment(null, 'bk.a.p2', 'c6', 750, 'Payment', 'Card', 'Succeeded', -4);
    b.payment(null, 'bk.a.p5', 'c1', 950, 'Payment', 'Swish', 'Succeeded', -10);
    b.payment(null, 'bk.a.p8', 'c6', 750, 'Payment', 'Card', 'Succeeded', -25);
    b.payment(
      null,
      'bk.a.p4',
      'c3',
      4500,
      'Retainer',
      'Bank Transfer',
      'Succeeded',
      -65
    );
    b.payment(
      null,
      'bk.a.p3',
      'c5',
      2000,
      'Retainer',
      'Bank Transfer',
      'Succeeded',
      -95
    );
    b.payment(
      null,
      'bk.a.p7',
      'c4',
      2000,
      'Retainer',
      'Bank Transfer',
      'Succeeded',
      -125
    );
    c.save();

    // Payment plans (one per module) with a late instalment each, so "plan instalments overdue" is never empty
    b.plan('pl.h', 'iv.h6', 'g3');
    b.plan('pl.p', 'iv.p5', 't4');
    b.plan('pl.j', 'iv.j4', 'p1');
    b.plan('pl.c', 'iv.c4', 'c3');
    c.save();
    b.instalments('pl.h', 'iv.h6');
    b.instalments('pl.p', 'iv.p5');
    b.instalments('pl.j', 'iv.j4');
    b.instalments('pl.c', 'iv.c4');
    c.save();

    // Reminder history for the overdue invoices
    List<String> r1 = new List<String>{ 'Reminder 1' };
    List<Integer> r1d = new List<Integer>{ 10 };
    List<String> r2 = new List<String>{ 'Reminder 1', 'Reminder 2' };
    List<Integer> r2d = new List<Integer>{ 10, 20 };
    List<String> plan = new List<String>{
      'Reminder 1',
      'Reminder 2',
      'Plan Offered',
      'Payment Plan'
    };
    List<Integer> pland = new List<Integer>{ 10, 20, 30, 35 };
    b.history('iv.h4', r1, r1d);
    b.history('iv.h5', r2, r2d);
    b.history('iv.h6', plan, pland);
    b.history('iv.p4', r1, r1d);
    b.history('iv.p5', plan, pland);
    b.history(
      'iv.p6',
      new List<String>{
        'Reminder 1',
        'Reminder 2',
        'Plan Offered',
        'Collections'
      },
      new List<Integer>{ 10, 20, 30, 60 }
    );
    b.history('iv.j3', r1, r1d);
    b.history('iv.j4', plan, pland);
    b.history('iv.c3', r1, r1d);
    b.history('iv.c4', plan, pland);
    c.save();
  }

  // ------------------------------------------------------------------ overdue-wave pack

  public static void wave(PMS_DemoData.Ctx c) {
    Books b = new Books(c);
    // key, record type, account, booking, project, matter, days overdue, charge type, text, qty, price, tax
    List<List<String>> rows = new List<List<String>>{
      new List<String>{
        'w1',
        'Rent_Invoice',
        't3',
        'bk.l3',
        null,
        null,
        '10',
        'Rent',
        'Hyra A-103',
        '1',
        '14200',
        '0'
      },
      new List<String>{
        'w2',
        'Folio',
        'g2',
        'bk.p2',
        null,
        null,
        '18',
        'Room Night',
        'Extra nätter',
        '2',
        '1690',
        '12'
      },
      new List<String>{
        'w3',
        'Client_Bill',
        'c2',
        null,
        null,
        'mt.4',
        '25',
        'Consultation Fee',
        'Läkarbesök, 2 st',
        '2',
        '1100',
        '0'
      },
      new List<String>{
        'w4',
        'Project_Invoice',
        'p1',
        null,
        'pj.2',
        null,
        '33',
        'Billable Hours',
        'Projektledning, 40 timmar',
        '40',
        '1250',
        '25'
      },
      new List<String>{
        'w5',
        'Rent_Invoice',
        't5',
        'bk.l5',
        null,
        null,
        '41',
        'Rent',
        'Lokalhyra A-105',
        '1',
        '33000',
        '25'
      },
      new List<String>{
        'w6',
        'Client_Bill',
        'c3',
        null,
        null,
        'mt.5',
        '52',
        'Consultation Fee',
        'Samtalsterapi, 3 besök',
        '3',
        '1100',
        '0'
      },
      new List<String>{
        'w7',
        'Project_Invoice',
        'p2',
        null,
        'pj.1',
        null,
        '60',
        'Milestone',
        'Milstolpe: delleverans',
        '1',
        '250000',
        '25'
      },
      new List<String>{
        'w8',
        'Rent_Invoice',
        't4',
        'bk.l4',
        null,
        null,
        '75',
        'Rent',
        'Hyra A-104',
        '1',
        '9800',
        '0'
      },
      new List<String>{
        'w9',
        'Folio',
        'g1',
        'bk.p1',
        null,
        null,
        '90',
        'Room Night',
        'Extra nätter',
        '3',
        '1690',
        '12'
      },
      new List<String>{
        'w10',
        'Client_Bill',
        'c6',
        null,
        null,
        'mt.6',
        '100',
        'Fixed Fee',
        'Rehabiliteringsprogram',
        '1',
        '6500',
        '0'
      },
      new List<String>{
        'w11',
        'Rent_Invoice',
        't2',
        'bk.l2',
        null,
        null,
        '110',
        'Service Charge',
        'Serviceavgift, 6 månader',
        '6',
        '3200',
        '25'
      },
      new List<String>{
        'w12',
        'Project_Invoice',
        'p1',
        null,
        'pj.2',
        null,
        '120',
        'Fixed Fee',
        'Fast arvode etapp 2',
        '1',
        '180000',
        '25'
      }
    };
    Set<String> planned = new Set<String>{ 'w6', 'w8' };
    for (List<String> r : rows) {
      Integer age = Integer.valueOf(r[6]);
      String stage = planned.contains(r[0])
        ? 'Payment Plan'
        : (age >= 60
            ? 'Collections'
            : (age >= 30
                ? 'Plan Offered'
                : (age >= 20 ? 'Reminder 2' : 'Reminder 1')));
      b.invoice(
        'iv.' + r[0],
        r[1],
        r[2],
        r[3],
        r[4],
        r[5],
        -age - 14,
        -age,
        'Issued',
        stage
      );
    }
    c.save();
    for (List<String> r : rows) {
      Integer age = Integer.valueOf(r[6]);
      b.charge(
        'iv.' + r[0],
        r[7],
        r[8],
        Decimal.valueOf(r[9]),
        Decimal.valueOf(r[10]),
        Decimal.valueOf(r[11]),
        -age - 14
      );
    }
    c.save();

    // Plans for two of them
    b.plan('pl.w1', 'iv.w6', 'c3');
    b.plan('pl.w2', 'iv.w8', 't4');
    c.save();
    b.instalments('pl.w1', 'iv.w6');
    b.instalments('pl.w2', 'iv.w8');
    c.save();

    // Reminder history: every step an invoice has gone through
    for (List<String> r : rows) {
      Integer age = Integer.valueOf(r[6]);
      List<String> stages = new List<String>();
      List<Integer> days = new List<Integer>();
      stages.add('Reminder 1');
      days.add(10);
      if (age >= 20) {
        stages.add('Reminder 2');
        days.add(20);
      }
      if (age >= 30) {
        stages.add('Plan Offered');
        days.add(30);
      }
      if (planned.contains(r[0])) {
        stages.add('Payment Plan');
        days.add(35);
      } else if (age >= 60) {
        stages.add('Collections');
        days.add(60);
      }
      b.history('iv.' + r[0], stages, days);
    }
    c.save();
  }

  // ------------------------------------------------------------------ month-end pack

  public static void month(PMS_DemoData.Ctx c) {
    Date thisMonth = c.today.toStartOfMonth();
    c.account(
      'a.hotelowner',
      'Strandviken Fastighets AB',
      'Business',
      'Owner',
      'Strandvägen 10',
      'Stockholm',
      '114 56'
    );
    c.save();

    // Hotel owner statement for last month, still a draft
    c.add(
      new PMS_Owner_Statement__c(
        Site__c = c.ref('s.hotel'),
        Owner_Account__c = c.ref('a.hotelowner'),
        Period_Start__c = thisMonth.addMonths(-1),
        Period_End__c = thisMonth.addDays(-1),
        Gross_Rent__c = 412000,
        Management_Fee__c = 32960,
        Expenses__c = 58400,
        Arrears__c = 28600,
        Occupancy_Percent__c = 74.5,
        Occupancy_Basis__c = '12 rum, föregående månad',
        Generated_On__c = c.nowDt.addHours(-6),
        Status__c = 'Draft'
      ),
      'os.hotel'
    );
    c.save();

    // Vendor bills falling due, and one approved bill that is already late
    List<String> orders = new List<String>{
      'wo.2',
      'wo.5',
      'wo.7',
      'wo.2',
      'wo.5',
      'wo.7'
    };
    List<String> vendors = new List<String>{
      'a.v1',
      'a.v3',
      'a.v1',
      'a.v1',
      'a.v3',
      'a.v1'
    };
    List<Integer> due = new List<Integer>{ 3, 5, 7, 10, 14, -5 };
    List<Decimal> amount = new List<Decimal>{
      4200,
      18500,
      9600,
      3100,
      12800,
      7400
    };
    for (Integer k = 0; k < orders.size(); k++) {
      c.add(
        new PMS_Vendor_Bill__c(
          Site__c = c.ref('s.prop'),
          Work_Order__c = c.ref(orders[k]),
          Vendor_Account__c = c.ref(vendors[k]),
          Vendor_Invoice_Number__c = 'ME-' + (1001 + k),
          Status__c = k == 5 ? 'Approved' : 'Submitted',
          Amount__c = amount[k],
          Tax_Amount__c = (amount[k] * 0.25).setScale(2),
          Bill_Date__c = c.day(due[k] - 30),
          Due_Date__c = c.day(due[k]),
          Notes__c = 'Månadsavslut, demodata.'
        ),
        'vb.me.' + k
      );
    }
    c.save();

    // Rent reviews due
    c.add(
      new PMS_Rent_Adjustment__c(
        Lease__c = c.ref('bk.l3'),
        Kind__c = 'Manual',
        Status__c = 'Draft',
        Effective_Date__c = c.day(30),
        Old_Rent__c = 14200,
        New_Rent__c = 14500,
        Change_Percent__c = 2.11,
        Note__c = 'Årlig hyresjustering.'
      ),
      'ra.me.1'
    );
    c.add(
      new PMS_Rent_Adjustment__c(
        Lease__c = c.ref('bk.l4'),
        Kind__c = 'Manual',
        Status__c = 'Draft',
        Effective_Date__c = c.day(45),
        Old_Rent__c = 9800,
        New_Rent__c = 10050,
        Change_Percent__c = 2.55,
        Note__c = 'Årlig hyresjustering.'
      ),
      'ra.me.2'
    );
    c.add(
      new PMS_Rent_Adjustment__c(
        Lease__c = c.ref('bk.l2'),
        Kind__c = 'Index',
        Status__c = 'Approved',
        Effective_Date__c = c.day(40),
        Base_Rent__c = 26000,
        Old_Rent__c = 28500,
        New_Rent__c = 30500,
        Change_Percent__c = 7.02,
        Base_Index__c = 118.4,
        Current_Index__c = 129.2,
        Index_Period__c = 'KPI 2020=100, senaste månaden',
        Warning__c = 'Kontrollera uppsägningstiden innan avi skickas.'
      ),
      'ra.me.3'
    );
    c.add(
      new PMS_Rent_Adjustment__c(
        Lease__c = c.ref('bk.l5'),
        Kind__c = 'Index',
        Status__c = 'Draft',
        Effective_Date__c = c.day(60),
        Base_Rent__c = 30000,
        Old_Rent__c = 33000,
        New_Rent__c = 34900,
        Change_Percent__c = 5.76,
        Base_Index__c = 318.2,
        Current_Index__c = 347.9,
        Index_Period__c = 'KPI 1980=100, senaste månaden'
      ),
      'ra.me.4'
    );
    // The index values the reviews rest on
    Date lastMonth = thisMonth.addMonths(-1);
    c.add(
      new PMS_Index_Value__c(
        Series__c = 'KPI 2020=100',
        Year__c = lastMonth.year(),
        Month__c = lastMonth.month(),
        Value__c = 129.2,
        Source__c = 'SCB (demo)'
      ),
      'iv.me.20'
    );
    c.add(
      new PMS_Index_Value__c(
        Series__c = 'KPI 1980=100',
        Year__c = lastMonth.year(),
        Month__c = lastMonth.month(),
        Value__c = 347.9,
        Source__c = 'SCB (demo)'
      ),
      'iv.me.80'
    );
    c.save();
  }
}
