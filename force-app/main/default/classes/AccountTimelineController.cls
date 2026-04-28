/**
 * @description  Apex controller for the Account Activity Timeline LWC.
 *               Retrieves Tasks, Events, EmailMessages, and Cases linked to the
 *               parent Account of a given Case record.
 *
 *               Returns:
 *               1. An AccountHeader item (index 0) with Account Id and Name.
 *               2. Activity items (Task, Event, Email) filtered by an optional
 *                  date range string (SOQL date literal, e.g. THIS_MONTH).
 *               3. Cases related to the Account, paginated via offset + pageSize.
 *                  Case items expose: title (CaseNumber), description (Description),
 *                  status (Status) — Subject is part of the title field.
 *
 * @author       Araz
 * @version      1.0
 * @date         2026-04-28
 */
public with sharing class AccountTimelineController {

    // ─────────────────────────────────────────────────────────────
    // SECURITY — allow-list of SOQL date literals
    // ─────────────────────────────────────────────────────────────

    /**
     * @description  Whitelist of accepted SOQL date literals.
     *               Any incoming dateFilter value not in this set is treated as 'ALL'
     *               (no filter), preventing SOQL injection through string concatenation.
     */
    private static final Set<String> ALLOWED_DATE_LITERALS = new Set<String>{
        'TODAY', 'YESTERDAY',
        'THIS_WEEK', 'LAST_WEEK',
        'THIS_MONTH', 'LAST_MONTH',
        'LAST_N_DAYS:30', 'LAST_N_DAYS:90',
        'THIS_YEAR', 'LAST_YEAR'
    };

    /**
     * @description  Validates the incoming dateFilter against the whitelist.
     *               Returns null when the filter should be ignored (no WHERE clause).
     */
    private static String sanitizeDateFilter(String dateFilter) {
        if (String.isBlank(dateFilter) || dateFilter == 'ALL') return null;
        return ALLOWED_DATE_LITERALS.contains(dateFilter) ? dateFilter : null;
    }

    // ─────────────────────────────────────────────────────────────
    // PUBLIC METHODS
    // ─────────────────────────────────────────────────────────────

    /**
     * @description  Returns activity items and the AccountHeader for the
     *               parent Account of the given Case.
     *               Optionally filters by a SOQL date literal (e.g. THIS_MONTH).
     *
     * @param        caseId      Id of the Case record currently being viewed
     * @param        dateFilter  SOQL date literal string or 'ALL' for no filter
     * @return       List<TimelineItem> AccountHeader first, then sorted activity items
     */
    @AuraEnabled(cacheable=true)
    public static List<TimelineItem> getAccountTimeline(Id caseId, String dateFilter) {

        // Resolve the parent Account from the Case
        Case c = [
            SELECT AccountId, Account.Name
            FROM   Case
            WHERE  Id = :caseId
            LIMIT  1
        ];

        // Guard: no parent Account
        if (c.AccountId == null) {
            return new List<TimelineItem>();
        }

        Id accountId = c.AccountId;
        List<TimelineItem> items = new List<TimelineItem>();

        // ── AccountHeader ────────────────────────────────────────
        TimelineItem header   = new TimelineItem();
        header.id             = c.AccountId;
        header.title          = c.Account.Name;
        header.type           = 'AccountHeader';
        header.dateValue      = '';
        header.icon           = 'standard:account';
        header.iconBackground = '#0070d2';
        items.add(header);

        String safeFilter   = sanitizeDateFilter(dateFilter);
        Boolean applyFilter = safeFilter != null;

        // ── Tasks ────────────────────────────────────────────────
        String taskQuery = 'SELECT Id, Subject, Status, Priority, ' +
                           'ActivityDate, Description, Owner.Name ' +
                           'FROM Task WHERE WhatId = :accountId';
        if (applyFilter) taskQuery += ' AND ActivityDate = ' + safeFilter;
        taskQuery += ' ORDER BY ActivityDate DESC NULLS LAST LIMIT 200';

        for (Task t : Database.query(taskQuery)) {
            TimelineItem item   = new TimelineItem();
            item.id             = t.Id;
            item.title          = t.Subject != null ? t.Subject : '(No Subject)';
            item.type           = 'Task';
            item.dateValue      = t.ActivityDate != null ? String.valueOf(t.ActivityDate) : '';
            item.description    = t.Description;
            item.owner          = t.Owner.Name;
            item.status         = t.Status;
            item.icon           = 'standard:task';
            item.iconBackground = '#4BC076';
            items.add(item);
        }

        // ── Events ───────────────────────────────────────────────
        String eventQuery = 'SELECT Id, Subject, StartDateTime, ' +
                            'Description, Owner.Name, Location ' +
                            'FROM Event WHERE WhatId = :accountId';
        if (applyFilter) eventQuery += ' AND StartDateTime = ' + safeFilter;
        eventQuery += ' ORDER BY StartDateTime DESC NULLS LAST LIMIT 200';

        for (Event e : Database.query(eventQuery)) {
            TimelineItem item   = new TimelineItem();
            item.id             = e.Id;
            item.title          = e.Subject != null ? e.Subject : '(No Subject)';
            item.type           = 'Event';
            item.dateValue      = e.StartDateTime != null ? String.valueOf(e.StartDateTime) : '';
            item.description    = e.Description;
            item.owner          = e.Owner.Name;
            item.status         = e.Location;
            item.icon           = 'standard:event';
            item.iconBackground = '#EB7092';
            items.add(item);
        }

        // ── EmailMessages ────────────────────────────────────────
        // Guard: RelatedToId does not exist in all orgs
        Map<String, Schema.SObjectField> emailFieldMap =
            Schema.SObjectType.EmailMessage.fields.getMap();

        if (emailFieldMap.containsKey('relatedtoid')) {
            String emailQuery = 'SELECT Id, Subject, TextBody, ' +
                                'MessageDate, FromAddress, ToAddress ' +
                                'FROM EmailMessage WHERE RelatedToId = :accountId';
            if (applyFilter) emailQuery += ' AND MessageDate = ' + safeFilter;
            emailQuery += ' ORDER BY MessageDate DESC NULLS LAST LIMIT 200';

            for (EmailMessage em : Database.query(emailQuery)) {
                TimelineItem item   = new TimelineItem();
                item.id             = em.Id;
                item.title          = em.Subject != null ? em.Subject : '(No Subject)';
                item.type           = 'Email';
                item.dateValue      = em.MessageDate != null ? String.valueOf(em.MessageDate) : '';
                item.description    = em.TextBody;
                item.owner          = em.FromAddress;
                item.status         = em.ToAddress;
                item.icon           = 'standard:email';
                item.iconBackground = '#6BC8E2';
                items.add(item);
            }
        }

        // Sort activity items (skip index 0 which is AccountHeader)
        List<TimelineItem> activityItems = new List<TimelineItem>();
        for (Integer i = 1; i < items.size(); i++) {
            activityItems.add(items[i]);
        }
        activityItems.sort();

        List<TimelineItem> result = new List<TimelineItem>{ items[0] };
        result.addAll(activityItems);
        return result;
    }

    /**
     * @description  Returns a paginated page of Cases related to the given Account.
     *
     * @param        accountId    Id of the Account whose Cases to retrieve
     * @param        pageSize     Number of records per page (default 10)
     * @param        offset       Number of records to skip for pagination
     * @param        dateFilter   SOQL date literal string or 'ALL' for no filter
     * @param        extraFields  Comma-separated Case API field names to show as
     *                            subtitle rows (e.g. "Subject,Status,Category_1__c").
     *                            Validated against Case schema to prevent SOQL injection.
     * @return       CasePage     Wrapper with items list and total count
     */
    @AuraEnabled(cacheable=false)
    public static CasePage getCases(Id accountId, Integer pageSize, Integer offset, String dateFilter, String extraFields) {

        Integer size = (pageSize != null && pageSize > 0) ? pageSize : 10;
        Integer skip = (offset   != null && offset   > 0) ? offset   : 0;

        String safeFilter   = sanitizeDateFilter(dateFilter);
        Boolean applyFilter = safeFilter != null;

        // ── Resolve and validate subtitle fields ─────────────────
        Set<String> baseFieldsLower = new Set<String>{
            'id', 'casenumber', 'subject', 'status', 'type', 'priority',
            'description', 'createddate', 'owner.name'
        };

        Map<String, Schema.SObjectField> caseFieldMap =
            Schema.SObjectType.Case.fields.getMap();

        List<String> extraFieldList   = new List<String>();
        List<String> subtitleApiNames = new List<String>();

        if (String.isNotBlank(extraFields)) {
            for (String raw : extraFields.split(',')) {
                String apiName = raw.trim();
                if (String.isBlank(apiName)) continue;

                String apiLower = apiName.toLowerCase();

                if (caseFieldMap.containsKey(apiLower)) {
                    // Direct match
                    String canonicalName = caseFieldMap.get(apiLower).getDescribe().getName();
                    subtitleApiNames.add(canonicalName);
                    if (!baseFieldsLower.contains(apiLower)) {
                        extraFieldList.add(canonicalName);
                    }
                } else {
                    // Fuzzy fallback: handles missing namespace prefix
                    String foundKey = null;
                    for (String k : caseFieldMap.keySet()) {
                        if (k.endsWith(apiLower)) {
                            foundKey = k;
                            break;
                        }
                    }
                    if (foundKey != null) {
                        String canonicalName = caseFieldMap.get(foundKey).getDescribe().getName();
                        subtitleApiNames.add(canonicalName);
                        if (!baseFieldsLower.contains(foundKey)) {
                            extraFieldList.add(canonicalName);
                        }
                    }
                }
            }
        }

        // ── Count + paginated Case query ─────────────────────────
        String countQuery = 'SELECT COUNT() FROM Case WHERE AccountId = :accountId';
        if (applyFilter) countQuery += ' AND CreatedDate = ' + safeFilter;
        Integer total = Database.countQuery(countQuery);

        String selectFields = 'Id, CaseNumber, Subject, Status, Type, Priority, Description, CreatedDate, Owner.Name';
        if (!extraFieldList.isEmpty()) {
            selectFields += ', ' + String.join(extraFieldList, ', ');
        }

        String caseQuery = 'SELECT ' + selectFields + ' FROM Case WHERE AccountId = :accountId';
        if (applyFilter) caseQuery += ' AND CreatedDate = ' + safeFilter;
        caseQuery += ' ORDER BY CreatedDate DESC LIMIT :size OFFSET :skip';

        List<SObject> cases = Database.query(caseQuery);

        // Collect Case Ids for child activity queries
        Set<Id> caseIds = new Set<Id>();
        for (SObject so : cases) { caseIds.add((Id) so.get('Id')); }

        // ── Tasks linked to Cases ────────────────────────────────
        Map<Id, List<TimelineItem>> tasksByCaseId = new Map<Id, List<TimelineItem>>();
        for (Task t : [
            SELECT Id, Subject, Status, ActivityDate, Description, Owner.Name, WhatId
            FROM   Task
            WHERE  WhatId IN :caseIds
            ORDER BY ActivityDate DESC NULLS LAST
        ]) {
            if (!tasksByCaseId.containsKey(t.WhatId)) tasksByCaseId.put(t.WhatId, new List<TimelineItem>());
            TimelineItem item   = new TimelineItem();
            item.id             = t.Id;
            item.title          = t.Subject != null ? t.Subject : '(No Subject)';
            item.type           = 'Task';
            item.dateValue      = t.ActivityDate != null ? String.valueOf(t.ActivityDate) : '';
            item.description    = t.Description;
            item.owner          = t.Owner.Name;
            item.status         = t.Status;
            item.icon           = 'standard:task';
            item.iconBackground = '#4BC076';
            tasksByCaseId.get(t.WhatId).add(item);
        }

        // ── Events linked to Cases ───────────────────────────────
        Map<Id, List<TimelineItem>> eventsByCaseId = new Map<Id, List<TimelineItem>>();
        for (Event e : [
            SELECT Id, Subject, StartDateTime, Description, Owner.Name, WhatId
            FROM   Event
            WHERE  WhatId IN :caseIds
            ORDER BY StartDateTime DESC NULLS LAST
        ]) {
            if (!eventsByCaseId.containsKey(e.WhatId)) eventsByCaseId.put(e.WhatId, new List<TimelineItem>());
            TimelineItem item   = new TimelineItem();
            item.id             = e.Id;
            item.title          = e.Subject != null ? e.Subject : '(No Subject)';
            item.type           = 'Event';
            item.dateValue      = e.StartDateTime != null ? String.valueOf(e.StartDateTime) : '';
            item.description    = e.Description;
            item.owner          = e.Owner.Name;
            item.icon           = 'standard:event';
            item.iconBackground = '#EB7092';
            eventsByCaseId.get(e.WhatId).add(item);
        }

        // ── EmailMessages linked to Cases ────────────────────────
        // Guard: ParentId does not exist in all orgs
        Map<Id, List<TimelineItem>> emailsByCaseId = new Map<Id, List<TimelineItem>>();
        Map<String, Schema.SObjectField> emailFieldMap =
            Schema.SObjectType.EmailMessage.fields.getMap();

        if (emailFieldMap.containsKey('parentid')) {
            for (EmailMessage em : [
                SELECT Id, Subject, TextBody, MessageDate, FromAddress, ToAddress, ParentId
                FROM   EmailMessage
                WHERE  ParentId IN :caseIds
                ORDER BY MessageDate DESC NULLS LAST
            ]) {
                if (!emailsByCaseId.containsKey(em.ParentId)) emailsByCaseId.put(em.ParentId, new List<TimelineItem>());
                TimelineItem item   = new TimelineItem();
                item.id             = em.Id;
                item.title          = em.Subject != null ? em.Subject : '(No Subject)';
                item.type           = 'Email';
                item.dateValue      = em.MessageDate != null ? String.valueOf(em.MessageDate) : '';
                item.description    = em.TextBody;
                item.owner          = em.FromAddress;
                item.status         = em.ToAddress;
                item.icon           = 'standard:email';
                item.iconBackground = '#6BC8E2';
                emailsByCaseId.get(em.ParentId).add(item);
            }
        }

        // ── Base field label map ─────────────────────────────────
        Map<String, String> baseLabelMap = new Map<String, String>{
            'subject'     => 'Subject',
            'status'      => 'Status',
            'type'        => 'Category',
            'priority'    => 'Priority',
            'owner.name'  => 'Owner',
            'casenumber'  => 'Case Number',
            'description' => 'Description'
        };

        // ── Build CaseItems ──────────────────────────────────────
        List<CaseItem> caseItems = new List<CaseItem>();
        for (SObject so : cases) {
            CaseItem ci       = new CaseItem();
            ci.id             = (String) so.get('Id');
            ci.caseNumber     = (String) so.get('CaseNumber');
            ci.subject        = (String) so.get('Subject');
            ci.status         = (String) so.get('Status');
            ci.category       = (String) so.get('Type');
            ci.priority       = (String) so.get('Priority');
            ci.description    = (String) so.get('Description');
            ci.owner          = (String) ((SObject) so.getSObject('Owner')).get('Name');
            ci.dateValue      = so.get('CreatedDate') != null ? String.valueOf(so.get('CreatedDate')) : '';
            ci.iconBackground = '#F2CF5B';

            // Build subtitle rows from requested fields
            List<SubtitleRow> rows = new List<SubtitleRow>();
            for (String apiName : subtitleApiNames) {
                String apiLower = apiName.toLowerCase();
                String label;
                String val;

                if (baseLabelMap.containsKey(apiLower)) {
                    label = baseLabelMap.get(apiLower);
                    Object rawVal = so.get(apiLower);
                    val = rawVal != null ? String.valueOf(rawVal) : null;
                } else {
                    Schema.SObjectField fld = caseFieldMap.get(apiLower);
                    if (fld != null) {
                        String canonicalName = fld.getDescribe().getName();
                        label = fld.getDescribe().getLabel();
                        Object rawVal = so.get(canonicalName);
                        val = rawVal != null ? String.valueOf(rawVal) : null;
                    } else {
                        label = apiName;
                        val   = null;
                    }
                }

                if (String.isNotBlank(val)) {
                    SubtitleRow row = new SubtitleRow();
                    row.apiName = apiName;
                    row.label   = label;
                    row.value   = val;
                    rows.add(row);
                }
            }
            ci.subtitleRows = rows;

            List<TimelineItem> caseActivities = new List<TimelineItem>();
            Id caseId = (Id) so.get('Id');
            if (tasksByCaseId.containsKey(caseId))  caseActivities.addAll(tasksByCaseId.get(caseId));
            if (eventsByCaseId.containsKey(caseId)) caseActivities.addAll(eventsByCaseId.get(caseId));
            if (emailsByCaseId.containsKey(caseId)) caseActivities.addAll(emailsByCaseId.get(caseId));
            caseActivities.sort();
            ci.activities = caseActivities;

            caseItems.add(ci);
        }

        CasePage page   = new CasePage();
        page.items      = caseItems;
        page.totalCount = total;
        return page;
    }


    // ─────────────────────────────────────────────────────────────
    // INNER CLASSES
    // ─────────────────────────────────────────────────────────────

    public class TimelineItem implements Comparable {
        @AuraEnabled public String id;
        @AuraEnabled public String title;
        @AuraEnabled public String type;
        @AuraEnabled public String dateValue;
        @AuraEnabled public String description;
        @AuraEnabled public String subject;
        @AuraEnabled public String owner;
        @AuraEnabled public String status;
        @AuraEnabled public String icon;
        @AuraEnabled public String iconBackground;

        public Integer compareTo(Object other) {
            TimelineItem o = (TimelineItem) other;
            if (String.isBlank(this.dateValue) && String.isBlank(o.dateValue)) return 0;
            if (String.isBlank(this.dateValue)) return 1;
            if (String.isBlank(o.dateValue))    return -1;
            if (this.dateValue > o.dateValue)   return -1;
            if (this.dateValue < o.dateValue)   return 1;
            return 0;
        }
    }

    public class CaseItem {
        @AuraEnabled public String id;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public String category;
        @AuraEnabled public String priority;
        @AuraEnabled public String description;
        @AuraEnabled public String owner;
        @AuraEnabled public String dateValue;
        @AuraEnabled public String iconBackground;
        @AuraEnabled public List<SubtitleRow> subtitleRows;
        @AuraEnabled public List<TimelineItem> activities;
    }

    public class SubtitleRow {
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    public class CasePage {
        @AuraEnabled public List<CaseItem> items;
        @AuraEnabled public Integer totalCount;
    }
}
