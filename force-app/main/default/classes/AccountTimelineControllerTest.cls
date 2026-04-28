/**
 * @description  Test class for AccountTimelineController v1.0.
 *
 *               Test scenarios:
 *               1. Happy path — activity timeline returns AccountHeader + Task + Event
 *               2. Date filter — THIS_MONTH still returns today's records
 *               3. No Account — Case with no AccountId returns empty list
 *               4. Invalid date filter is sanitized — does not break the query
 *               5. getCases first page — returns exactly 10 items
 *               6. getCases second page — returns remaining items
 *               7. getCases nested activities — Case has a linked Task
 *               8. getCases subtitle rows — subtitleRows populated for requested fields
 *               9. getCases invalid field — unknown field name is ignored safely
 *
 * @author       Araz
 * @version      1.0
 * @date         2026-04-28
 */
@isTest
private class AccountTimelineControllerTest {

    // ─────────────────────────────────────────────────────────────
    // TEST DATA SETUP
    // ─────────────────────────────────────────────────────────────

    /**
     * @description  Creates: Account → primary Case → Task + Event on Account
     *               + 12 extra Cases for pagination + 1 Task on the primary Case.
     */
    @TestSetup
    static void makeData() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        // Primary Case used in timeline and nested activity tests
        Case primaryCase = new Case(AccountId = acc.Id, Subject = 'Primary Test Case', Status = 'New');
        insert primaryCase;

        // Task linked to the Account (appears in Account Activities section)
        insert new Task(
            Subject      = 'Account Follow-up',
            WhatId       = acc.Id,
            Status       = 'Completed',
            ActivityDate = Date.today()
        );

        // Event linked to the Account
        insert new Event(
            Subject           = 'Account Meeting',
            WhatId            = acc.Id,
            StartDateTime     = DateTime.now(),
            DurationInMinutes = 30
        );

        // Task linked to the primary Case (appears nested inside the Case row)
        insert new Task(
            Subject      = 'Case Follow-up',
            WhatId       = primaryCase.Id,
            Status       = 'Open',
            ActivityDate = Date.today()
        );

