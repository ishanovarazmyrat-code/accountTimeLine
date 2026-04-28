/**
 * @description  Account Activity Timeline — JavaScript Controller v1.0
 *
 *               From a Case record page, surfaces:
 *               - The parent Account's full activity history
 *                 (Tasks, Events, Emails) — "Account Activities" section
 *               - Every sibling Case under the same Account, with its own
 *                 nested Tasks, Events, and Emails — "Case History" section
 *               - An optional unified chronological feed (mixSections mode)
 *
 *               Date display uses the standard Salesforce Activity component
 *               format: "5:59 AM | Today" / "9:21 PM | Yesterday".
 *
 * @author       Araz
 * @version      1.0
 * @date         2026-04-28
 */

import { LightningElement, api, wire, track } from 'lwc';
import getAccountTimeline from '@salesforce/apex/AccountTimelineController.getAccountTimeline';
import getCases           from '@salesforce/apex/AccountTimelineController.getCases';

const CASE_PAGE_SIZE = 10;

export default class AccountTimeline extends LightningElement {

    // ─────────────────────────────────────────────────────────────
    // APP BUILDER CONFIGURABLE PROPERTIES
    // ─────────────────────────────────────────────────────────────

    /**
     * @description  Hide the Account Activities section (Tasks, Events, Emails).
     *               Configurable in App Builder. Default: false (section is visible).
     *               LWC Boolean @api properties cannot be initialized to true,
     *               so this is an "opt-out" flag — set to true to hide the section.
     */
    @api hideActivities = false;

    /**
     * @description  Hide the Case History section with nested Case activities.
     *               Configurable in App Builder. Default: false (section is visible).
     *               Set to true in App Builder to hide the Case History section.
     */
    @api hideCases = false;

    @track isMixedMode = false;

    /**
     * @description  When true, merges Activities and Cases into a single
     *               chronological "All Activity" list instead of two sections.
     *               Configurable in App Builder. Default: false.
     */
    @api
    get mixSections() {
        return this.isMixedMode;
    }
    set mixSections(value) {
        this.isMixedMode = value === true || String(value).toLowerCase() === 'true';
    }

    /**
     * @description  Comma-separated list of Case fields to show as subtitle lines
     *               beneath the Case Number. Configurable in App Builder.
     *               Standard fields: Subject, Status, Type, Priority, Owner.Name
     *               Custom fields:   any API name (e.g. Category_1__c).
     *               Default: "Subject,Status"
     */
    @api caseSubtitleFields = 'Subject,Status';

    // ─────────────────────────────────────────────────────────────
    // INTERNAL PROPERTIES
    // ─────────────────────────────────────────────────────────────

    /** Id of the current Case record — injected by the Lightning record page */
    @api recordId;

    /** Enriched activity items (Task, Event, Email) for the Activities section */
    @track items = [];

    /** Enriched Case items for the Case History section */
    @track caseItems = [];

    /** Account name shown as a link in the card title */
    accountName = '';

    /** Lightning URL to the Account record */
    accountUrl  = '';

    /** Id of the parent Account — used for the getCases() imperative call */
    accountId   = '';

    /** True while the activity @wire is in flight */
    isLoading = true;

    /** Error message when the activity @wire fails */
    errorMessage = '';

    /** Currently selected SOQL date filter */
    selectedDateFilter = 'ALL';

    /** Whether the Account Activities / All Activity section is expanded */
    activitiesSectionExpanded = true;

    /** Whether the Case History section is expanded */
    casesSectionExpanded = true;

    /** True while loading more Cases imperatively */
    casesLoading = false;

    /** Total Case count for the Load More label */
    caseTotalCount = 0;

    /** Current pagination offset for Cases */
    caseOffset = 0;

    // ─────────────────────────────────────────────────────────────
    // DATE FILTER OPTIONS
    // ─────────────────────────────────────────────────────────────

