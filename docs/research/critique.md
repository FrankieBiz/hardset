# COMPLETENESS CRITIC — what is missing from the whole body of work

Verified against primary sources today (2026-08-19). Ordered by how much each would change what gets built in the next 30 days.

---

## P0 — Would change the build immediately

### 1. The locked persistence stack **deletes the user's entire training history by default** when they sign out of or switch iCloud accounts. Nothing in any stream names this.

This is the worst defect in the plan and it is a two-line fix that nobody has written.

`SQLiteData.SyncEngine.handleAccountChange` — on `.signOut` or `.switchAccounts`, with no delegate set, calls `deleteLocalData()`:

```
// Sources/SQLiteData/CloudKit/SyncEngine.swift:1345-1371
case .signOut, .switchAccounts:
  guard let delegate
  else {
    await withErrorReporting(.sqliteDataCloudKitFailure) {
      try await deleteLocalData()      // :1363
    }
    return
  }
```

`deleteLocalData()` (`SyncEngine.swift:761`) iterates every synchronized table and executes `T.delete()` — a hard local DELETE of every row. And adopting the delegate protocol is **not** sufficient: the protocol extension's *default* implementation does the same thing (`Sources/SQLiteData/CloudKit/SyncEngineDelegate.swift:86-100`, `case .signOut, .switchAccounts: try await syncEngine.deleteLocalData()`). You must explicitly override the method to get non-destructive behavior. The library's own doc comment (`SyncEngineDelegate.swift:23-38`) shows the intended pattern — present an alert — but ships destruction as the default twice over.

Why it matters: the entire GTM story is "your training history lives in your iCloud, not on my server," and there is no server, so this is unrecoverable — no support restore, no logs, nothing. The corpus's soft-delete mitigation (`new-research.md:566`) does not help; this is a local hard DELETE that bypasses it. A user who signs out of iCloud to troubleshoot something loses two years of lifting.

Do this: implement `SyncEngineDelegate.syncEngine(_:accountChanged:)` in the **first commit** that creates the SyncEngine, override `.signOut`/`.switchAccounts` to stop syncing and leave local data intact behind a "this data belongs to the previous iCloud account — keep locally / erase" choice, and write a test asserting the delegate is installed. Verify the underlying API on device: `CKSyncEngine.Event.accountChange` with `ChangeType.signIn(currentUser:)` / `.signOut(previousUser:)` / `.switchAccounts(previousUser:currentUser:)` exists at `CloudKit.swiftinterface:1285-1290` in the local iOS 26.4 SDK.

### 2. App Review Guideline 5.1.3 forbids storing health data in iCloud. The plan is HealthKit reads + CloudKit as the only sync transport.

Verbatim, from Apple's own guidelines page (https://developer.apple.com/app-store/review/guidelines/):

> "Apps must not write false or inaccurate data into HealthKit or any other medical research or health management apps, and **may not store personal health information in iCloud**."

The corpus recommends replacing the readiness sliders with "HealthKit sleep, HRV, and resting-HR-vs-baseline" (`new-research.md` readiness rec) and locks CloudKit private database as the only sync transport. If any HealthKit-derived value — sleep hours, HRV, resting HR, body weight read from Health — lands in a synchronized GRDB table, it goes to iCloud. That is a straightforward 5.1.3 rejection, and it is the kind of thing a reviewer finds by reading your own App Privacy disclosure.

Do this, before the schema exists: partition the store into synced and unsynced tables, and put every HealthKit-derived value in an **unsynced, device-local** table. Read from HealthKit on each device rather than syncing the readings. Decide explicitly whether user-entered bodyweight (typed by the user, never read from Health) is in scope — that is your data, not HealthKit's, and syncing it is defensible; a value you read out of Health is not. Also note this is a second, independent argument for the readiness feature being v2, not v1.

### 3. Guideline 1.4.1 puts the "science-based" brand itself under heightened review scrutiny. Every stream treated the science layer as a marketing asset and nobody read it as a review risk.

Verbatim:

> "Medical apps that could provide inaccurate data or information... may be reviewed with greater scrutiny. **Apps must clearly disclose data and methodology to support accuracy claims relating to health measurements, and if the level of accuracy or methodology cannot be validated, we will reject your app.**"

The plan's flagship surfaces are MEV/MRV volume landmarks, an e1RM estimate, a 0–100 quality score whose own docstring concedes the number is not meaningful, and four uncited fatigue constants carrying 14–16% of it. Combined with 2.3.1(a) — "All new features, functionality, and product changes must be described with specificity in the Notes for Review section... generic descriptions will be rejected" — the review notes are a deliverable, not an afterthought.

