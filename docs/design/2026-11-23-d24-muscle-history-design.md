# D24 — Rebuilding the paid unlock around time

- Status: design note for review. No production Swift was changed for this document.
- Supersedes: the surface described in `MuscleHeatmapView.swift`, not the entitlement.
- Product ID stays `com.hardset.app.lifetime` (`LifetimeAccess.swift:37`). Existing buyers keep the
  entitlement (`docs/release/RELEASE-RUNBOOK.md:305`); nothing here touches StoreKit.
- Serves: D17 ("the unlock buys analysis over time"), D24 ("rebuilt around time, or it does not ship
  in 1.0"), D21 (the Scale), D20 (the figure roles), **D30 (the surface is "Muscle history")** and
  **D31 (a session dated in the future counts in lifetime totals and never in timing)**. The
  feature-gate boundary the launch plan already states — "deep muscle analysis over time unlocks;
  live logging, history, and raw data exports remain 100% free" (`docs/LAUNCH-PLAN.md:272`) — is
  exactly what this note implements.

## 0. The defect, stated precisely

The paid sheet draws `MuscleHeatmapView` (`WeeklyVolumeScreen.swift:185-187`), which is a grid of one
fractional set count per muscle for the window the free screen is currently showing. The free
Volume tab already lists every one of those counts, per muscle, for the same window
(`VolumeReportView.swift:289`), plus the same gap list (`VolumeReportView.swift:446`), plus the same
certainty sentence (`VolumeReportView.swift:259`). The paid sheet adds nothing the free screen does
not already say; it repeats it in a grid.

So the rebuild is not "improve the grid". It is: **remove the weekly count from the paid surface
entirely**, and sell the three things the free screen structurally cannot show — when, how the
current stretch compares, and how long — plus the shape of the last twelve weeks. Everything a
number is *made of* stays free (see §3). The surface is called **Muscle history** (D30).

## 1. Data feasibility

The schema needs no change. All four numbers are computable from `loggedSets` plus the current
attribution on `exercises`, and the aggregate behind two of them reads less than a query the app
already runs every time the Progress tab opens.

The one thing to understand first: **there is no per-muscle column anywhere, and there must not be.**
A muscle's figure is derived by crediting each set through the movement's attribution
(`MuscleTaxonomy.swift:421` → `SetCounting.weight` at `:431-438`), which is 1.0 direct, 0.5 indirect,
0.0 stabilising. Every query below therefore returns *per movement*, and Core does the muscle
arithmetic with the same function the free screen uses (`VolumeAnalyzer.credit`, `MuscleVolume.swift:123-130`).

| Number | Read | Arithmetic | Exact? |
| --- | --- | --- | --- |
| **Last trained** | one grouped aggregate over `loggedSets`: `exerciseID`, `max(completedAt)`, `count(*)` | per muscle, the latest instant among movements whose credit for it is > 0 | yes |
| **Current 4 weeks** | four of the existing seven-day windows, `weeksBack` 0…3 | `VolumeAnalyzer.report` per window, summed | yes |
| **Previous 4 weeks** | `weeksBack` 4…7 | same | yes |
| **Lifetime sets** | the same grouped aggregate as "last trained" | per movement `count × setWeight`, summed | yes |
| **Twelve-week shape** | `weeksBack` 0…11 | the twelve window reports above, oldest first | yes |

### 1.1 Last trained, lifetime and the future, in one statement

D31 rules that a session dated in the future counts in lifetime totals and never in timing. The
one grouped read carries both halves, because SQLite's filtered aggregates answer them without a
second pass:

```swift
// One row per movement, over the whole history. Warm-ups excluded in SQL, because
// `hardSets` means working sets (`MuscleVolume.swift:55-56`) and no credit is given here.
// The filters are D31: a set dated after `now` counts in the count the lifetime figure is made
// from, and in neither the latest date nor the earliest date that place it in time.
let grouped: [(UUID, Int, Int, Date?, Date?)] = try LoggedSet
  .where { !$0.isWarmup }
  .group { $0.exerciseID }
  .select {
    ($0.exerciseID, $0.exerciseID.count(),
     $0.exerciseID.count(filter: $0.completedAt <= now),
     $0.completedAt.max(filter: $0.completedAt <= now),
     $0.completedAt.min(filter: $0.completedAt <= now))
  }
  .fetchAll(db)
```

The first count is the lifetime one; the second is the count that can be placed in time, so the
difference is the number of future-dated sets the sheet owns up to. `max` and `min` are filtered the
same way, so a future date can never become "last trained" and a future date can never open the
shape. Nothing is clamped to `now`, dropped from the total, or counted as a negative interval.

This shape is already in the app: `CatalogSeeder.recent` does the same `group`/`select` with
`completedAt.max()` (`CatalogSeeder.swift:283-287`), and `TemplateStore` does it for last-done days
(`TemplateStore.swift:148-152`). Filtered aggregates are in the pinned swift-structured-queries
(`AggregateFunctions.swift:19-30` and the `filter:` argument on `max`/`min`). It is also *smaller*
than a query the Progress tab already runs on every visit: the board reads every working set in
history with six columns (`Tools/check_query_performance.py:88-91`, whitelisted at `:101`). This
reads one row per movement.

Expected plan, to be proven rather than asserted: the partial index added in v3 is
`loggedSets(exerciseID, machineID, weightKg DESC, reps DESC, completedAt DESC, id DESC, sessionID)
WHERE NOT isWarmup` (`Migrations.swift:366-376`). Its leading key is `exerciseID`, it carries
`completedAt`, and its predicate is exactly the query's, so the aggregate should be answered from
the index alone with no table read and no temporary sort. The design note does not claim that as
measured; §4 says how to prove it, and what to do if it fails.

Lifetime is then exact, not approximate: the credit weight is a property of the *movement's role*,
not of the set, so `Σ_movements count × weight` is identical to materialising every set and crediting
it one at a time. That equality is what makes the lifetime figure and the twelve-week shape
reconcilable at all, and §4 turns it into a test.

### 1.2 The four-week windows already exist

`VolumeWindowRange(endingAt:weeksBack:)` (`VolumeStore.swift:178-205`) is not a 7-day constant to be
generalised; it is a family of adjacent seven-day windows:

- `weeksBack: 0` = `[today − 6 days at local midnight, now)`;
- `weeksBack: n` = `[today − 7n − 6 days, today − 7(n − 1) − 6 days)`;
- adjacent windows meet exactly and none overlaps (proved at `VolumeStoreTests.swift:380-397`).

So the current four weeks are windows 0–3, whose union is `[today − 27 days, now)`, and the previous
four are 4–7, which union to `[today − 55 days, today − 27 days)`. The twelve-week shape is 0–11.
No new window type is needed, and the daylight-saving and boundary-day behaviour that took a test to
settle (`VolumeStoreTests.swift:399-413`) is inherited rather than re-derived. Days are added with
the calendar, so a clock change moves no boundary by an hour (`VolumeStore.swift:170-177`).

Every window ends at `now`, so a set dated after `now` is in no window at all: D31's timing half is
the window's own half-open end, not a second filter. The lifetime total is the only figure that
counts it, and §2.5 says so in one sentence.

Summing four reports is exact, not a convenience: each set falls in exactly one window, so
`fractionalSets`, `hardSets`, `unattributedHardSets` and `setsTouchingGroup` are all additive
(`MuscleVolume.swift:51-66`). One `MuscleVolumeReport.merging(_:)` extension in Core is the whole
mechanism.

### 1.3 Imports are real training, and they count

Nothing in the read excludes imports, and nothing should. `readCountableSets` filters on
`completedAt` and `isWarmup` only (`VolumeStore.swift:117-126`). The import machinery appears in
three places, and each is a *label*, never a filter, for volume:

- `VolumeWindowReading.importedMovements` exists so a "Worked from" line can say "imported movement"
  (`VolumeStore.swift:151-153`, rendered at `MuscleCountWorking.swift:186-189`);
- an imported *movement* is `CatalogEntry.isImported` (`CatalogEntry.swift:32-37`), set by the
  importer and read by `CatalogSeeder.isImported`;
- imported *sessions* are recognised by `notes LIKE 'Imported from %'` (`VolumeStore.swift:347`).

The one place imports are excluded is the picker's "recent" list, because logging against an imported
duplicate earns no volume (`CatalogSeeder.swift:260-266`, `:284`). That is a picker rule, not a
volume rule, and this surface must not copy it.

Consequences to state on the sheet, not to engineer around:

- The lifetime total includes imported workouts, so it is a history figure and not a
  since-install figure. One line says so.
- An import's dates were read in the zone the importer was told (`WorkoutCSVImport.swift:219`,
  `zoneNote`). A set at 23:30 in that zone can land in a different week than the lifter now expects.
  Twelve-week bucketing uses the lifter's current calendar, which is the rule history months already
  accepts and defends (`HistoryStore+Months.swift:8-12`). Not fixed here; named in the note.