        // 12 additional Cases for pagination testing (10 per page)
        List<Case> extraCases = new List<Case>();
        for (Integer i = 0; i < 12; i++) {
            extraCases.add(new Case(
                AccountId = acc.Id,
                Subject   = 'Pagination Case ' + i,
                Status    = 'New'
            ));
        }
        insert extraCases;
    }

    // ─────────────────────────────────────────────────────────────
    // ACTIVITY TIMELINE TESTS
    // ─────────────────────────────────────────────────────────────

    /**
     * @description  Happy path: AccountHeader must be first item;
     *               at least Task and Event must follow.
     */
    @isTest
    static void testGetAccountTimeline_happyPath() {
        Case c = [SELECT Id FROM Case WHERE Subject = 'Primary Test Case' LIMIT 1];

        Test.startTest();
        List<AccountTimelineController.TimelineItem> items =
            AccountTimelineController.getAccountTimeline(c.Id, 'ALL');
        Test.stopTest();

        System.assert(items.size() >= 3, 'Expected AccountHeader + Task + Event at minimum');
        System.assertEquals('AccountHeader', items[0].type,  'First item must be AccountHeader');
        System.assertEquals('Test Account',  items[0].title, 'AccountHeader title must match Account Name');
    }

    /**
     * @description  Date filter THIS_MONTH should still return today's records.
     */
    @isTest
    static void testGetAccountTimeline_withDateFilter() {
        Case c = [SELECT Id FROM Case WHERE Subject = 'Primary Test Case' LIMIT 1];

        Test.startTest();
        List<AccountTimelineController.TimelineItem> items =
            AccountTimelineController.getAccountTimeline(c.Id, 'THIS_MONTH');
        Test.stopTest();

        System.assertEquals('AccountHeader', items[0].type, 'First item must always be AccountHeader');
    }

    /**
     * @description  Case with no AccountId must return an empty list without throwing.
     */
    @isTest
    static void testGetAccountTimeline_noAccount() {
        Case orphan = new Case(Subject = 'Orphan Case', Status = 'New');
        insert orphan;

        Test.startTest();
        List<AccountTimelineController.TimelineItem> items =
            AccountTimelineController.getAccountTimeline(orphan.Id, 'ALL');
        Test.stopTest();

        System.assertEquals(0, items.size(), 'Expected empty list for Case with no Account');
    }

    /**
     * @description  An invalid / non-whitelisted dateFilter must be silently sanitized
     *               to 'no filter' instead of throwing or breaking the query.
     */
    @isTest
    static void testGetAccountTimeline_invalidDateFilterSanitized() {
        Case c = [SELECT Id FROM Case WHERE Subject = 'Primary Test Case' LIMIT 1];

        Test.startTest();
        // Pass a value that looks like a SOQL injection attempt
        List<AccountTimelineController.TimelineItem> items =
            AccountTimelineController.getAccountTimeline(c.Id, 'TODAY) OR (1=1');
        Test.stopTest();

        // Must not throw, and must still return at least AccountHeader
        System.assert(items.size() >= 1, 'Sanitizer should fall back to no filter, returning header');
        System.assertEquals('AccountHeader', items[0].type, 'AccountHeader must be present');
    }

    // ─────────────────────────────────────────────────────────────
    // CASE PAGINATION TESTS
    // ─────────────────────────────────────────────────────────────

    /**
     * @description  First page must return exactly 10 Case items.
     */
    @isTest
    static void testGetCases_firstPage() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        AccountTimelineController.CasePage page =
            AccountTimelineController.getCases(acc.Id, 10, 0, 'ALL', 'Subject,Status');
        Test.stopTest();

        System.assertEquals(10, page.items.size(), 'First page should contain 10 items');
        // 1 primary + 12 extra = 13 total
        System.assert(page.totalCount >= 13, 'Total count should include all Cases');
    }

    /**
     * @description  Second page must return the remaining Cases (13 total - 10 first page = 3).
     */
    @isTest
    static void testGetCases_secondPage() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        AccountTimelineController.CasePage page =
            AccountTimelineController.getCases(acc.Id, 10, 10, 'ALL', 'Subject,Status');
        Test.stopTest();

        System.assert(page.items.size() >= 3, 'Second page should have the remaining cases');
    }

    /**
     * @description  Each CaseItem must expose its nested activities list.
     *               The primary Case has one linked Task — it should appear
     *               in that Case's activities list.
     */
    @isTest
    static void testGetCases_nestedActivities() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        AccountTimelineController.CasePage page =
            AccountTimelineController.getCases(acc.Id, 10, 0, 'ALL', 'Subject,Status');
        Test.stopTest();

        // Find the primary Case in the results and check its nested activities
        Boolean foundCaseActivity = false;
        for (AccountTimelineController.CaseItem ci : page.items) {
            if (ci.activities != null && !ci.activities.isEmpty()) {
                foundCaseActivity = true;
                break;
            }
        }
        System.assert(foundCaseActivity, 'The primary Case should include nested activities');
    }

    // ─────────────────────────────────────────────────────────────
    // SUBTITLE ROWS TESTS
    // ─────────────────────────────────────────────────────────────

    /**
     * @description  subtitleRows must be populated when valid fields are requested.
     *               Subject and Status are always present on the test data Case.
     */
    @isTest
    static void testGetCases_subtitleRowsPopulated() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        AccountTimelineController.CasePage page =
            AccountTimelineController.getCases(acc.Id, 10, 0, 'ALL', 'Subject,Status');
        Test.stopTest();

        // Find the primary Case which has Subject = 'Primary Test Case' and Status = 'New'
        AccountTimelineController.CaseItem primary = null;
        for (AccountTimelineController.CaseItem ci : page.items) {
            if ('Primary Test Case'.equals(ci.subject)) {
                primary = ci;
                break;
            }
        }

        System.assertNotEquals(null, primary, 'Primary Case must be present in results');
        System.assertNotEquals(null, primary.subtitleRows, 'subtitleRows must not be null');
        System.assert(primary.subtitleRows.size() >= 2,
            'Expected at least Subject and Status subtitle rows, got: ' + primary.subtitleRows.size());

        // Verify labels and values
        Map<String, String> rowsByLabel = new Map<String, String>();
        for (AccountTimelineController.SubtitleRow row : primary.subtitleRows) {
            rowsByLabel.put(row.label, row.value);
        }
        System.assertEquals('Primary Test Case', rowsByLabel.get('Subject'), 'Subject row value mismatch');
        System.assertEquals('New',               rowsByLabel.get('Status'),  'Status row value mismatch');
    }

    /**
     * @description  Passing an invalid / non-existent field name must not throw —
     *               it should be silently skipped and valid fields still returned.
     */
    @isTest
    static void testGetCases_invalidFieldIgnored() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        AccountTimelineController.CasePage page =
            AccountTimelineController.getCases(acc.Id, 10, 0, 'ALL', 'Subject,NonExistentField__xyz,Status');
        Test.stopTest();

        System.assertNotEquals(null, page, 'Result must not be null even with an invalid field');
        System.assert(page.items.size() > 0, 'Items should still be returned');

        // The invalid field is skipped — Subject and Status rows must still appear
        AccountTimelineController.CaseItem first = page.items[0];
        System.assertNotEquals(null, first.subtitleRows, 'subtitleRows must not be null');

        Boolean hasSubject = false;
        for (AccountTimelineController.SubtitleRow row : first.subtitleRows) {
            if (row.label == 'Subject') hasSubject = true;
        }
        System.assert(hasSubject, 'Subject row must still be present despite invalid field in list');
    }
}