Do this: the corpus's own best recommendation (invert `EvidenceLibrary` so every constant that moves a number carries a rating, enforced by a test) is now a **review-risk mitigation, not a credibility nicety** — promote it to P0. Write the App Review notes as a document that names each computed number, its formula, and its citation, and keep the in-app Methodology screen as the linked artifact. Avoid framing anything as a health *measurement*; frame it as a plan-structure heuristic. And never present e1RM to two decimals.

### 4. The schema is permanent from the day you ship, and three independent append-only rules stack. There is no "freeze the schema" gate anywhere in the plan.

Three constraints, all primary-sourced, all irreversible, none of them assembled in one place by any stream:

- **CloudKit production schema is additive-only.** Apple: "To prevent conflicts, you can't delete record types or fields that are already in production. Every time you deploy the development schema, its additive changes merge into the production schema." Also: "Apps in the App Store can access only the production environment. Before you publish your app, you must deploy the development schema to the production environment" — and deploying "doesn't copy any records." Resetting development after production exists reverts dev to the production state, not to empty. (https://developer.apple.com/documentation/CloudKit/deploying-an-icloud-container-s-schema)
- **SQLiteData disallows, forever: removing columns, renaming columns, renaming tables** (`Sources/SQLiteData/Documentation.docc/Articles/CloudKitSync.md:452-457`).
- **SQLiteData forbids `UNIQUE` constraints on anything but the primary key**, validated with a thrown error at `SyncEngine` construction (`CloudKitSync.md:263-266`); `ON DELETE RESTRICT` and `NO ACTION` also throw (`:250`); and these CloudKit field names are reserved and cannot be used as column names: `creationDate`, `creatorUserRecordID`, `etag`, `lastModifiedUserRecordID`, `modificationDate`, `modifiedByDevice`, `recordChangeTag`, `recordID`, `recordType` (`:290-300`). `creationDate` and `modificationDate` are exactly what a GRDB developer names those columns by reflex.

Why it matters: this collides head-on with the corpus's biggest open data question — curated-vs-crowd-sourced gym registry, and "how much of the exercise↔machine labeling are you willing to do by hand." Those decisions determine table shape. Get them wrong and you cannot rename the column, cannot drop it, cannot add the natural uniqueness constraint on `(gymID, machineName)` or on an exercise slug.

Do this in month one, before any UI: write the full v1 schema as one migration file, run the `SyncEngine` constructor against it in a test to prove it validates, grep every column name against the reserved list, replace every intended `UNIQUE` with either a primary key or an application-level dedupe, and only then deploy the development schema. Add a checklist item: "deploy CloudKit schema to production" is a release step that must happen *before* the first TestFlight external build, and it cannot be undone.

### 5. Nobody totalled the plan. The corpus's own effort tags sum to roughly two years of full-time solo work.

Rounds 2 and 3 carry 136 effort-tagged recommendations: 31 `[hours]`, 63 `[days]`, 39 `[weeks]`, 3 `[months]`. At a deliberately generous 4h / 2d / 1.5w / 1.5mo per item that is ≈106 calendar weeks full-time. Subtract the now-cut Watch app (7–9 weeks) and it is ≈97–99. The content pipeline alone is 260–340 hours plus $200–400 of art spend per this run's audit correction. Round 1 adds untagged prose recommendations on top.

No stream produced a total, and no stream asked the only question that matters: **how many hours a week does this person actually have?** At evenings-and-weekends (~15h/week) the untrimmed plan is roughly six years.

Do this: pick the v1 line explicitly and write down what is *out*. My proposed cut, defensible against the corpus's own findings: logger + local store + subscription + one honest per-machine progression chart + a curated ~120-exercise catalog. Out of v1: Foundation Models rendering, readiness/HealthKit, the composite quality score, crowd-sourced gym registry, mesocycle/deload prescription, per-gym day variants, Managed Background Assets, sharing, Uberon IDs, Chart3D. Sequence the content workstream *in parallel* from week one — the audit is right that it is 6–9 weeks of its own and that absorbing it as "seed data between features" is exactly how Elos got 404 exercises where 301 have no content.

---

## P1 — Month-one obligations with external lead times

### 6. EU DSA trader status will publish your home address on your App Store page. This has a document-verification lead time and it is not optional for a paid app.

Apple, verbatim (https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/):

> "Once verified, Apple will publish this information on your App Store product page when your app is distributed in any of the 27 territories of the EU."

For an individual (not an organization) enrollment the required fields are "Address or P.O. Box, Phone number, Email address." Verification requires two-factor validation of both the email and the phone, plus "a current document that verifies your business name and address," and if you display a P.O. Box, "documentation that reflects your association with this alternate address (for example, a receipt or bill)." Apps without trader status are removed from the EU App Store (https://developer.apple.com/news/?id=einwn76m).

Someone selling a $3.99/mo subscription is a trader. Do this in week one: decide between (a) a registered LLC/company so the published address is a business address, or (b) a P.O. Box plus a bill in your name at that box. Option (b) has a real queue at the post office and the bill has to exist. Start it now, not the week you submit.

### 7. There is no privacy manifest plan at all. Zero mentions across 2,232 lines of research. It has been mandatory since May 1, 2024.

The app needs its own `PrivacyInfo.xcprivacy` declaring `NSPrivacyAccessedAPITypes` for every required-reason API its code — **including its statically-linked SPM dependencies** — touches. Concretely for this stack: `NSPrivacyAccessedAPICategoryUserDefaults` / `CA92.1` (the house pattern mirrors prefs to UserDefaults), and `NSPrivacyAccessedAPICategoryFileTimestamp` / `C617.1` if anything stats the database file. I checked both dependencies at source:

- GRDB ships a manifest and declares **no** required-reason API use: `GRDB/PrivacyInfo.xcprivacy` on `master` contains `NSPrivacyAccessedAPITypes` as an empty array, `NSPrivacyTracking` false, `NSPrivacyCollectedDataTypes` empty.
- SQLiteData ships **no** privacy manifest at all (repo tree at `main`, 319 paths, zero matches for "privacy").
- Neither is on Apple's "SDKs that require a privacy manifest and signature" list (https://developer.apple.com/support/third-party-SDK-requirements/) — that list is Firebase/Flutter/RxSwift-shaped and includes `RealmSwift`, `FMDB` and `sqflite` but not GRDB.

Also mandatory regardless of backend: a privacy policy URL in App Store Connect **and** reachable in the app — 5.1.1(i), verbatim: "All apps must include a link to their privacy policy in the App Store Connect metadata field and within the app in an easily accessible manner," and it must "Explain its data retention/deletion policies and describe how a user can revoke consent and/or request deletion."

Do this: write the manifest in the first commit alongside the Xcode project; write the privacy policy and host it before the first TestFlight external build; and answer the App Privacy questionnaire deliberately — the moment you add any analytics or crash SDK, the answer changes and so does your controller status.

### 8. GDPR/CCPA: the no-backend design is a genuine advantage, and the plan is about to throw it away the first time it needs a crash report.

With no backend, personal data never reaches you: CloudKit private-database content is encrypted with keys available only on the user's trusted devices, and under Advanced Data Protection the keys stay in the account's iCloud Keychain. You are not processing it. Your real obligations reduce to: the privacy policy, the App Privacy disclosure, the DSA trader publication above, and an in-app "export and erase everything" affordance. Note 5.1.1(v) actively favors this design — "If your app doesn't include significant account-based features, let people use it without a login" — and the account-deletion requirement only bites "if your app supports account creation," which this app does not.

The unnamed gap is the flip side: **you will be blind.** `MetricKit` and Xcode Organizer appear zero times in the corpus. With no server and no analytics SDK, your only crash visibility is Xcode Organizer, populated solely by users who opted into sharing analytics with developers. You will not know your activation rate, your paywall conversion, or whether the logger's 1-tap budget holds in the field — which makes the audit's instruction to A/B the paywall trigger unexecutable.

Do this: decide *now*, as one decision, whether to add a privacy-respecting analytics/crash SDK (TelemetryDeck-class, EU-hosted, no IDFA) and accept that it makes you a controller with disclosure and consent obligations, or to ship blind and rely on Organizer plus an in-app "copy diagnostics" button. Do not drift into it after launch: adding an SDK post-launch changes your App Privacy answers and requires a new submission, and by then you have already lost the launch cohort's data.

### 9. What CI actually runs, on one Mac, has never been specified — and the highest-risk subsystems cannot be tested by it at all.

Concrete answer, verified: Xcode Cloud includes **25 compute hours/month** with Apple Developer Program membership, then $49.99/mo for 100 (https://developer.apple.com/xcode-cloud/); "running 5 tests of 12 minutes each equals one compute hour." That is the only CI a solo dev with one Mac should pay for.

But three subsystems are structurally untestable in CI: CloudKit sync needs remote notifications and therefore a physical device (SQLiteData's own docs and the CKSyncEngine write-up both say so); AlarmKit's alerting behavior, breakthrough of Focus/silent mode, and persistence across force-quit are device-only; Liquid Glass specular/motion rendering is documented as wrong in the Simulator. On top of that, this machine's own memory records that sandboxed `xcodebuild` cannot run tests locally (no pty), so there is no authoritative local run either.

Do this: (a) Xcode Cloud runs exactly two things on every push — the pure-engine Swift Testing suite and a `swift-snapshot-testing` matrix over the set row / keypad / rest bar across {light,dark} × {.large,.accessibility3,.accessibility5} × {reduceTransparency on/off}; (b) write a one-page **manual pre-release device checklist** covering account signout/switch, sync between two devices, AlarmKit fire with the app force-quit, Focus-mode breakthrough, and a 45-minute continuous session for thermals — and treat it as a release gate, not a nice-to-have; (c) acquire the second physical device in month one, per the corpus's own recommendation, because discovering this after the sync layer is written is the expensive ordering.

### 10. The SPM/module layout for a greenfield app does not exist anywhere. All 6 phases of module planning in round 1 are dead work.

Round 1's only module content is a Phase 1–6 plan for *extracting* `Intelligence/` from Elos into a shared package so two apps can share it (`prior-research.md:124-129`). The locked decisions kill it: Elos keeps its full workout section untouched, the new app is greenfield, reference code is read-only, no data import. Nothing replaced it. There is no `Package.swift`, no target graph, no decision on plain `.xcodeproj` vs workspace vs Tuist, no test-target plan.

Meanwhile one requirement *does* force the first module boundary before any UI exists: AlarmKit's `AlarmAttributes<Metadata>` conforms to `ActivityKit.ActivityAttributes` (`AlarmKit.swiftinterface:16`), so the countdown needs a **Widget Extension target**, and the `Metadata` type must compile into both the app and the extension (correctly identified at `r3-research.md:35`). That means a shared library target exists on day one whether you planned it or not.

Do this, week one, as the concrete repo setup:

- One Xcode project, one app target, one Widget Extension target, one test target. No Tuist — a solo dev with one target graph does not need a project generator.
- One local SPM package with three library targets: `HardsetCore` (pure value types — engine, movement keys, muscle model, `AlarmMetadata` conformance; Foundation only, `nonisolated` throughout, zero SwiftUI/GRDB), `HardsetStore` (GRDB + SQLiteData, schema, migrations, sync), `HardsetUI` (design tokens + components). The app target and the widget extension both depend on `HardsetCore`; only the app depends on `HardsetStore`.
- First commit sets `SWIFT_VERSION = 6.0`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`, `IPHONEOS_DEPLOYMENT_TARGET = 26.1`; `PrivacyInfo.xcprivacy`; `NSAlarmKitUsageDescription` (required — Apple: "If the `NSAlarmKitUsageDescription` key is missing or its value is an empty string, your app can't schedule alarms with AlarmKit," iOS 26.0+); iCloud + CloudKit capability; Background Modes → Remote notifications.
- Sign the Paid Applications Agreement and file tax + banking now. Apple: "the Account Holder must sign the Paid Apps Agreement," and "You won't be able to create a new app or In-App Purchase until you've agreed to the most recent version." Enroll in the Small Business Program before the first sale. Good news: Apple is merchant of record and collects/remits VAT, so you owe no consumption-tax filings — only income tax.

---

## P2 — Consequences of the locked decisions that were not foreseen

**No Watch, but the sync design for a future Watch is contradictory — and the schema is now permanent.** Two audited streams recommend opposite designs: the persistence stream says "Build the Watch app as a standalone target with its own GRDB store and its own SyncEngine on the same CloudKit container" (`new-research.md:576`); the watchOS stream says CloudKit on watchOS terminates the app 30–60s in when Always-On is off and the phone is unreachable (FB17685611) and the watch store must be `cloudKitDatabase: .none` (`new-research.md`, watchOS findings). The watchOS finding is about `NSPersistentCloudKitContainer`, not `CKSyncEngine`, so it may not transfer — but it is unresolved either way. Because "keep the SessionEngine seam so Watch is additive later" is a locked decision *and* the schema is now append-only forever, this contradiction has to be resolved **before the schema freeze**, not when the Watch app starts. Concrete action: assume a Watch peer will write sets, and design set records so a second writer with client-generated immutable IDs and field-wise LWW is already correct.

**No import from Elos means every empty state is the first screen every user sees, and the machine wedge has no cold-start data.** With no history, per-machine progression charts, "Previous," and the volume readout are all empty on day one, and the machine registry starts at zero. The corpus specifies `ContentUnavailableView` as a component but never designs the first-session experience against a truly empty store. Concrete action: treat the empty-state pass as a named workstream, and seed the machine registry with the deduped curated core (the audit notes the 1,697→1,128 dedup is a prerequisite that was never itself budgeted) so the wedge is visible before any user has logged anything.

**$3.99/mo makes the free tier a costed decision, and this run already rebuilt the model — but the second-order consequence is the roadmap.** At ~$25.49 net per annual subscriber and 1.4–2.1% D35 freemium conversion, the base case is $10–12k year one. That does not fund 106 weeks of work. It funds a part-time side project indefinitely, which is fine — but it means the plan must be sequenced so that *the first shippable slice is independently valuable*, because there will not be a runway-funded push to finish the rest.

**Inferred experience level is right, and the corpus already verified the mechanism** (`TrainingProfile` is goal + experience + overrides with `static let default = TrainingProfile(goal: .hypertrophy, experience: .intermediate)` at `Features/Train/Programs/Intelligence/TrainingProfile.swift:123-145`). The unnamed consequence: the volume landmarks scale by experience (0.75/1.0/1.15), so a beginner is silently prescribed intermediate volume until inference kicks in. Define the inference rule and its cold-start behavior explicitly, and show the user what the app currently believes — that disclosure *is* the honesty brand.

**Elos left whole means the engine ideas now exist in two diverging codebases** — already flagged as a risk in round 2 and still unmitigated. Accept the divergence and stop treating Elos as a source of truth; it is a reference implementation you read, not a dependency.

---

## Cut these — premature optimization or YAGNI

- **Foundation Models as a rendering layer.** Gated on A17 Pro / 8 GB, i.e. iPhone 15 Pro and later — a strict minority of an iOS 26.1 install base that reaches down to the iPhone SE 2. It adds three UI states and a whole error surface to serve a fraction of users a prettier sentence than a template. Ship the deterministic template; revisit in v1.1.
- **Managed Background Assets.** The audit already established it does not skip review ("Asset packs must be reviewed before they can be tested externally in TestFlight or made available for users on the App Store"), so it buys no publishing latency. A ~10 MB curated SVG set ships in the binary. Cut.
- **CloudKit record sharing.** `CKSharingSupported`, `CKShare`, the shared database — none of it serves a single-user training log. Every table it touches gets harder. Cut.
- **Uberon anatomical IDs.** The corpus itself calls this a nice-to-have. Cut, and note the append-only schema makes "one extra column costs nothing now" a slightly worse bargain than it sounds.
- **The composite 0–100 score.** Three independent arguments now converge on removing it: its own docstring, the credibility critique, and Guideline 1.4.1's accuracy-claim scrutiny. Cut it from the primary surface.
- **The ≤50 ms tap-to-visible-lock CI gate.** Per this run's audit, unmeasurable by XCTest or XCUITest; keep it as a design rule verified once on device with an Animation Hitches trace.
- **Localization.** Nothing in the corpus decides this, and the honest answer is: v1 is English-only. Say so out loud, because it has a real consequence — coaching copy is hardcoded English inside every scorer in the reference code (`VolumeScorer.swift:78`, `BalanceScorer.swift:56`, `FrequencyScorer.swift:48`, ~20 more), which is precisely the mistake to *not* repeat. Structure tips as data with a rendering layer from the first commit, and put user-facing strings in a String Catalog even while shipping one language. That costs hours now and saves a rewrite later. On the EU legal question: the European Accessibility Act became enforceable 28 June 2025 and covers mobile apps via EN 301 549, but microenterprises providing services (under 10 employees, under €2m turnover) are exempt from its service obligations — so a solo developer is almost certainly out of scope. Document that conclusion rather than assuming it, and note that accessibility still matters for a different reason: the corpus's own set-row VoiceOver finding (a 40-set session costing ~280 swipes if rows are not combined) is a usability defect, not a compliance one.

---

## The thing every stream quietly assumed

That the developer will be building this full-time, at a steady pace, with a working verification loop. All three assumptions are false: the effort tags sum to ~2 years, tests cannot run locally under sandboxed `xcodebuild`, and the three highest-risk subsystems (CloudKit sync, AlarmKit, Liquid Glass) require physical devices that have not been acquired. The single highest-leverage thing to do in the next 30 days is not a feature — it is to establish one authoritative test run on real hardware, freeze the schema against the three append-only rules, install the account-change delegate, and write down what is *not* in v1.