- There is no per-import filter, and adding one would create a second lifetime total. Refused
  deliberately.

### 1.4 What is honestly weaker, and the smallest alternative

Three real limits. None needs a schema change; the first two need disclosure, the third needs one
decision.

1. **Attribution is today's, not the day's.** `readAttributionEntries` reads live `exercises` rows
   and excludes archived ones (`VolumeStore.swift:128-130`). So a lifetime figure is "credit as
   attributed now". This is not new — the free screen already discloses that its counts use current
   attribution — but a lifetime total makes it heavier: editing one movement's body part changes a
   number that reads like a permanent total. Smallest honest alternative: keep current attribution,
   say so, and let the "Worked from" account for the lifetime figure be the list of movements and
   their credits, which makes the sentence checkable line by line. Storing attribution per set would
   be a permanent column on every set and could still not be backfilled; rejected for 1.0.
2. **Archiving a movement moves its sets to "unattributed", not to another muscle.** This is already
   the tested behaviour (`VolumeStoreTests.swift:313-332`), and it is the right one, but on a
   lifetime figure it means the number *falls* and the sheet must say why rather than shrink
   silently. This is why lifetime must carry `isLowerBound` and `unattributedHardSets`
   (`MuscleVolume.swift:59-76`) and render "≥" exactly as the weekly rows do. Do not "fix" it by
   reading archived rows' attribution: the four-week figures would then use one attribution and the
   lifetime another.
