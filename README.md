# accountTimeline

A lightweight Salesforce Lightning Web Component that surfaces a true **360° view of the customer** directly on the Case record page — the parent Account's full activity history **and** every sibling Case under that Account, in one configurable chronological view.

> **The perspective fix.** Most Salesforce timeline packages assume you're standing on the Account, looking down at its Cases. But service agents live on the **Case**, not the Account. `accountTimeline` flips that — from any Case, see the entire customer story without opening four tabs.

[![Salesforce](https://img.shields.io/badge/Salesforce-API_v59.0-00A1E0?logo=salesforce&logoColor=white)](https://developer.salesforce.com/docs/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/Version-1.0-blue)](https://github.com/ishanovarazmyrat-code/accountTimeLine)

---

## What you get

From a single Case record page, the component shows:

- 📌 **Account Activities** — Tasks, Events, and Emails linked to the parent Account
- 📌 **Case History** — every sibling Case under the same Account, with each Case's own nested Tasks, Events, and Emails
- 🔀 **Optional mixed mode** — both lists merged into one unified, time-ordered feed
- 🔎 **Drill into any Case** for subject, status, description, and nested activities — without leaving the page
- 📅 **Date filtering** — All Time / Today / This Week / This Month / Last Month / Last 30 Days / Last 90 Days / This Year
- 📄 **Pagination** for the Case list (default 10 per page, "Load More" button)

---

## App Builder configuration

Drop the component on a Case Lightning Record Page and configure these properties without code:

| Property | Type | Default | Description |
|---|---|---|---|
| **Hide Account Activities** | Boolean | `false` | Hide the Account Activities section |
| **Hide Case History** | Boolean | `false` | Hide the Case History section |
| **Mix Activities and Cases** | Boolean | `false` | Merge both into one chronological feed |
| **Case Row Subtitle Fields** | String | `Subject,Status` | Comma-separated Case API field names to display as subtitles |

> **`caseSubtitleFields`** accepts both standard fields (`Subject`, `Status`, `Type`, `Priority`, `Owner.Name`) and **custom fields** (`Category_1__c`, etc.). Field labels resolve from metadata automatically — no code changes needed when you add a new field to your Case object.

---

## Installation

### Option 1 — SFDX deploy (recommended)

```bash
git clone https://github.com/ishanovarazmyrat-code/accountTimeLine.git
cd accountTimeLine
sf project deploy start --target-org <your-org-alias>
```

### Option 2 — Manual deploy via VS Code

1. Open the project in VS Code with the Salesforce Extension Pack
2. Authorize your org: `SFDX: Authorize an Org`
3. Right-click `force-app/main/default` → `SFDX: Deploy Source to Org`

---

## Usage

1. Open a Case record page in Lightning Experience
2. Click the gear icon (top right) → **Edit Page**
3. From the Components panel (left), find `accountTimeline` under Custom Components
4. Drag it onto the page (right column works best)
5. Configure the four properties in the right-hand panel
6. **Save** and **Activate** the page



---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Lightning Record Page (Case)                       │
│  └── accountTimeline LWC                            │
│      ├── @wire getAccountTimeline(caseId, filter)   │
│      │   └── Apex → AccountHeader + Tasks/Events/Emails on Account
│      └── imperative getCases(accountId, page, …)    │
│          └── Apex → Cases + nested Tasks/Events/Emails per Case
└─────────────────────────────────────────────────────┘
```

### Files

```
accountTimeLine/
├── README.md
├── LICENSE
├── .gitignore
├── sfdx-project.json
└── force-app/main/default/
    ├── classes/
    │   ├── AccountTimelineController.cls         # Server-side controller
    │   ├── AccountTimelineController.cls-meta.xml
    │   ├── AccountTimelineControllerTest.cls     # Test class (≥85% coverage)
    │   └── AccountTimelineControllerTest.cls-meta.xml
    └── lwc/accountTimeline/
        ├── accountTimeline.js                    # Controller + reactivity
        ├── accountTimeline.html                  # SLDS template
        ├── accountTimeline.css                   # Scoped styles
        └── accountTimeline.js-meta.xml           # App Builder metadata
```

---

## Security

- ✅ Apex class declared `with sharing` — respects record-level access
- ✅ SOQL date literals validated against a server-side **whitelist** (`ALLOWED_DATE_LITERALS`) to prevent SOQL injection through string concatenation
- ✅ `caseSubtitleFields` validated against `Schema.SObjectType.Case.fields.getMap()` — invalid fields are silently dropped, never injected into a query
- ✅ Field labels resolved through `getDescribe().getLabel()` — supports localized orgs
- ⚠️ FLS not explicitly stripped — relies on `with sharing` and standard object permissions. If you need stricter FLS enforcement, wrap reads with `Security.stripInaccessible()`.

---

## Test coverage

The included test class covers:

1. Happy path — AccountHeader + Task + Event are returned
2. Date filter — `THIS_MONTH` returns today's records
3. No Account — Case with no `AccountId` returns an empty list
4. Invalid date filter — sanitizer falls back to no-filter without throwing
5. `getCases` first page — returns 10 items
6. `getCases` second page — returns remaining items
7. Nested activities — Cases expose linked Tasks
8. Subtitle rows — populated correctly for valid fields
9. Invalid field name — silently ignored, valid fields still returned

Run with:

```bash
sf apex run test --tests AccountTimelineControllerTest --code-coverage --result-format human
```

Expected coverage: **≥ 100%**.

---

## Related work

This component was built to solve a specific gap not covered by existing tools:

- [**Timeline LWC** by Dave Norris (deejay-hub)](https://github.com/deejay-hub/timeline-lwc) — excellent open-source timeline, designed for the **parent perspective** (Account → Cases). We use and respect it. Different goal.
- **Salesforce Case Timeline** (Spring '26) — native feature showing major events of the *current* Case only. No parent Account activities, no sibling Cases.
- **Standard Related Lists / Dynamic Related Lists** — can surface a parent's related Cases on the child page, but as flat lists — no chronological merge, no nested Activities, no drill-in.

`accountTimeline` fills the missing piece: from a Case, see the parent Account's full activity **and** every sibling Case in one configurable chronological view.

---

## Roadmap

Ideas welcome — open an issue or PR.

- [ ] FFLIB Selector pattern refactor for enterprise codebases
- [ ] Optional `Security.stripInaccessible()` wrapper for strict FLS orgs
- [ ] Custom record types as filter chips
- [ ] Inline activity creation (compose Task / Email from the timeline)
- [ ] Export-to-CSV from the unified mixed-mode view

---

## Contributing

Pull requests welcome! Please:

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/your-feature`)
3. Run all tests (`sf apex run test --code-coverage`)
4. Open a PR with a clear description and screenshot

---

## License

MIT — see [LICENSE](LICENSE).

---

## Author

Built by **Araz** at **Bold Generic Solutions**.

If this saved your team some clicks, a ⭐ on the repo would mean a lot.
