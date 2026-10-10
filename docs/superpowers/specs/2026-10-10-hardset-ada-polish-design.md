# Hardset — ADA-calibre polish, all four phases

Date: 2026-10-10. Status: awaiting the user's review.

## 1. What this is for

**What the user asked for:** use as many agents as needed to perfect the app, guided by what makes
Apple Design Award winners draw people in. All four phases are in scope. Rest length is chosen
per exercise and remembered from the lifter's own last choice. Work happens on this Linux machine:
build and test everything possible here, commit locally, and push to GitHub later so it can be
built on the Mac.

**What I am assuming (correct me):**

- The refusals in `HANDOFF.md` §6 and the invariants in §5 stand. "Draws people in" comes from
  craft, speed and trust, never from streaks, feeds, coaching or invented targets.
- Nothing is pushed to GitHub until the user says so.
- Where this spec and `HANDOFF.md`/`DECISIONS.md` disagree, those files win unless this spec
  records the change as a new numbered decision.

**What success looks like:** a lifter can open the app cold, log a full workout with rest timers
and see an honest summary at the end, fast, accessibly, and so it feels native. Every behaviour
that can be tested off a Mac is tested here. Everything that cannot is listed in a ledger with
the exact check to run on the Mac.

## 2. Evidence this direction rests on

Three read-only audits ran on 2026-10-10: ADA winners and the iOS 26/27 HIG, a screen-by-screen
UX audit, and a platform-surface audit. The ADA findings that shape the design, all from Apple's
own pages:

- **Focus on the current step.** Crouton (Interaction, 2024) shows "only the current step". Mela
  (finalist, 2025) dims and highlights steps as they come up.
- **Restraint wins.** grug (Delight & Fun, 2026) won for "nothing extraneous", and the HIG
  Simplicity principle says every element must earn its place.
- **Explain numbers instead of throwing them at people.** Gentler Streak (Social Impact, 2024) was
  praised for being "less about hard comparisons and more about progress". The Outsiders
  (finalist, 2026) was built for "meaningful insight".
- **Native depth.** Flighty (Interaction, 2023) used Live Activities. Moonlitt (Interaction, 2026)
  won for its Liquid Glass and "easy onboarding". Guitar Wiz (Inclusivity, 2026) won for
  VoiceOver, Dynamic Type, Increase Contrast and Differentiate Without Color.
- **Physical-feeling input.** (Not Boring) Camera (finalist, 2026) was praised for "giant buttons
  and haptic scroll wheels".

Rejected even though they appear in winners, because each conflicts with a refusal: streaks and
leaderboards (Duolingo), share-to-earn medals (Any Distance), gem unlocks (Opal), AI programs
(SmartGym, Fitbod).

## 3. Design direction: one feeling, "calm confidence"

1. **The current set is the hero.** The next set to log is emphasised, logged sets compact, and
   upcoming sets recede. The weight is the largest type on screen.
2. **Honesty you can see.** Certainty is a visual system (glyph and word, never colour alone)
   attached to every derived number, with the source one tap away. Caveats stop looking like
   errors: no orange warning text for a lower bound.
3. **Compared with yourself, on this machine.** Never with a target.
4. **Input that feels physical.** The first key replaces the prefill. ± steps use the machine's
   real increment. One crisp haptic per log.
5. **One earned moment.** A record is marked on the row that earned it and given a distinct
   haptic. Finishing gives a summary. Nothing else celebrates.
6. **Privacy said out loud.** "No account. Your data stays on your devices and in your iCloud."
7. **Quiet on repetition.** Per the HIG, frequent actions get minimal motion, and all motion
   honours Reduce Motion.

## 4. Non-negotiables

- Every invariant in `HANDOFF.md` §5 and every refusal in §6. In particular there is still no
  *default* rest: a rest length exists only after the lifter picks one for that exercise.
- Schema changes are additive only, and each needs a `DECISIONS.md` entry first. Any new table is
  device-local unless a decision says otherwise. `bodyweightEntries` stays unsynced.
