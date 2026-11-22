# Hardset Launch & Positioning Plan

An operational plan for launching Hardset on the iOS App Store, designed to be executed by a single developer with zero marketing budget.

---

## 1. The One-Sentence Pitch and the App Store Subtitle

### One-Sentence Pitch
> **Hardset is a local-only training log for evidence-based lifters that shows where every number comes from, separates history by physical machine, and refuses to invent estimates or targets when science has not settled them.**

This pitch defines the product's boundary immediately:
- **Audience:** Evidence-based lifters who distrust arbitrary app metrics and keep spreadsheets.
- **Differentiator:** Epistemic honesty (mathematical provenance and machine-level isolation).
- **Architecture:** Zero-cloud, local-first utility without feeds or accounts.

### App Store Subtitle (30-Character Limit)
Apple strictly limits the subtitle to 30 characters. The subtitle must be instantly readable to a lifter scrolling through search results on a phone screen:

| Candidate | Character Count | Verdict | Rationale |
| :--- | :--- | :--- | :--- |
| **`The log that won't lie to you`** | **29 / 30** | **Selected (Primary)** | Direct statement of the core positioning ruling (D16). Immediately arrests cynical lifters scrolling past generic "AI workout planner" apps. |
| `Honest, local-only workout log` | 30 / 30 | Alternate | Emphasizes privacy and local execution for lifters prioritizing data ownership. |
| `No feed. No guessing. Just log` | 30 / 30 | Alternate | Negative space framing that highlights the absence of bloat. |

**Selected Subtitle:** `The log that won't lie to you` (29 characters).

---

## 2. The First Three Screenshots

In the App Store gallery, a potential user grants roughly two seconds per card. Honesty cannot wait for card four; it must be proven in the first two screenshots, or the user leaves. 

All screenshots are presented in Hardset's high-contrast monochrome design system (canvas black `#050608`, chalk white `#F3F3F5`, plate-calibrated accents), with tabular numbers set in condensed typography.

### Screenshot 1: The Live Workout Session
- **Screen:** `WorkoutScreen` (Live Workout Session).
- **State:**
  - Movement: `Incline Chest Press` at `Gym A · Machine 1 (45° Plate-Loaded Sled)`.
  - Sets logged: Two working sets completed with plate-green check marks (`225 lb × 8` and `225 lb × 7`). Set 3 active on the gym-floor numeric pad.
  - Heading metadata: Tabular readout of estimated 1RM (`285 lb`) displaying the quiet provenance line: `Moderate confidence (from 8 reps) · Formula estimate, not measured single`.
  - Provenance caveat: Beneath the movement title, an inline disclosure states: `Different machine from Gym B · Load history not inherited`.
  - Pinned rest timer: Opaque panel displaying `01:42` remaining.
- **Caption:** `It tells you when it's estimating.`
- **What a stranger learns in two seconds:** This app does not pretend a 5-to-8 rep formula calculation is a measured 1-rep maximum. It tags the physical machine, rates its own certainty out loud, and refuses to inflate numbers to flatter the user.

### Screenshot 2: Volume Breakdown and Attribution
- **Screen:** `VolumeScreen` ("Where the work went").
- **State:**
  - Weekly volume ledger showing fractional attribution for recent training: Incline Bench Press contributes `1.0 set` to Chest, `0.5 set` to Front Delts, and `0.5 set` to Triceps.
  - Group-level counts: Displays `setsTouchingGroup` (`8 sets touch Chest`), preventing false triple-counting.
  - Transparent neglect: An explicit section reads: `Nothing logged for Rear Delts, Calves, Traps`.
  - Scientific disclosure footnote: Plain text citing the literature: `0.5 indirect credit is an adopted convention (Pelland et al.), not an inherited finding. Weekly target: Unevaluated.`
- **Caption:** `Shows its math. Refuses to invent targets.`
- **What a stranger learns in two seconds:** It does not manufacture arbitrary green progress bars or pretend to know individual biological recovery thresholds (MEV/MRV). It shows the exact fractional math, cites the research, admits when targets are scientifically unevaluated, and shows what was skipped.

### Screenshot 3: Equipment-Separated Progression
- **Screen:** `ProgressBoardView` (Progress Board).
- **State:**
  - Single card for `Leg Press` displaying two distinct, unmerged trend lines:
    1. `45° Incline Sled (Gym A)`: `+20 lb in 6 weeks · Moderate confidence`.
    2. `Horizontal Cable Sled (Gym B)`: `3 sessions over 2 weeks · No 6-week comparison (needs baseline)`.
  - Most improved ordering: Header states `Most improved · ranked by confidence first, then gain`.
  - Stalled lift disclosure: `Overhead Press · No record in 3 sessions` with neutral pause symbol (no patronizing automated deload advice).