    /**
     * @description  Options for the date range combobox.
     *               Values are SOQL date literals passed directly to Apex,
     *               where they are validated against a server-side whitelist.
     */
    get dateFilterOptions() {
        return [
            { label: 'All Time',     value: 'ALL'            },
            { label: 'Today',        value: 'TODAY'          },
            { label: 'This Week',    value: 'THIS_WEEK'      },
            { label: 'This Month',   value: 'THIS_MONTH'     },
            { label: 'Last Month',   value: 'LAST_MONTH'     },
            { label: 'Last 30 Days', value: 'LAST_N_DAYS:30' },
            { label: 'Last 90 Days', value: 'LAST_N_DAYS:90' },
            { label: 'This Year',    value: 'THIS_YEAR'      },
        ];
    }

    // ─────────────────────────────────────────────────────────────
    // WIRE — activity timeline
    // ─────────────────────────────────────────────────────────────

    /**
     * @description  Fetches activity items whenever recordId or selectedDateFilter
     *               changes. Extracts the AccountHeader item for the title link,
     *               then enriches the remaining items for the flat activity list.
     */
    @wire(getAccountTimeline, { caseId: '$recordId', dateFilter: '$selectedDateFilter' })
    wiredTimeline({ data, error }) {
        this.isLoading = false;

        if (data) {
            // First item is always AccountHeader injected by Apex
            const header = data.find(i => i.type === 'AccountHeader');
            if (header) {
                this.accountName = header.title;
                this.accountUrl  = `/lightning/r/${header.id}/view`;

                // Trigger Case loading only once (when accountId is first resolved)
                if (!this.accountId) {
                    this.accountId = header.id;
                    this.loadCases(true);
                }
            }

            // Build enriched activity list from all non-header items
            this.items = data
                .filter(i => i.type !== 'AccountHeader')
                .map(item => this.enrichActivityItem(item));

            this.errorMessage = '';
        } else if (error) {
            this.errorMessage = (error.body && error.body.message)
                ? error.body.message
                : 'An unexpected error occurred while loading the timeline.';
            this.items       = [];
            this.accountName = '';
            this.accountUrl  = '';
        }
    }

    // ─────────────────────────────────────────────────────────────
    // COMPUTED GETTERS
    // ─────────────────────────────────────────────────────────────

    /** True when there are activity items to render */
    get hasItems()  { return this.items.length > 0; }

    /** True when loaded with no error and no activity items */
    get isEmpty()   { return !this.isLoading && !this.errorMessage && this.items.length === 0; }

    /** True when an error message is present */
    get hasError()  { return !!this.errorMessage; }

    get showActivities() { return !this.hideActivities; }
    get showCases()      { return !this.hideCases; }

    /** True when no Cases are loaded and loading is complete */
    get noCases()   { return !this.casesLoading && this.caseItems.length === 0; }

    /** True when there are more Cases to load beyond the current page */
    get hasMoreCases() {
        return this.caseItems.length < this.caseTotalCount;
    }

    /** Load More button label */
    get loadMoreLabel() {
        const remaining = this.caseTotalCount - this.caseItems.length;
        return `Load More (${remaining} remaining)`;
    }

    /** Chevron icon for Account Activities / All Activity section toggle */
    get activitiesChevronIcon() {
        return this.activitiesSectionExpanded ? 'utility:chevrondown' : 'utility:chevronright';
    }

    /** Chevron icon for Case History section toggle */
    get caseChevronIcon() {
        return this.casesSectionExpanded ? 'utility:chevrondown' : 'utility:chevronright';
    }

    /**
     * @description  Merged chronological list for mixSections mode.
     *               Combines activity items and Case items, sorts by dateValue desc.
     */
    get mixedItems() {
        const all = [
            ...this.items,
            ...this.caseItems
        ];
        return all.sort((a, b) => {
            if (!a.dateValue) return 1;
            if (!b.dateValue) return -1;
            return b.dateValue > a.dateValue ? 1 : -1;
        });
    }

    /** Total count for the All Activity section badge */
    get mixedItemCount() {
        return this.mixedItems.length;
    }

    /** True when the mixed list is empty */
    get mixedIsEmpty() {
        return this.mixedItems.length === 0;
    }