- `HardsetApp.swift` stays wiring only.
- `ExerciseCatalog.swift` is never hand-edited.
- The methodology text pinned by tests is never edited. New plain-language summaries are *new*
  fields.
- No set is ever logged from outside the app UI: not from Siri, widgets, controls or the Action
  button. The lifter must see the numbers being saved.

## 5. Verification strategy

| Layer | Where it is verified |
|---|---|
| `HardsetCore` | Linux container (`swift:6.2`), every change test-first |
| `HardsetStore` (except sync) | Linux container, every change test-first |
| Sync, `HardsetUI`, `HardsetFeature`, `HardsetAlarm`, app, widget | Mac only. Logged in `docs/MAC-VERIFICATION.md` |
| AlarmKit, CloudKit, HealthKit, glass, haptics | Physical iPhone (`DEVICE-CHECKLIST.md`) |

**The architectural rule this forces, and the payoff:** behaviour moves out of views into Core or
Store types that views merely render. Examples: the rest plan, the finish flow, the summary, the
alarm reconciliation and the keypad semantics. This is already the codebase's stated principle
(`HANDOFF.md` §7), and here it also decides what gets tested at all.

**`docs/MAC-VERIFICATION.md`** is a running ledger. Every commit that touches unverifiable code
adds an entry: the commit, the file, the exact build or simulator step, and the expected result.
It mirrors `DEVICE-CHECKLIST.md`'s rule that an unchecked box is not "probably fine".

**API discipline for Mac-only code.** No Swift compiler here can check SwiftUI, AlarmKit,
ActivityKit, App Intents or HealthKit calls. So every new Apple API used must be checked against
developer.apple.com documentation, with the URL in the commit message or the ledger. Prefer APIs
the codebase already uses. Every API newer than iOS 26.1 needs an `#available` check.

## 6. Phase 0 — Linux verification harness

A precondition for everything else. All of this was proven in a scratch copy on 2026-10-10: 285
tests across 38 suites pass.

- `HardsetStore`: the CloudKit-only code goes behind `#if canImport(CloudKit)`:
  - the `HardsetSyncDelegate` class only; `AccountChange` and `AccountChangePolicy` stay outside
    the guard so their tests still run on Linux
  - `HardsetDatabase.makeSyncEngine`
  - `attachMetadatabase` in `open`

  Apple builds are unchanged.
- `SessionCoordinator.swift` gets an explicit `import Observation`. On Apple it comes in
  transitively; on Linux it does not.
- `Package.swift` gets an `#if os(Linux)` branch that omits `HardsetAlarm`, `HardsetUI` and
  `HardsetFeature`. It is a test-execution affordance, like the existing `.macOS` platform entry.
  The real manifest is used, not an overlay copy.
- Store tests share one `Configuration` helper (`TestDatabase.swift`). On non-Darwin platforms it
  registers a `uuid()` SQL function. Apple's SQLite provides that function and Linux's does not.
  Sync suites (`SchemaTests`, `SyncDelegateTests`, `SyncEngineRetentionTests`) are guarded.
- `Tools/linux-test.sh` runs `podman run docker.io/library/swift:6.2` against the real package and
  installs `libsqlite3-dev`. `README.md` documents it.
- Re-baseline `Tools/generate_project.py` so its output matches the committed `.pbxproj` byte for
  byte. The HardsetFeature IDs were hand-edited. Verify here with `python3` and `diff`.

## 7. Phase 1 — Trust

Correctness first. Each item lists the layer that holds its logic.

**1.1 Rest, per exercise and remembered** (Core, Store, UI)
- *Core:* `RestPreference` is `.off` or `.after(Duration)`. A pure `RestPlan.duration(after:
  slot, preference:)` returns nil for warm-ups and for `.off`.
- *Store:* `RestPreferenceStore`, a protocol with a `UserDefaults` implementation. It is
  device-local and needs no schema change (`UserDefaults` is already declared in the privacy
  manifest as CA92.1). Tests use an in-memory implementation.