- **Caption:** `Different machines. Never merged.`
- **What a stranger learns in two seconds:** Switching from a steep sled to a horizontal cable machine will never draw a fake personal record or false regression in the chart. Machine leverage is treated as a physical reality, not a naming mistake.

---

## 3. App Store Copy

### Short Description (Promotional Text — 170 Characters Max)
> A local-only training log for evidence-based lifters. Honest certainty on estimates, machine-separated history, and fractional volume math. No feeds. No subscriptions.
*(167 characters)*

---

### Long Description

**Most workout apps are built to flatter you or trap you in a social feed.**

They take an 8-rep set, run it through an ungrounded formula, and award a "1-rep max" trophy with absolute confidence. They merge a 45-degree leg press with a horizontal cable press into a single graph, manufacturing progress you never made. They show colorful volume bars claiming you hit your "optimal recovery target" based on uncited rules of thumb. Then they demand a $15/month subscription to view your own training history.

Hardset is built on a different thesis: **calibrated honesty.**

We built Hardset for intermediate and advanced lifters who keep spreadsheets, read the research, and want an instrument for the gym floor that refuses to guess.

#### 1. Calibrated Certainty
Every estimate in Hardset carries its epistemic confidence:
- A formula-derived 1RM caps at Moderate confidence. Only a measured single is High confidence.
- High-rep sets (above 10 reps) carry Low confidence because empirical variance is too wide to extrapolate accurately.
- When data is missing, Hardset reports "Unevaluated" rather than inventing a number.

#### 2. Machine-Level Provenance
A 200 lb leg press on a Cybex sled is not a 200 lb leg press on a Hammer Strength horizontal press. 
- Hardset tracks your training history keyed to `exercise × machine`.
- When you train at a different gym or use a different pin stack, Hardset records a separate series.
- Machine series are never merged into false progress curves or false regressions.

#### 3. Fractional Volume Attribution
Hardset attributes training volume based on empirical research (Pelland et al.):
- Prime movers receive 1.0 set credit; secondary compound contributors receive 0.5 set credit.
- Direct sets are never conflated with compound totals: group views count sets once per session to prevent triple-counting.
- We report weekly volume targets as Unevaluated because dose-response curves exist in the literature, but universal biological minimums do not.

#### 4. Your Data Never Leaves Your Phone
- **No account required:** Download and start logging immediately.
- **Zero cloud transmission:** Your workouts, notes, and gym profiles are saved locally in an on-device SQLite database.
- **No social feed:** No followers, no leaderboards, no community tabs, and no algorithmic distraction between sets.
- **Full export ownership:** Export your entire raw training history at any time as CSV, JSON, or SQLite files.

#### 5. Built for the Gym Floor
- High-contrast monochrome interface designed for bright overhead gym lighting and chalky fingers.
- Single-hand custom numeric keypad with direct weight-to-rep focus traversal and plate steppers.
- Opaque rest countdown timers backed by system dates that survive app backgrounding, screen locks, and process termination.
- Instant set logging with tactile haptic confirmation.

---

### What This App Is Not
- **Hardset is not a social network.** There are no profiles, likes, comments, activity feeds, or vanity badges.
- **Hardset is not an algorithmic coaching oracle.** It does not auto-regulate your routine, prescribe dogmatic deloads, or claim to calculate your exact biological recovery rate.
- **Hardset is not a cloud subscription service.** There are no monthly recurring fees, no locked history tiers, and no cloud databases holding your data hostage.

---

### Keywords & Rationale (100-Character Comma-Separated Limit)

**Search String:**
`workout log,hypertrophy,lifting log,strength,gym tracker,weightlifting,bodybuilding,rpe,rep max`
*(96 characters)*

#### Keyword Selection Rationale:
- `workout log`, `lifting log`, `gym tracker`: Core transactional search terms used by lifters searching for utility loggers rather than general fitness routines.
- `hypertrophy`: Filters specifically for lifters focused on muscle-building volume and attribution rather than casual cardio or step counting.
- `strength`, `weightlifting`, `bodybuilding`: Broad intent buckets that capture serious gym trainees looking for alternatives to bloated market leaders.
- `rpe`, `rep max`: Niche terminology used almost exclusively by intermediate-to-advanced lifters who track proximity to failure and estimated performance benchmarks.

---

## 4. Where the First 200 Users Come From

With zero advertising budget, early acquisition must rely on high-signal organic participation in communities of evidence-based lifters.

### 1. Target Communities