    // ─────────────────────────────────────────────────────────────
    // EVENT HANDLERS
    // ─────────────────────────────────────────────────────────────

    /** Updates the date filter and re-triggers the @wire */
    handleDateFilterChange(event) {
        this.selectedDateFilter = event.detail.value;
        this.isLoading = true;
        // Reload cases with the new filter
        if (this.accountId) {
            this.loadCases(true);
        }
    }

    /** Forces a @wire refresh by briefly toggling the filter value */
    handleRefresh() {
        this.isLoading = true;
        const current = this.selectedDateFilter;
        this.selectedDateFilter = '__refresh__';
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { this.selectedDateFilter = current; }, 100);
    }

    /** Toggles the mix mode (mixed vs separate sections) */
    handleMixToggle(event) {
        this.isMixedMode = event.target.checked;
    }

    /** Toggles the Account Activities / All Activity section */
    toggleActivitiesSection() {
        this.activitiesSectionExpanded = !this.activitiesSectionExpanded;
    }

    /** Toggles the Case History section */
    toggleCaseSection() {
        this.casesSectionExpanded = !this.casesSectionExpanded;
    }

    /** Toggles expand/collapse of an activity item */
    toggleItem(event) {
        const id = event.currentTarget.dataset.id;
        this.items = this.items.map(item => {
            if (item.id !== id) return item;
            const isExpanded = !item.isExpanded;
            return { ...item, isExpanded, expandIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright' };
        });
    }

    /** Toggles expand/collapse of a Case item in the Case History section */
    toggleCaseItem(event) {
        const id = event.currentTarget.dataset.id;
        this.caseItems = this.caseItems.map(item => {
            if (item.id !== id) return item;
            const isExpanded = !item.isExpanded;
            return { ...item, isExpanded, expandIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright' };
        });
    }

    /** Toggles expand/collapse of an item in the mixed All Activity list */
    toggleMixedItem(event) {
        const id = event.currentTarget.dataset.id;

        // Try to update in items first
        let found = false;
        this.items = this.items.map(item => {
            if (item.id !== id) return item;
            found = true;
            const isExpanded = !item.isExpanded;
            return { ...item, isExpanded, expandIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright' };
        });

        // If not found in items, update in caseItems
        if (!found) {
            this.caseItems = this.caseItems.map(item => {
                if (item.id !== id) return item;
                const isExpanded = !item.isExpanded;
                return { ...item, isExpanded, expandIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright' };
            });
        }
    }

    /** Loads the next page of Cases */
    loadMoreCases() {
        this.caseOffset += CASE_PAGE_SIZE;
        this.loadCases(false);
    }

    /** Prevents link clicks from bubbling up to row toggle handlers */
    stopPropagation(event) {
        event.stopPropagation();
    }

    // ─────────────────────────────────────────────────────────────
    // PRIVATE HELPERS
    // ─────────────────────────────────────────────────────────────

    /**
     * @description  Imperatively calls getCases and appends or replaces caseItems.
     *               Also enriches the nested activities of each Case.
     *
     * @param        reset  If true, clears existing caseItems before loading
     */
    loadCases(reset) {
        if (!this.accountId) return;

        this.casesLoading = true;
        if (reset) {
            this.caseOffset = 0;
            this.caseItems  = [];
        }

        getCases({
            accountId:   this.accountId,
            pageSize:    CASE_PAGE_SIZE,
            offset:      this.caseOffset,
            dateFilter:  this.selectedDateFilter,
            extraFields: this.caseSubtitleFields || 'Subject,Status'
        })
        .then(result => {
            this.caseTotalCount = result.totalCount;

            // Enrich each CaseItem and its nested activities
            const newItems = result.items.map(ci => this.enrichCaseItem(ci));
            this.caseItems = reset ? newItems : [...this.caseItems, ...newItems];
        })
        .catch(err => {
            console.error('Error loading cases:', err);
            this.caseTotalCount = 0;
        })
        .finally(() => {
            this.casesLoading = false;
        });
    }

    /**
     * @description  Transforms a raw Apex TimelineItem (activity) into a UI object.
     *               Adds: recordUrl, exactDate, subtitle, iconStyle,
     *               isExpanded, expandIcon.
     *
     * @param        item  Raw TimelineItem from Apex
     * @returns      Enriched item for template binding
     */
    enrichActivityItem(item) {
        return {
            ...item,
            recordUrl:   `/lightning/r/${item.id}/view`,
            exactDate:   this.getExactDate(item.dateValue),
            subtitle:    this.getActivitySubtitle(item),
            isExpanded:  false,
            expandIcon:  'utility:chevronright',
            isCaseType:  false
        };
    }

    /**
     * @description  Transforms a raw Apex CaseItem into a UI object.
     *               Adds: recordUrl, exactDate, hasActivities,
     *               enriched nested activities, isExpanded, expandIcon.
     *
     * @param        ci  Raw CaseItem from Apex
     * @returns      Enriched case item for template binding
     */
    enrichCaseItem(ci) {
        const enrichedActivities = (ci.activities || []).map(act => ({
            ...act,
            recordUrl:  `/lightning/r/${act.id}/view`,
            exactDate:  this.getExactDate(act.dateValue)
        }));

        return {
            ...ci,
            title:         ci.title || ci.caseNumber,
            caseNumber:    ci.title || ci.caseNumber,
            icon:          'standard:case',
            recordUrl:     `/lightning/r/${ci.id}/view`,
            exactDate:     this.getExactDate(ci.dateValue),
            // subtitleRows is built by Apex from the extraFields param —
            // each entry is { apiName, label, value } ready for template rendering
            subtitleRows:  ci.subtitleRows || [],
            activities:    enrichedActivities,
            hasActivities: enrichedActivities.length > 0,
            isExpanded:    false,
            expandIcon:    'utility:chevronright',
            isCaseType:    true
        };
    }

    /**
     * @description  Formats an ISO date string as "5:59 AM | Today",
     *               "9:21 PM | Yesterday", or "9:21 PM | Apr 13, 2026".
     *               Matches the standard Salesforce Activity component style.
     *
     * @param        dateStr  ISO date or datetime string from Apex
     * @returns      Formatted string or empty string for blank input
     */
    getExactDate(dateStr) {
        if (!dateStr) return '';

        // Normalize Apex "yyyy-MM-dd HH:mm:ss" to standard UTC ISO string
        let isoStr = dateStr;
        if (isoStr.includes(' ') && !isoStr.includes('T')) {
            isoStr = isoStr.replace(' ', 'T') + 'Z';
        }

        const d = new Date(isoStr);
        if (isNaN(d.getTime())) return dateStr;

        const now       = new Date();
        const yesterday = new Date();
        yesterday.setDate(now.getDate() - 1);

        const isToday = d.toDateString() === now.toDateString();
        const isYest  = d.toDateString() === yesterday.toDateString();

        // Time portion: "5:59 AM"
        const timePart = d.toLocaleTimeString(undefined, {
            hour:   'numeric',
            minute: '2-digit',
            hour12: true
        });

        // Day label: Today / Yesterday / "Apr 13, 2026"
        let dayLabel;
        if (isToday) {
            dayLabel = 'Today';
        } else if (isYest) {
            dayLabel = 'Yesterday';
        } else {
            dayLabel = d.toLocaleDateString(undefined, {
                month: 'short',
                day:   'numeric',
                year:  'numeric'
            });
        }

        // Date-only fields will not have 'T' in the normalized isoStr
        const hasTime = isoStr.includes('T');
        return hasTime ? `${timePart} | ${dayLabel}` : dayLabel;
    }

    /**
     * @description  Returns a one-line subtitle for activity items,
     *               matching the standard Salesforce Activity component wording.
     *
     * @param        item  Raw or enriched TimelineItem
     * @returns      Subtitle string or null
     */
    getActivitySubtitle(item) {
        if (item.type === 'Event') return 'You had an event';
        if (item.type === 'Task')  return item.status ? `Status: ${item.status}` : null;
        if (item.type === 'Email') return item.owner  ? `You sent an email to ${item.owner}` : 'Email';
        return null;
    }
}