- *Coordinator:* `restAfterSet: Duration?` becomes a lookup against the preference store keyed by
  `ExerciseID`. New methods:
  - `setRest(_:for:)` persists the choice
  - `startRest(for:)` starts a rest by hand
- *UI:* a chip on each exercise reads "Rest · Off" or "Rest · 2:00". Its menu offers presets
  (1:00, 1:30, 2:00, 3:00, 4:00, 5:00), Custom…, Off, and "Start now". Nothing is selected until
  the lifter picks. `restMetadata` is set when a rest starts, which fixes the empty caption.

**1.2 AlarmKit reconciliation** (Core, Store, Alarm)
- *Core:* `AlarmSnapshot` mirrors AlarmKit with the cases `countdown(fireDate)`,
  `paused(remaining)` and `alerting`. A pure `RestReconciler.reconcile(local:persisted:alarms:
  now:)` returns the corrected `RestTimerState` and any stale alarm IDs to cancel.
- *Store:* reads and writes the existing device-local `deviceRestTimer` table.
- *Alarm:* the controller runs `reconcile` on launch and on every `AlarmManager.alarmUpdates`
  value. This fixes the app restarting idle after a force-quit while the alarm still fires, and
  Lock Screen pause leaving the app stale.

**1.3 Alarm permission, honestly**
- Request permission at the first rest, after one explanatory sentence.
- When denied, show a plain banner with a Settings link, keep the on-screen countdown, and fall
  back to a plain local notification (the time-sensitive level needs an entitlement and is
  deferred).
- `RestTimerController.lastError` is shown in the UI.

**1.4 The alert's "Skip" button**
- It is `.custom` with no intent, so it does nothing. Remove the secondary button in Phase 1.
  Phase 4 adds real intents.

**1.5 What you see is what is saved** (UI)
- `SetRowView` reseeds its buffers whenever the draft changes from outside, for example after a
  machine change, not only when the unit changes.

**1.6 Logged rows are locked** (UI)
- No editing a logged set's fields. Editing comes back properly in 2.3.

**1.7 One weight formatter** (Core)
- `WeightFormatter` is aware of unit and locale. It replaces the six local `format(_:)` helpers
  and fixes every "kg in pounds mode" leak:
  - PR copy
  - step chip
  - machine picker
  - `MachineChange.explanation`, which becomes a function of unit

**1.8 Truthful copy**
- "This week" becomes "Last 7 days".
- Methodology certainty comes from `certaintyCeiling` instead of the hardcoded "Moderate".
- Plurals are correct ("1 set").

**1.9 No swallowed failures** (Store/Feature)
Each of these becomes a typed error with plain copy and a retry, or an explicit message:
- `try? SessionCoordinator.resume`
- `try? catalog.seed()`
- the `addMachine` catch
- raw `\(error)` strings

An open session that fails to resume must never look like "no workout".

**1.10 Retry that works**
- Error states get a Retry button, replacing the impossible pull-to-refresh.

**1.11 Housekeeping**
- Make `AppSmokeTests` compile against the real `RootView`.
- Fix the README's stale "never compiled" line.

## 8. Phase 2 — The core loop, crafted

**2.1 Keypad v2** (Core-tested semantics)
- `NumericEntryBuffer` gains "replace on first input": the first digit typed after seeding
  replaces the prefill.
- The pad header shows the value being composed.
- Next moves weight → reps. There is a Clear key.
- ± steps come from Core `LoadStep`: the machine's `stackIncrementKg`, otherwise a unit default
  (2.5 kg / 5 lb). Steps only adjust an existing value and never create one from nil.
- The pad becomes a bottom inset that keeps the active row visible, instead of a 360 pt sheet.
- Target: 100 → 102.5 in 2 taps (±) or 5 taps (typed), down from 10.