| Community | Platform | Audience Profile | Why They Care About Hardset |
| :--- | :--- | :--- | :--- |
| **r/naturalbodybuilding** | Reddit | Serious natural physique athletes tracking volume landmarks and exercise variations. | Frustrated by black-box volume apps; already track direct vs. indirect sets manually in spreadsheets. |
| **r/weightroom** | Reddit | Experienced lifters logging heavy compounds and multi-year training cycles. | Deep hatred for social feeds, buggy timers, and cloud subscription paywalls. |
| **Stronger By Science (SBS)** | Discord & Forum | Greg Nuckols / Eric Trexler community focused on scientific rigor and statistical nuance. | Value epistemic humility; appreciate explicit confidence ratings and cited literature. |
| **3D Muscle Journey (3DMJ)** | Community / Podcast Listeners | Lifters trained in RPE, volume dose-response, and progressive overload tracking. | Want machine-specific logging because they rotate gyms and understand mechanical differences. |
| **r/spreadsheets / Lifting Templates** | Reddit / Web | Lifters who refuse commercial apps and maintain complex Google Sheets. | Only an app that mirrors spreadsheet precision (machine isolation, raw exports) can convert them. |

---

### 2. Appropriate Posts and Comment Frameworks

#### Trigger 1: Lifters Complaining About App Paywalls and Feed Bloat
- **Context:** Threads where users discuss Hevy adding mandatory social features, Strong charging $99 or subscription tiers, or RP Hypertrophy pricing at $35/month.
- **Comment Framework:**
  > "I felt the same way about workout apps turning into social feeds or locking raw CSV exports behind $15/month subscriptions. I ended up building Hardset specifically to solve that: it's local-only (no cloud, no account, your data stays in an SQLite database on your phone), has no feed, and does one-tap logging. Core logging and history are completely free forever. Happy to share a link if you're looking for something stripped down."

#### Trigger 2: Lifters Discussing Different Machines and Pin Stacks
- **Context:** Discussions on why a 45° plate-loaded leg press doesn't match a horizontal cable press, or how gym changes mess up historical 1RM tracking.
- **Comment Framework:**
  > "Most apps flatten all leg presses into one exercise, which ruins your progressive overload data when you switch gyms. In Hardset, we keyed load history to `exercise × machine`. If you switch from a Cybex sled to a Hammer Strength press, it starts a separate series and refuses to draw fake progress between them. It also rates formula 1RM estimates as 'Moderate' or 'Low' confidence depending on reps. Built it for lifters who care about accurate data."

#### Trigger 3: Discussions on Volume Tracking and Research Methodology
- **Context:** Threads debating direct vs. indirect set counting (e.g., how much triceps credit a close-grip bench press gives).
- **Comment Framework:**
  > "We implemented fractional set attribution in Hardset based on the Pelland et al. meta-analysis (1.0 for prime movers, 0.5 for indirect secondary muscles). More importantly, we explicitly cite the methodology in the app and disclose that 0.5 is an adopted heuristic rather than an inherited biological absolute. We also leave weekly muscle targets as 'Unevaluated' because the literature shows a dose-response relationship, not a fixed universal floor."

---

### 3. The Ethical Line: What NOT To Do

> **The Single Rule: NEVER ASTROTURF.**

- **Strict Prohibition:** Never create sockpuppet accounts, never pose as a satisfied third-party user ("Hey, has anyone tried this cool app Hardset?"), never purchase fake reviews, and never incentivize deceptive ratings.
- **The Rationale:** In an evidence-based niche where the product's entire value proposition is **truthfulness and epistemic honesty**, being discovered in a single deceptive act or fake review would permanently destroy the brand's credibility.
- **Mandatory Disclosure:** In every forum, thread, or social interaction, explicitly declare developer status: *"I built Hardset..."* or *"Full disclosure: I am the developer of Hardset."*
- **Ask for Critique:** Frame community engagement as asking for rigorous technical teardowns of the math, muscle taxonomy, and UI ergonomics rather than begging for downloads.

---

## 5. The Launch Checklist in Order

Execution sequence required before publishing to App Store Connect.

### Phase 1: Legal & Public Infrastructure (Mandatory Before Submission)
- [ ] **Deploy dedicated static website:** Host on a clean, dedicated domain or subdomain (e.g., `hardset.app`), separate from the developer's WebGL portfolio (Ruling D6).
- [ ] **Publish Public Privacy Policy:**
  - Grounded in `docs/release/PRIVACY_POLICY_DRAFT.md`.
  - Disclose local-only data storage (no cloud database, no tracking SDKs, no third-party analytics).
  - Detail optional Apple Health integration and direct StoreKit 2 transaction verification.
  - Set public HTTPS URL in App Store Connect and in-app Settings link.