3. **A muscle with no credited set is not the same as a muscle that was never worked.** The report
   already models this as absent-not-zero (`MuscleVolume.swift:52-54`, `:80-82`), and `isLowerBound`
   says when absence is a floor rather than a fact. The lifetime figure needs the same three-way
   distinction, and the sheet needs a fourth state for content debt: `neck` has no direct movement in
   the catalogue at all (`ExerciseCatalog.swift:1925-1927`), so its emptiness is ours, not the
   lifter's. §3 gives the four states and their words.

If any of the four numbers had needed a schema change, the smallest honest addition would have been
a nullable `sessions.importedSource TEXT` to replace the `notes LIKE` heuristic: additive, no `CHECK`,
no `UNIQUE`, and nothing removed or renamed, which is the rule the frozen `v1` and every forward
migration follow (`Migrations.swift:1-29`) — v10 is the same discipline in practice, where a column
is kept and emptied rather than dropped (`Migrations.swift:455-460`). It is **not** needed for these
four numbers, and it cannot be backfilled for existing rows, so it is recorded as a future option and
explicitly not part of D24.

## 2. The surface

**A sheet from the existing pinned entry point on the Volume tab.** Not a sixth screen: the entry
row, the entitlement load, the sheet presentation and the "Worked from" stack over it already exist
in one place (`WeeklyVolumeScreen.swift:120-161`, `:174-203`), and the tab set is fixed at four plus
Settings (`HardsetRootView.swift:284-311`). A new screen would mean a new navigation destination, a
second place to explain the entitlement, and a second loading state.

### 2.1 What changes, file by file

