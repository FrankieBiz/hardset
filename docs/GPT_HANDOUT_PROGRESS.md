# GPT handout implementation record

Objective: execute `docs/GPT_HANDOUT.md` throughout the existing app while preserving
all permanent schema, concurrency, machine identity and persist-before-claim rules.
Worktree: `zoanthid`; branch: `FrankieBiz/complete-gpt-handout-tasks`.

Acceptance criteria:

- Core remains Foundation-only, strict Swift 6 remains enabled, and logger rendering
  consumes values without database reads.
- A retried set command cannot duplicate or replace an acknowledged set.
- Import validates the entire file and commits atomically; absent equipment is never
  silently identified. CSV, JSON and SQLite exports are reachable without purchase.
- Rest mutations commit durable desired state before UI/OS changes; outstanding OS
  cancellations survive relaunch and stale scheduling completions are reconciled.
- New screens use existing tokens, accessibility text, adaptive layouts and native
  sharing. No decorative or recurring animation is introduced.
- Linux `make check`, expanded portable Store tests, deterministic project generation
  and the existing macOS/iOS workflow verify their respective supported surfaces.

## Requirement coverage

| Handout section | Implementation and acceptance evidence |
| --- | --- |
| 1: Mission and calibrated honesty | No accounts, social graph, feed or coaching added. Receipts distinguish saved user input from independent verification. Imported equipment and attribution remain unevaluated. |
| 1: Machine awareness | Existing exercise × machine keys retained. Receipt records use same-machine comparisons only. Imported movements use separate exercise identities and never seed a native machine benchmark. |
| 1: Persistence | Existing atomic logging, recovery, no-erasure migrations and explicit account-change delegate retained. Stable set command IDs cover lost acknowledgements; conflicting payloads are rejected. |
| 2: Package architecture | Existing targets preserved. `HardsetHealth` adds a platform seam for HealthKit; Core stays Foundation-only. Store owns portable Health persistence. Xcode project remains generated. |
| 3: Invariants | No stored session duration or ticking countdown. New rest checkpoint contains the existing enum and absolute deadlines. New tables are local-only, introduced in v7/v8, with a local chart-order index in v9; no applied migration rewritten. |
| 4: Gym-floor UI | Machine-increment inline load controls use canonical kilograms; keypad remains available for large edits. Logged values cannot be edited. Machine changes refresh idle display buffers. Existing first-key replacement behavior is retained. |
| 5: Hardset Ledger | History opens a saved-set receipt with equipment labels, same-machine PRs, text sharing and a dark rendered image. Unknown/imported equipment produces no machine PR claims. Long receipts use text to avoid unbounded bitmap allocation. |
| 5: Strong/Hevy migration | Settings provides UTF-8 CSV selection, explicit Strong unit context, validated preview and atomic import. Original timestamps/duration are retained; unavailable set completion times are disclosed as grouped at workout start. Supported loads are0–10,000 in the source unit and reps1–999; out-of-range rows are rejected. Exact-file repeat imports are refused on the same device. |
| 5: Apple polish | Existing AlarmKit/Live Activity seam retained; rest journal and reconciliation added, along with explicit duration choices and visible retry. Native selection haptics confirm load adjustments. Apple Health read/write is opt-in in Settings. |
| 5: Monetization | StoreKit non-consumable purchase/restore, verified entitlements, pending/canceled/error states and storefront price. Only the new deep muscle map checks access; existing gyms, logging, history, CSV import and every export remain free. No subscription. |
| 6: Collaboration | No diagrams or attribution trailers. Existing architectural comments and test guarantees retained. New migration tests account for tables that did not exist in historical fixtures. |
| 7–8: Verification | Run the commands below; results are recorded in the task handoff. Apple/device validation is separate from Linux syntax and portable tests. |

## Source and format limits