- [ ] **Publish Public Support Page:**
  - Grounded in `docs/release/SUPPORT_DRAFT.md`.
  - Provide a monitored support contact email address.
  - Detail critical data retention warning: deleting the app deletes the local database; users must export CSV/SQLite to maintain external backups.

### Phase 2: Hardware & Runtime Verification (Mandatory Before Submission)
- [ ] **Walk physical iPhone checklist (`docs/OWNER-DEVICE-CHECKLIST.md`):**
  - Walk the entire first-launch tour and Welcome bar on physical hardware under gym lighting.
  - Verify AlarmKit rest timers: Test delivery while locked, with app force-quit, under Focus modes, and during process restarts.
  - Test `ClankPlayer` haptic feedback: Confirm the transient `clank` feels like a physical iron plate meeting a barbell rather than a double buzz.
  - Verify keypad touch-down response with sweaty/chalky thumb interaction.
  - Validate accessibility rendering: VoiceOver and Dynamic Type across all five primary tabs (`docs/KNOWN-ISSUES.md`).

### Phase 3: Monetization & StoreKit Verification (Mandatory Before Submission)
- [ ] **Configure StoreKit 2 Non-Consumable Product:**
  - Product ID: `com.hardset.app.lifetime`.
  - Pricing: $19.99 launch tier (to be adjusted to $29.99 standing tier post-launch, per Ruling D17).
- [ ] **Sandbox Purchase Verification:**
  - Execute real StoreKit transaction in Apple Sandbox environment.
  - Test purchase success, user cancellation, deferred/family approval, and `AppStore.sync()` restore flow.
  - Verify offline launch with cached verified entitlement.
  - Confirm the feature gate boundary: deep muscle analysis over time unlocks; live logging, history, and raw data exports remain 100% free.

### Phase 4: App Store Connect Assets & Metadata
- [ ] **App Store Icon:** Final 1024×1024 px production asset reflecting the calibrated iron identity.
- [ ] **Production Screenshots:** Capture native 6.7" and 6.5" screenshots matching the exact 3-screen progression specified in Section 2.
- [ ] **App Store Connect Questionnaire:**
  - Age Rating: 4+.
  - App Privacy Nutrition Labels: Empty `NSPrivacyCollectedDataTypes` (no data collected or linked to user identity; optional local Health access declared).
  - Reviewer Notes: Document local-only operation, confirm no account registration is needed, and explain sandbox testing credentials.

### Phase 5: Post-Launch Deferrals (Can Wait for Future Updates)
- [ ] 150-movement catalogue expansion (v1 ships 50 rigorously attributed movements; expansion is additive post-launch, per D5/D19).
- [ ] CloudKit multi-device sync (explicitly deferred by D7/D18 until two-device conflict resolution is proven on physical hardware).
- [ ] In-app database restore from export files (CSV/SQLite exports serve as human-readable archives in v1).
- [ ] Interactive web landing page with video demonstrations.

---

## 6. The Honest Risks and Reviewer Responses

Every architectural tradeoff carries an honest objection. These are the four primary risks, along with the exact responses to provide if raised by an App Store reviewer, journalist, or prospective user.

### Risk 1: Local-Only Storage (No Automatic Cloud Backup)
- **The Objection:** *"If I lose or break my phone, all my workout history is gone."*
- **The Honest Response:**
  > "Hardset stores all workout data exclusively on your device with no cloud account, meaning your training privacy is absolute and your log works without cell service, but you must use the built-in CSV, JSON, or SQLite exports or standard iOS device backups to protect your history."

### Risk 2: Small Exercise Catalogue (50 Movements in v1)
- **The Objection:** *"Competitors have 2,000 exercises. Hardset only has 50."*
- **The Honest Response:**
  > "We ship 50 fully researched, anatomically cited movements rather than thousands of unvetted duplicates, and you can add any custom exercise with your own primary and secondary muscle attribution in two taps."

### Risk 3: No Multi-Device Sync
- **The Objection:** *"I log workouts on my iPhone, but I want to review my progress on an iPad."*
- **The Honest Response:**
  > "Version 1 does not sync across devices because we refused to rush multi-device replication before proving zero data-loss reliability on a single phone; seamless, conflict-free sync is being engineered as a future update without compromising local logging speed."

### Risk 4: Upfront Price ($19.99 Launch / $29.99 Standing Lifetime)
- **The Objection:** *"Why pay $20 to $30 upfront for a local-only app when Hevy is free to download?"*
- **The Honest Response:**
  > "Hardset is a one-time purchase with no recurring subscriptions, no ads, and no selling of your data, priced to sustainably support independent software while keeping core logging, personal history, and raw data exports completely free forever."