| File | Change |
| --- | --- |
| `HardsetCore/MuscleHistory.swift` | new. `MuscleHistory` value (five reports/collections), `MuscleHistoryAnalyzer` (buckets, merges, last-trained map), `MuscleHistoryCopy` |
| `HardsetCore/MuscleVolume.swift` | add `MuscleVolumeReport.merging(_:)`; no change to `VolumeAnalyzer` |
| `HardsetStore/MuscleHistoryStore.swift` | new. One read transaction: the grouped aggregate, twelve `readCountableSets` calls, one attribution read, the movement names |
| `HardsetStore/VolumeStore.swift` | three readers from `private static` to `static` (`readCountableSets`, `readAttributionEntries`, `readMovements`) so the archive and attribution rules are shared, not copied. Behaviour unchanged |
| `HardsetUI/MuscleHistoryView.swift` | new. Replaces `MuscleHeatmapView.swift` |
| `HardsetUI/MuscleHeatmapView.swift` | deleted |
| `HardsetFeature/WeeklyVolumeScreen.swift` | the sheet body becomes `MuscleHistoryView`; the pinned row is re-gated (§2.4); the working helpers stay, with a 28-day label |
| `HardsetFeature/HardsetRootView.swift` | constructs the history store alongside the volume store and passes it to the Volume screen |
| `HardsetFeature/LifetimePurchaseSection.swift:10` | the one sentence naming what is unlocked |
| `HardsetFeature/LifetimeAccess.swift:22-23` | the development-build note, and the extracted purchase gate (§4.4) |
| `HardsetUI/VolumeReportView.swift` | doc comments at `:24`, `:228`, `:259`, `:478`, `:496` that describe the paid surface |
| `HardsetUI/ProgressBoardView.swift` | `Sparkline` gains the include-zero domain (§3.5) |
| `HardsetUISnapshotTests/ScreenSnapshotTests.swift:99-110` | the `deepMuscleMap` captures become `muscleHistory` captures |
| `docs/release/APP-STORE-METADATA.md:43,93,243,258`; `RELEASE-RUNBOOK.md:178,260,269`; `PRIVACY_POLICY_DRAFT.md:40`; `SUPPORT_DRAFT.md:62` | the old surface name no longer describes the unlock; the paid surface is "Muscle history" (D30) |

`SessionView.swift` is not touched, and it must not be: it is on `check_interaction_rules.py`'s
logger path (`:33-42`) and carries the log moment, the pad traversal and the rest bar. This surface
logs nothing.

### 2.2 What the sheet is

Per muscle, in `Muscle.allCases` order — the taxonomy says declaration order is display order
(`MuscleTaxonomy.swift:28`) — four things and nothing else:

1. **Last trained** — the date of the most recent working set that credited it, with the movement
   that set it. Not a weekly count.
2. **Last 4 weeks against the 4 before** — two fractional counts and their signed difference. Not a
   percentage when the previous window is zero.
3. **Lifetime** — fractional sets credited since the first logged set, with "≥" when the history
   holds unattributed working sets.
4. **A twelve-week shape** — one point per seven-day window, oldest first. Twelve because that is
   already the app's sparkline length (`ProgressTrend.swift:14-17`), not a new number.

No 7-day figure appears anywhere in the sheet. That is the defect fixed by construction, not by
restyling: the paid surface contains no number the free screen shows.

Two habits the free screen already keeps are inherited rather than re-decided. The sheet names its
span by dates, not "this month" — a rolling window called "this month" counts the wrong days on the
first of the month (`WeeklyVolumeScreen.swift:33-36`, `:267-273`). And it loads once per opening,
keeping one snapshot on screen, for the reason the free screen gives: a figure that changed while
being read would describe two windows at once (`WeeklyVolumeScreen.swift:26-30`).

### 2.3 What the entitlement gates, and what it does not

Gated: the four figures above, and nothing else.

Never gated, on this sheet or any other:

- how sets are counted (`MethodologySheet.setCounting()`, already free from the Volume header and
  Settings, `WeeklyVolumeScreen.swift:205-210`);
- what a certainty is about (`VolumeAnalyzer.certaintyMeaning`, `MuscleVolume.swift:232-241`);
- the reason a number is a floor, or that attribution is today's;
- the "Worked from" account *of any figure on this sheet*. A figure the lifter can see must open to
  the sets it was made from — that rule is the product, and locking an explanation behind a second
  interaction would undo it. The paid sheet's figures open the same `WorkedFromSheet`
  (`WeeklyVolumeScreen.swift:197-200`), built from the same Core derivation as the free rows
  (§3.6).

### 2.4 A free user's view, and the entry row

Free: the pinned row, then the offer. `LifetimePurchaseSection` unchanged in structure — heading,
one sentence, price, restore, and no fake preview (`LifetimePurchaseSection.swift:5-40`). The sheet
must not render the lifter's real numbers blurred, greyed or truncated: a blurred figure is still a
claim about their data, and a teaser list of *their* muscles is a second place to see weekly numbers.

The pinned row's gate has to change. Today it is `window.report.hardSets > 0`
(`WeeklyVolumeScreen.swift:122`), which for a time surface is wrong in both directions: a lifter in a
deload week has a history and would lose the row, and a lifter with no history would be shown a
purchase offer over nothing. The predicate becomes:

```swift
// The row appears where there is history to show, or where the lifter has already bought it and
// may be owed the sheet's own empty state. It never appears before the entitlement is known.
if window.report.hardSets > 0 || (lifetime.hasLoaded && lifetime.isUnlocked)
```

No extra query: `hardSets` is already in the report the screen holds.

### 2.5 Degradation with no history, and the future

Three states, each with words rather than zeros:

1. **Nothing logged at all.** `hardSets == 0` and no lifetime rows: the row is hidden (§2.4), so this
   state is reachable only by an owner. The sheet says what it will show once a set exists. It does
   not draw 22 tiles of nothing.
2. **History shorter than twelve weeks.** The shape spans `min(12, weeks since the first logged
   working set)` and its label names the span. Pre-history weeks are **not** drawn as zero, because
   nine empty points would read as nine untrained weeks. The app already settled this question for
   Progress, in words: a row says how much history it does have rather than borrowing a window
   (`ProgressTrend.swift:33-35`, `ProgressCopy.swift:55-65`, and `ProgressCopy.span` at `:73-85`).
   The sheet reuses the same idea through `MuscleHistoryCopy`.
3. **A muscle with nothing.** Four states, §3.4.

D31 adds one sentence, not a fourth state: when `futureDatedSets > 0`, the sheet says once, in plain
words, that those working sets are dated in the future, count in lifetime totals, and are not in
"Last trained" or the weekly figures. It does not clamp the date, drop the sets from the total, or
show a negative number of days since.

## 3. The numbers' honesty

### 3.1 Measured or derived

| Figure | Kind | Largest role | Certainty badge |
| --- | --- | --- | --- |
| Last trained (a date) | count — a set exists at that instant | `readout` 28 at most, inside a sentence | no |
| Current 4 weeks, previous 4 weeks | derived — fractional credit, an adopted convention | `readout` 28 | **no** (§3.2) |
| Their difference | derived — a ratio of two derived counts | `readout` 28, never larger | no badge (§3.2): it is a difference of two four-week totals, and its account states both sides rather than placing either on the weekly curve |
| Lifetime sets | derived — `Σ count × weight` under the same convention | `readout` 28 | no |
| Twelve-week shape | derived — twelve fractional counts | no figure at all | no |

### 3.2 The certainty badge does not belong on a four-week figure

`MuscleCertaintyBadge` is not a confidence in the *count*. It is the engine's placement of a count on
a **weekly** dose-response curve: `doseResponse(fractionalSets:for:)` is defined per week
(`MuscleVolume.swift:217-230`), and the sentence every screen carries says "published studies of
weekly sets" (`:232-241`), which the paid surface repeated before this rebuild. Putting that badge
beside a 28-day total would silently reinterpret a weekly curve as a monthly one. So the sheet
carries no per-muscle badge on the window totals, and says once, in the sheet's own caption, that
the research behind the badge is about weekly sets and this surface does not rate a four-week total.
The free Volume screen keeps its badges unchanged. The difference is a difference of two four-week
totals, so it carries no badge either; its account states both counts and the direction, and repeats
the same certainty-meaning sentence rather than placing either total on the weekly curve.

### 3.3 The Scale (D21): this sheet has no monument

DESIGN.md is explicit that size is earned by being a measurement, and that an estimate — "a
fractional muscle credit, a percentage change in either, a trend" — is never drawn above
`Tokens.Text.estimateCeiling` (28 pt) (`DESIGN.md:228-239`). Applied to each figure here:

- **Last trained** is a measured instant, so it may be drawn large. Its natural size is still
  `readout`, inside a sentence and beside a movement name: a date is not a figure the screen leads
  with, and nothing here earns a monument.
- **Lifetime sets is derived**, so it may not exceed 28 pt. This answers the question the brief
  raises directly: *a measured lifetime total may be a monument; this one is not measured.* A per-muscle
  lifetime number is a sum of fractional credits, which is a convention applied to a count. There is
  no measured per-muscle lifetime total in this schema and there cannot be, because one set credits
  several muscles at different weights by design (`DECISIONS.md:244-249`).
- **The four-week totals and their difference are derived**, so 28 pt is their ceiling too, and the
  difference always travels beside its certainty.