**2.2 Active-set focus**
- The next unlogged set is emphasised and the rest recede.
- After a log, the view scrolls to the next set.

**2.3 Edit and delete a logged set** (Store-tested)
- A context menu offers Edit and Delete. The store writes first, then the UI updates.
- Delete has a 5-second Undo that re-inserts the row.
- Edits never announce records. The summary recomputes from the database.

**2.4 Finish flow and summary** (Store-tested `SessionSummary`)
- *Confirm* when prefilled rows were never logged ("2 sets weren't logged and won't be saved").
- *Discard* when zero sets were logged: a new store delete that cascades.
- *Summary sheet:*
  - duration from the closed timeline, or "Length unknown"
  - working sets, reps and volume, read from the database
  - every record this session
  - muscles touched, with "≥" where it is a lower bound
  - machines used
- No streaks, targets or comparisons with goals.

**2.5 The record moment**
- A trophy on the row that earned it, kept for the session (the coordinator keeps records per set).
- A distinct haptic.
- A symbol bounce, gated on Reduce Motion.
- A VoiceOver announcement.
- Copy that states the new estimate in the lifter's unit.

**2.6 Motion and haptics**
- `Tokens.Motion` holds spring presets that collapse under Reduce Motion.
- `.contentTransition(.numericText())` on counts and timers, and symbol replace on the log check.
- A Core `FeedbackEvent` enum maps events to haptics: log, record, error, rest adjust. The UI
  maps those to `sensoryFeedback`.

**2.7 Liquid Glass on the functional layer only**
- A prominent glass Start button and Finish as the `.prominent` toolbar action.
- One floating rest cluster that merges the rest bar and the tab accessory, so the countdown
  stops appearing twice.
- Never on set rows or cards (HIG). Guarded with `#available`.

**2.8 Tokens v2**
- Semantic colours (success, record, caution, critical) separated from certainty colours.
- A certainty palette that meets 4.5:1 for text, with Increase Contrast variants.
- Visible card separation in light mode.
- A hero type style for the weight.

**2.9 Navigation**
- Tapping the accessory goes to Train (`TabView(selection:)`), and the TabView no longer swaps
  identity.
- The exercise picker gets Cancel and a "Recent" section.
- "Repeat this workout" from a past session, started by the user and never preselected or
  recommended. It copies exercises and machines, not loads; prefill still comes from history.

## 9. Phase 3 — Honesty as a visual language, and inclusivity

**3.1 Certainty badges everywhere**
- `CertaintyBadge`, `UnevaluatedReadout` and `AssumptionChip` exist but are unused. They go
  beside every derived number: e1RM, volume, lower bounds.
- Each uses a glyph plus a word. Tapping opens the source.
- Per-muscle certainty replaces the global "Moderate" header.

**3.2 Methodology sheet**
- A new `EvidenceSource.summary` field gives an "In short" line.
- A visual of the 1.0 / 0.5 / 0 credit scheme.
- The DOI becomes a `Link`, and the sheet gets Done and plain titles.

**3.3 Chart**
- A summary headline over the chart (e.g. "Hammer leg press: +5 kg over 6 sessions").
- Scrubbing with `chartXSelection`.
- Each machine gets its own symbol shape as well as its own colour.
- Estimates are dashed. An `AXChartDescriptor` describes the chart to VoiceOver.
- Series are never merged.

**3.4 Accessibility pass**
- *Set row:* the default action logs, with value and traits; VoiceOver announces logs and records.
- *Pad:* the dead decimal key is hidden from VoiceOver, and the pad speaks the value.
- *Rest buttons* are reachable.
- *History rows* are not dimmed.
- Unit names are spoken in full.
- Layouts work at accessibility text sizes (stacked set row, scaled metrics), with 44 pt targets.
- Nothing is signalled by colour alone.

**3.5 First run**
- One screen: three promises (honest numbers, your machines, fast logging), the privacy line,
  and Start.