- [Strong export instructions](https://help.strongapp.io/article/235-export-workout-data)
  and [Hevy import/export instructions](https://help.hevyapp.com/hc/en-us/articles/38001424401943-How-to-Import-Strong-App-CSV-Files-and-Export-Your-Data-in-Hevy)
  establish the user-facing CSV workflow. Their public help pages do not specify a
  versioned schema. The parser supports the tested English Strong and Hevy header
  families, commas/semicolons, quoted multiline fields and BOMs. Unrecognized or
  incomplete rows fail the whole preview; timed/distance-only work is not fabricated
  into load × reps. Real export fixtures from other versions remain compatibility work.
- Strong Weight without a unit uses the explicitly displayed Settings unit. Dates
  without an offset use this device's time zone, disclosed before preview. English
  Hevy dates and ISO 8601 are supported. CSVs over20MB are refused by the file picker.
- JSON exports every application table, nullable value and primary key; SQLite uses
  GRDB's online backup API, including committed WAL pages. CSV exports all logged
  sets with identity, equipment and workout context. Exports are snapshots, not a
  promise of in-app database restore. Export files remain in app temporary storage
  until system cleanup; Save/Share lets the user choose a durable destination.
- The import replay ledger is local, so importing independently on two offline
  devices can create two distinct imported histories. It is not a cross-device lock.
- Health reads at most1,000 body-mass samples and1,000 workout summaries from the
  previous365days. Health observations stay out of synchronized tables and out of
  machine histories. Denied Health reads are indistinguishable from empty reads.
  Health export sends completed plausible native strength sessions, with no invented
  energy/heart rate; metadata uses stable sync IDs and version1 for retry safety.
  See [Apple's sync identifier documentation](https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncidentifier).
- Receipt records compare against complete history before the workout plus earlier
  working sets in that workout. Source load/equipment are entered by the user. The
  briefing's “Verified Honest” wording must not imply independently measured accuracy.

## External release configuration and verification

These actions require the actual platform/service environment; code or a Linux test
cannot establish them:

- Register `com.hardset.app.lifetime` as a non-consumable in App Store Connect and set
  the requested US base price to$19.99. The app reads localized StoreKit pricing;
  it reports unavailable when no product is returned. No App Store Connect product,
  price, purchase or production deployment was created by this code change.
- Enable HealthKit in the signing profile. Test real grants, denials, revocations,
  Health reads, exported workout retry behavior, pending/refunded purchases and
  purchase restoration in an Apple sandbox/TestFlight lane.
- Confirm physical-device AlarmKit authorization, process death, Focus, background
  scheduling, lock-screen stop/expiry and app pause/resume, plus two-account CloudKit retention.
- Measure Release startup, logging and frame timings on a representative device;
  “zero latency” is a design aim, not a timing claim proven by these changes.

## Verification commands

- `make check`
- `make check` now uses repository-owned `Tools/hardset_check.py`, selecting every
  portable Store test automatically. Four named suites requiring the Apple-only
  Database/SyncSetup implementations remain explicitly excluded on Linux. It reuses
  the installed pinned toolchain/official UUID support (`HARDSET_TOOLING_ROOT` can
  select its location). The installed global checker was not changed.
- `python3 Tools/generate_project.py` and `git diff --check`
- `.github/workflows/ios-ui.yml`: macOS package compile, new feature storage tests,
  iOS Simulator app/widget build, app test and screen/AlarmKit-controller suites.

- Pause and resume are app commands so the journal commits before changing OS state.
  The Lock Screen does not expose a daemon-only pause button that would bypass that
  journal. A failed rest-journal read blocks only timer commands and exposes retry;
  the training log and exports remain accessible. Failed mutations retain their
  intended state for an explicit retry.
- A machine’s load step can be entered or cleared from its picker. Saving it updates
  active equipment constraints without re-prefilling drafts or changing saved loads.
- Scheduling acknowledgement is durable. OS change notifications reconcile stop and
  expiry; a previously acknowledged alarm that disappears is not recreated. A pending
  unacknowledged request remains retryable after a process crash.
- An unchanged displayed load step retains its original canonical precision. Reps-only
  edits do not round-trip the untouched load through a rounded pounds display.

## Completed implementation verification — 2026-11-08

- `make check`: 181 Core tests in24 suites, 198 portable Store tests in25 suites,
  124 Swift files parsed, eight indexed query plans and172 contrast pairs passed.
- Native integrated source run [42482223181](https://github.com/FrankieBiz/hardset/actions/runs/42482223181)
  passed the macOS package build, 30 feature tests, iOS app/widget build, app test,
  25 screen/controller tests and four real-app UI tests in dark/light appearances.
- Reviewed system-composited workout completion and light-mode artifacts. The
  expanded finish confirmation requires scrolling above the floating accessory;
  the real-app journey now performs that scroll before tapping Finish.
- Apple audits remain evidence rather than a blanket accessibility certification:
  system navigation text scaling, search-field clipping and other recorded findings
  remain in the artifacts. Light start audit reported no issues. Physical-device
  performance, signed service behavior and external release configuration above
  remain unverified.