**Therefore: no monument on this sheet**, and `Tools/check_figure_cap.py` gains no entry in its
`ALLOWED` map (`:35`). If the owner wants a monument here, the only honest candidate is an integer
count of *working sets that credited the muscle* (any credit > 0), which is measured — but it is a
third quantity, and showing it next to the fractional lifetime total would put two different
"lifetime sets" on one screen. That is the conflation `DECISIONS.md:244-249` exists to prevent, so it
is refused rather than deferred. Overruling it means adding the file to `ALLOWED` with its reason,
which is exactly the visible diff that check is built to force (`Tools/check_figure_cap.py:8-18`).

### 3.4 Four states for a muscle with nothing

| State | Condition | What the sheet says |
| --- | --- | --- |
| Content debt | token has no direct movement authored — currently `neck` (`ExerciseCatalog.swift:1925-1927`) | the existing gap copy (`UncatalogedMuscleCopy`, `VolumeReportView.swift:481-490`), unchanged |
| No credited sets | absent from lifetime `fractionalSets`, and lifetime `unattributedHardSets == 0` | "No credited sets", plus the convention sentence. No shape, no "0", no trend |
| A floor | absent from lifetime `fractionalSets`, but lifetime `unattributedHardSets > 0` | "No credited sets · N working sets have no body part recorded." with the Library route (`MuscleCountWorking.unattributedWayOut`, `:184`) |
| Trained | present in lifetime `fractionalSets` | the four figures |

The middle two are the ones that keep the sheet from saying "you have never trained your hamstrings"
to someone with 40 unattributed sets. The report already models absence-vs-zero
(`MuscleVolume.swift:52-54`, `:74-76`); the sheet must not flatten it.

### 3.5 The shape, and the one existing component it must not be