- Naming a gym is optional. Alarm permission is deferred to the first rest.
- The unit is inferred from locale, with a visible way to correct it.
- No questionnaire, goals or program.

**3.6 History**
- Tappable rows open a session detail (by exercise and machine, records, honest duration).
- Exercise progress is reachable outside a live workout.

**3.7 Gym and machine management**
- Rename and archive, using the existing `GymStore` APIs.

**3.8 Localization readiness**
- String Catalogs and `defaultLocalization: "en"`.
- Core copy moves to `String(localized:)` or `LocalizedStringResource`.
- Locale-aware decimal separator.
- Known risk: package resources previously broke the asset step (`Package.swift:68-70`), so this
  is verified on the Mac before anything is built on top of it.

**3.9 Code health**
- Split `HardsetRootView` (start, gym picker, accessory).
- Move muscle display names into Core and remove the `CertaintyLevel` mirror.

## 10. Phase 4 — System surfaces

**4.1 Rest Live Activity**
- A progress ring (`ProgressView(timerInterval:)`), the machine name, and a guarded date range.
- Pause/resume and stop as `LiveActivityIntent`s.

**4.2 App Intents and App Shortcuts**
- `StartWorkoutIntent` opens the app and starts an empty session.
- `StartRestIntent` requires the duration as a parameter. `StopRestIntent` stops the rest.
- Phrases are registered for Siri, Spotlight and the Action button.

**4.3 Control Center controls**
- Start workout, and Rest with a duration the lifter configures when adding the control.
- These live in the existing widget extension.

**4.4 HealthKit, opt-in and write-only**
- `HKWorkoutBuilder` with `.traditionalStrengthTraining`, with start and end from
  `SessionTimeline`.
- **No energy burned**, because nothing measures it.
- Skip implausible durations.
- The export policy is pure Core and tested on Linux.
- A new device-local table maps sessions to HealthKit IDs. It is additive and needs a decision
  entry.
- **Blocked on a user decision:** a privacy policy URL is required before this can ship.

**4.5 Widgets**
- "Last time on this machine" and the last session.
- The app writes an App Group snapshot file and the widget never opens the database (SyncEngine
  triggers live in the app process).
- Privacy manifest `1C8F.1` for the shared defaults, plus a widget manifest.
- No "days since" counts.

**4.6 App icon**
- A design brief plus SVG layer drafts, to be finished in Icon Composer on the Mac. This needs
  the user's design judgement and cannot be done here.

**4.7 TipKit**
- At most two tips that point out features (the machine chip, tap a name for history). Never
  coaching.

**4.8 Launch background colour and privacy manifest updates.**

## 11. How the agents work

- Each phase gets its own implementation plan (writing-plans), executed with subagent-driven
  development.
- Tasks within a phase that touch disjoint files run in parallel in isolated git worktrees.
  Overlapping tasks run in sequence.
- Every Core and Store task is test-first and runs `Tools/linux-test.sh` until green.
- Every UI task adds its ledger entry.
- A reviewer agent checks each task against this spec and the invariants before merge.
- I merge into `FrankieBiz/porgy` one task at a time, rerun the full Linux suite after each merge,
  and commit small with messages that explain why.
- No push until the user asks.
- Between phases I report what was verified, what was not, and what the ledger holds.

## 12. Open decisions (none block Phases 0–3)

1. A privacy policy URL (blocks 4.4 shipping, not building).
2. The app icon's final artwork (4.6).
3. Still open from `HANDOFF.md` §11: who authors the catalogue, Developer Program membership,
   founding price.

## 13. Risks

- **Mac-only code piles up unverified.** Mitigations: small UI diffs, existing APIs, the ledger,
  and a recommended Mac build after Phase 1 rather than only at the very end.
- **The Swift 6.2 container differs from Xcode's toolchain.** A green Linux run is necessary, not
  sufficient. The Mac build is the authority.
- **Sync behaviour stays untested here.** Phase 0 guards must not change Apple builds, so they are
  `#if` only, with no logic changes.