`Sparkline` (`ProgressBoardView.swift:381-408`) is the right precedent and the wrong settings. It is
hidden from VoiceOver (the row's sentence carries the meaning), it marks its newest point, and it is
dropped entirely at accessibility text sizes (`:242-245`). Keep all three.

Change one thing: the Progress sparkline draws `chartYScale(domain: .automatic(includesZero: false))`
(`:403`), which is right for a load series with no impasses and wrong here — with the zero excluded,
a week with no sets sits on the same floor as a week with one set, which is precisely the "zero with
a trend" the brief forbids. The muscle shape must include zero, so an untrained week is visibly at
the bottom. If the component is shared, parameterise that one argument; if it is not, the new view
draws its own with the same rules and a comment saying why the domain differs.

### 3.6 Inspection: every derived figure opens the working

DESIGN.md: a figure the lifter cannot inspect is what the product refuses, and every capped estimate
opens "Worked from" through `WorkedFromSheet` (`DESIGN.md:241-250`). No new derivation is needed:

- **A window total's working** is `MuscleCountWorking.derive` fed that window's sets — the exact call
  the free rows already make (`WeeklyVolumeScreen.swift:214-223`), with a 28-day label.
- **The lifetime figure's working** is the same type, fed the grouped counts materialised as
  `[CountableSet]`. The repository already does this to reuse the one analyser instead of writing a
  second: `SplitBalanceAnalyzer` turns `plannedSets` into `CountableSet`s one by one
  (`SplitBalance.swift:74-80`). Materialising a few hundred trivial structs on demand is cheaper
  than a second accounting path, and it guarantees the account adds up to the figure
  (`MuscleCountWorking.swift:260-274`).
- **The difference's working** is the two window accounts plus the same certainty words.

Two consequences to accept knowingly. The lifetime account cannot list warm-ups "Left out" with a
count, because the aggregate excluded them in SQL; it says they were excluded without a number. And
`Tools/check_interaction_rules.py` will **not** catch a new capped estimate — its table is a fixed
dict of six files with two hooks each (`:238-245`), and it only fails when a listed hook is removed —
so the new view's hookup must be added there and its row to DESIGN.md's audit table
(`DESIGN.md:252-274`) by hand. That is a process gap worth knowing
before someone adds a figure with no control and gets a green build.

## 4. Tests that would prove it

The repository's fixture style is fixed and all of it runs on Linux except the last item.

### 4.1 Core — `hardset-check core`, suite `MuscleHistoryTests`

Style: pure values built inline, no database, as `MuscleVolumeTests` and `MuscleCountWorkingTests` do.
Build an `AttributionIndex` from `CatalogEntry` values (`MuscleVolume.swift:30-36`) and per-movement
`(count, lastAt)` pairs.

1. **Trained in one window and not the other.** A muscle with 6 sets five weeks ago and 2 in the last
   week: current 2, previous 6, difference −4 and no percentage confusion, last trained in the current
   window, lifetime 8.
2. **The mirror.** Previous only: current is absent-not-zero, the difference is reported as a fall
   with no division, and last trained falls in the previous window.
3. **The empty case.** No credited sets and no unattributed sets: absent from every collection, no
   shape, and the copy selects the "No credited sets" state.
4. **The imported case** (Core half): the credit path does not care where a set came from, so assert
   that an imported movement's counts produce identical figures and that its account lines carry
   `isImported` (`MuscleCountWorking.swift:186-189`).
5. **A gap in the middle.** A zero week between two non-zero weeks keeps its position in the twelve,
   so the shape dips rather than interpolating.
6. **Short history.** Fewer than twelve weeks of sets produces fewer points and a span label naming
   what exists.
7. **The spanning property.** Lifetime equals the sum of the twelve window reports plus whatever
   precedes them, and the last four windows sum to the current four-week report, for a fixture with
   history older than twelve weeks. This is the test that catches the two-code-path drift named in
   §5.
8. **Boundaries.** A set exactly on a window boundary counts in one window, not two, mirroring
   `VolumeStoreTests.boundaryDaySetStaysPut` (`VolumeStoreTests.swift:399-413`).
9. **The future (D31).** A movement whose only sets are dated after `now` is in the lifetime total
   and in no shape point and has no last trained; `futureDatedSets` counts those sets; the copy
   sentence selects.

### 4.2 Store — `hardset-check store`, suite `MuscleHistoryStoreTests`

Style: a real migrated database every time — `DatabaseQueue` + `HardsetMigrations.migrator().migrate`,
then `CatalogSeeder(database:).seed(now:)` so the tests run against shipped attribution rather than a
hand-made fixture (`VolumeStoreTests.swift:14-27`), and sets written through `LoggerStore.logSet`
(`:36-47`).

1. **The fixed two-window fixture**, read end to end from disk: assert all four numbers and the last
   two buckets.
2. **Empty database**: no lifetime rows, no last trained, `hardSets == 0`, and no crash on an empty
   attribution index.
3. **The imported case**: build a Strong CSV, `WorkoutCSVImport.preview` then
   `DataTransferStore.commit` — the exact pattern at `VolumeStoreTests.swift:177-220` — and assert the
   imported sets count toward lifetime and last trained. Then give the imported movement a body part
   and assert the figure moves, which is the "imports count once they are attributed" rule the free
   screen already relies on.
4. **Archived movement**: archive after logging and assert the lifetime figure becomes a lower bound
   with the right `unattributedHardSets`, rather than shrinking silently. Mirrors
   `VolumeStoreTests.swift:313-332`; this is the test that pins the honest degradation in §1.4.
5. **One read**: `db.trace` and assert one `BEGIN`, as `VolumeStoreTests.reportUsesOneRead` does
   (`:49-63`). Twelve window reads and one aggregate must not become thirteen transactions.
6. **Consistency with the free screen**: for the same instants, `MuscleHistoryStore`'s current
   four-week total for a muscle equals the sum of `VolumeStore.loadReport` over
   `VolumeWindowRange(endingAt:weeksBack:)` for `0...3` (`VolumeStore.swift:68-79`). Two entry
   points, one rule.
7. **Future-dated history (D31)**: log a set dated after `now` and one dated before it. The future
   set is in the lifetime total, in no bucket of the twelve-week shape, and not the last trained
   date; `futureDatedSets` is 1; no negative interval is produced. Then log a future-only movement
   and assert it has a lifetime figure and no last trained.
8. **Boundaries**: a set exactly on a window boundary appears in one bucket of the shape and the
   sum of the buckets equals the figures the window reports give, mirroring
   `VolumeStoreTests.boundaryDaySetStaysPut` (`VolumeStoreTests.swift:399-413`).

### 4.3 The query gate — `Tools/check_query_performance.py`

Add both new shapes to `QUERIES` (`:24`) and run the existing 100,000-set fixture. Measured here: the
four-week and twelve-week reads are a `SEARCH` on `loggedSets_on_completedAt` with no temporary sort;
the grouped lifetime aggregate is a covering scan of the partial working-set index (the fixture plans
it on `loggedSets_on_workingReps`), with no temporary b-tree. A whole-history aggregate returns one
row per movement and cannot be a keyed lookup, so it is listed in `WHOLE_HISTORY` (`:112-117`) with
that reason, beside `progress board sets`. Do not add a sixth near-duplicate index: v9 already ships
`(exerciseID, completedAt DESC, …) WHERE NOT isWarmup` (`Migrations.swift:446-454`). If a future
change makes this aggregate build a temporary b-tree, that is a plan regression, not a reason for a
new index.

### 4.4 Entitlement gating — simulator only, and extracted for exactly that reason

`LifetimeAccess` wraps StoreKit and has no test today. That is why the gate should be a pure function
rather than three `if`s inside a view body: one internal value that maps
`(hasLoaded, isUnlocked, isDevelopmentBuild)` to `.checking`, `.offer` or `.content`, tested in
`KitLogicTests` beside the certainty mapping (`KitLogicTests.swift:1-10`), with captures added to
`ScreenSnapshotTests` in the old grid capture's place — dark and narrow, light and `accessibility3`
(`ScreenSnapshotTests.swift:99-110`). The captures show the content states the view can draw; the
purchase gate itself needs StoreKit and is not snapshot-testable on Linux. State plainly in the
report: `KitLogicTests` and the snapshot suite run under `xcodebuild test` on the Mac (`make
mac-test`), not in Linux `make check`, so a green Linux gate says nothing about the purchase gate.

## 5. Cost and risk

### 5.1 Size

| Area | Files | Rough lines |
| --- | --- | --- |
| Core (types, analyser, copy, merge) | 1 new, 1 edited | 280–340 |
| Store (one read, twelve windows) | 1 new, 1 edited | 110–150 |
| UI (sheet, per-muscle rows, shape) | 1 new, 1 deleted, 1 edited | 240–300 |
| Feature wiring (sheet, row gate, copy) | 3 edited | 60–80 |
| Tests (Core, Store, query gate, snapshots, kit logic) | 2 new, 3 edited | 420–520 |
| Docs, release copy and Design's audit table | 5 edited | 40–60 |
| **Total** | **~20 files (6 new, 14 edited)** | **~1,150–1,450, roughly a third of it tests** |

No schema migration, no new index unless §4.3 proves one is required, no change to logging, StoreKit,
sync or the free screen's figures.

### 5.2 The one thing most likely to go wrong

**The lifetime figure and the twelve-week shape are computed by two different code paths, and a drift
between them is silent.** One is a SQL aggregate; the other is twelve `VolumeAnalyzer.report` calls.
They agree today only because credit is a per-movement constant (`MuscleTaxonomy.swift:421`) and
because both read attribution through the same function — and that second "because" is one refactor
away from being false. If someone makes `readAttributionEntries` include archived rows for the
aggregate, or excludes warm-ups in one path and not the other, the sheet shows a lifetime total that
does not contain the weeks drawn above it: no crash, no test failure, a plausible number that is
wrong, on the one screen whose entire claim is that its numbers are inspectable. The defences are
structural, not decorative: share the readers rather than copy them (§2.1), and make §4.1 test 7 a
property over a fixture with history older than twelve weeks so the two paths are reconciled on every
run.

The runner-up, because it is more likely in the field and more visible: an imported CSV with a wrong
year. `WorkoutCSVImport` rejects only dates beyond `Date.distantFuture` (`WorkoutCSVImport.swift:156-157`),
so a mistyped export can put a set in 2062. D31 rules what happens rather than inventing a
plausibility cutoff for a lifter's own history: the set stays in the lifetime total, it never renders
as "last trained", it never enters a four-week or twelve-week figure, and the sheet says in one
sentence that some sets are dated in the future. Nothing is clamped, dropped, or shown as a negative
interval.

### 5.3 What this note does not decide

- ~~The row's label, and whether the old surface name is retired everywhere in one pass or aliased for
  a release.~~ **Ruled (D30): the surface is "Muscle history" everywhere in one pass** — the sheet
  title, the Settings row, the In-App Purchase display name, `LifetimePurchaseSection`'s sentence,
  the store description, the review notes, the privacy policy, the support page, the runbook and the
  snapshot test names. The old name cannot stay: it names a grid that no longer exists.
- Whether the free Volume tab should offer a one-line pointer at the paid sheet for a lifter whose
  history is long. Not proposed here: it risks a second place to read weekly numbers.
- Whether a future import-provenance column replaces the `notes LIKE` heuristic (§1.4).
