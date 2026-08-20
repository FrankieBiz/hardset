# Hardset Muscle Taxonomy — Buildable Specification v1

**Status:** ratified against four research streams plus four audit passes. Where an audit refuted a claim, this spec follows the correction and states the refutation so it cannot be re-litigated from the original stream text. Where nothing verified a split, this spec says so rather than shipping it silently.

**Scope of permanence.** The frozen artefacts are the column *name* and *type* (`exercises.primaryMuscle TEXT`, `exercises.secondaryMusclesJSON TEXT`, Migrations.swift:102–103) — SQLiteData's permanently disallowed changes are exactly three: removing columns, renaming columns, renaming tables (`.build/checkouts/sqlite-data/Sources/SQLiteData/Documentation.docc/Articles/CloudKitSync.md:455-459`). Nothing constrains the set of string *values* a TEXT column may hold, nor the grammar of JSON inside one. So: **adding a token later is permitted and cheap; renaming or removing one is permanently impossible from the first build that reaches a second device.** Nothing has shipped yet, so today every literal in `ExerciseCatalog.swift` is still free to change.

---

## 1. THE VOCABULARY

**22 tokens.** `lowerCamelCase`, ASCII letters only, no digits, no separators. Plus one reserved non-token sentinel, `unknown`.

camelCase is a **choice, not a constraint** — the audit refuted "forced by 50 rows already on disk": nothing has shipped, and the 50 values live as source literals. It is chosen because all 16 muscle strings currently in the seed are already camelCase, five of them multi-word (`upperBack`, `lowerBack`, `frontDelts`, `sideDelts`, `rearDelts`), making camelCase the only option with a near-identity migration. The codebase carries two value conventions **on purpose**: kebab-case identifies movements (`slug: "barbell-back-squat"`, ExerciseCatalog.swift:18), camelCase identifies muscles.

Tiers are **two**, not three. The three-tier CORE/ADVISORY/JOINT-HEALTH structure was refuted as internally contradictory. `modelled` and `counted` replace it:

- **`modelled`** — the token's meaning matches one-to-one a site measured as a hypertrophy outcome in Pelland et al.'s corpus, so a weekly fractional count sits inside the range the published dose-response was fitted on. Six tokens.
- **`counted`** — real token, real attribution, credited at full fractional weight, shown as a number and as present/absent. Never placed on a dose-response curve, never compared to a target. Sixteen tokens.

| # | raw value (permanent) | display name | group | tier | justification |
|---|---|---|---|---|---|
| 1 | `chest` | Chest | chest | modelled | Pelland measured site (pectoralis major). Regional split rejected — see §2.1. |
| 2 | `frontDelts` | Front delts | shoulders | modelled | Pelland measured site (anterior deltoid); Table 1 lists it *direct* for barbell shoulder press, *indirect* for bench press. |
| 3 | `sideDelts` | Side delts | shoulders | counted | Ground B (below): a lateral raise applies essentially no moment about the anterior or posterior deltoid's line of action. No three-arm head-specific trial exists. |
| 4 | `rearDelts` | Rear delts | shoulders | counted | Ground B, same argument. This is the most common real coverage gap in pressing-heavy programs. |
| 5 | `rotatorCuff` | Rotator cuff | shoulders | counted | One token, not four. Cuff hypertrophy evidence in healthy people is a BFR case series and a preliminary isokinetic study; no controlled dose-response. |
| 6 | `lats` | Lats | back | counted | Ground B (humeral shoulder extension/adduction vs scapular retraction). No hypertrophy trial dissociates lat growth from rhomboid/mid-trap growth; NCT07360236 registered, unreported. |
| 7 | `upperBack` | Upper back | back | counted | Ground B (scapular retraction/depression). Owns rhomboids, **middle and lower** trapezius, teres. Narrower than Pelland's "trapezius" site, so not modelled. |
| 8 | `traps` | Traps | back | counted | Ground B (scapular elevation). Upper trapezius **only**. Already a distinct live value in the seed (ExerciseCatalog.swift:422 vs :270). Narrower than Pelland's trapezius site. |
| 9 | `lowerBack` | Lower back | back | counted | Erector spinae. Pelland never measured erector spinae; no trial establishes hinge-driven lumbar hypertrophy either way (§10). |
| 10 | `biceps` | Biceps | arms | modelled | Pelland measured site (biceps brachii / elbow flexors). Head and brachialis splits rejected — §2.4. |
| 11 | `triceps` | Triceps | arms | modelled | Pelland measured site (triceps brachii / elbow extensors). Long-head split rejected — §2.2. |
| 12 | `forearms` | Forearms | arms | counted | Direct only where wrist flexion/extension or radioulnar rotation is the loaded action. Grip is `stabilizer` — §5. |
| 13 | `abs` | Abs | core | counted | Ground B (trunk flexion). No trained-lifter trial separates rectus abdominis growth by exercise selection. |
| 14 | `obliques` | Obliques | core | counted | Ground B (trunk rotation / lateral flexion). **Not established by outcome evidence** — no trial found. Ships as a coverage-presence token only. |
| 15 | `neck` | Neck | neck | counted | No dissociation evidence. Exists so neck work is not mis-filed onto `traps`, which is where both predecessor apps put it. Authoring-correctness token, not a dose claim. |
| 16 | `quadriceps` | Quads | legs | modelled | Pelland measured site (quadriceps / knee extensors); Table 1 makes leg press, hack squat, Smith squat, lunge and split-squat variants all *direct* for quadriceps. |
| 17 | `hamstrings` | Hamstrings | legs | modelled | Pelland measured site (hamstrings / posterior thigh). Head split rejected — §2.5. |
| 18 | `glutes` | Glutes | glutes | counted | Kubo 2019: gluteus maximus volume +6.7 ± 3.5% (full squat), +2.2 ± 2.6% (half). Pelland never measured glutes, so **neither** 1.0 nor 0.5 has corpus support for them. |
| 19 | `adductors` | Adductors | legs | counted | Kubo 2019: adductor volume +6.2 ± 2.6% (full) / +2.7 ± 3.1% (half). Plotkin 2023: adductor growth superior with squat (2.5 ± 0.7 cm²). No published weekly-set landmark. |
| 20 | `hipAbductors` | Hip abductors | legs | counted | Plotkin 2023 measured gluteus medius + minimus as a **single combined mCSA**, so the pair is the honest granularity; `gluteMedius` would claim resolution the measurement did not have. |
| 21 | `gastrocnemius` | Gastrocnemius | legs | counted | Kinoshita 2023: standing vs seated calf raise, lateral gastroc +12.4% vs +1.7%, medial +9.2% vs +0.6% (both n.s. seated, p = 0.147–0.508). A true dissociation. |
| 22 | `soleus` | Soleus | legs | counted | Kinoshita 2023: grew significantly in **both** legs (2.1% standing vs 2.9% seated, p = 0.410). The non-dissociating sibling — which is exactly why it is not split further. |

**The reserved sentinel.** `"unknown"` is not a `Muscle` case and never will be. It is already a live value: `"primaryMuscle" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'unknown'` (Migrations.swift:102), mirrored at Schema.swift:22. Any insert omitting the column, including a peer record arriving without the field, produces it. It displays as **"Not attributed"**, counts nowhere, and a test asserts no `Muscle` raw value equals it.

**Groups (8, derived in code, never stored):** `chest {chest}`; `shoulders {frontDelts, sideDelts, rearDelts, rotatorCuff}`; `back {lats, upperBack, traps, lowerBack}`; `arms {biceps, triceps, forearms}`; `core {abs, obliques}`; `neck {neck}`; `legs {quadriceps, hamstrings, adductors, hipAbductors, gastrocnemius, soleus}`; `glutes {glutes}`. 1+4+4+3+2+1+6+1 = 22.

### The two admission grounds (write these into the file's doc comment)

A token is admissible only on one of two grounds, and the spec records which.

- **Ground A — dissociation.** A common exercise gives one sibling essentially nothing while giving the other a lot, demonstrated by a *hypertrophy outcome measurement* (not activation). Tokens: `gastrocnemius`/`soleus` (Kinoshita 2023), `hipAbductors` (Plotkin 2023).
- **Ground B — disjoint loaded joint action.** Two tokens are loaded by joint actions in different planes, such that a movement resisting one applies essentially no resistance to the other's action. This is an argument from the direction of the resistance and moment arms, **not** from a trial. It is honest as a *coverage* claim ("does this program contain any work that resists this action?") and is **not** a dose-response claim. Tokens: the three delt heads, `lats`/`upperBack`/`traps`, `abs`/`obliques`, `adductors`.

**Ground B attributions may never carry `.high` certainty**, and the user-facing evidence copy must say "justified by the direction of the resistance, not by a head-specific dose-response trial."

### Why 22 and why not finer

Every finer split proposed in the research fails on one of three things: (a) it is a **magnitude** difference where the disfavoured condition still grew the tissue substantially — triceps long head, rectus femoris, hamstring heads, biceps heads; (b) its boundary is a **continuous parameter** an author must estimate per entry — bench angle, hip angle, ROM; (c) it has **no outcome evidence at all** — lower trapezius, serratus, tibialis, ab regions, glute regions. Each finer split also multiplies the ~240-entry authoring judgement, which is the binding constraint (260–340 hours, not yet done).

### Why not coarser

The fractional-credit feature requires the indirect credit to land somewhere meaningful. Hevy's live spec enumerates exactly 20 muscle-group values — `abdominals, shoulders, biceps, triceps, forearms, quadriceps, hamstrings, calves, glutes, abductors, adductors, lats, upper_back, traps, lower_back, chest, cardio, neck, full_body, other` (`https://api.hevyapp.com/docs/swagger-ui-init.js`, MuscleGroup schema, fetched 2026-08-20) — with no delt-head value, so an overhead press's 0.5 anterior-deltoid credit lands in the same bucket that absorbs every side and rear delt set. That is the resolution floor, and it is the reason for defining our own vocabulary rather than adopting Hevy's.

**Drawability is not a reason for stopping at 22 and must not be cited as one.** wger already ships highlight art for Serratus anterior (id 3) and Brachialis (id 13), neither a surface silhouette region (`https://wger.de/api/v2/muscle/?format=json&limit=100`, fetched 2026-08-20). A body map is a stylised diagram with conventional regions. Keep `isDrawable` as a rendering flag (false for `rotatorCuff`; re-examine `upperBack` and `lowerBack`, which are deep to trapezius and lats and no more distinct than the cuff), and delete the "drawability ceiling coincides with the literature" argument entirely.

---

## 2. REJECTED SUBDIVISIONS

Each rejection states the **evidence status of the claim being rejected**, so it can be quoted back.

**2.1 `upperChest` / `lowerChest` — REJECTED. Status: single unreplicated trial; everything else is EMG.**
The only outcome trial is Chaves SFN et al., *Int J Exerc Sci* 2020;13(6):859-872 — n=47 **untrained** men, 8 weeks, **one session per week**, ultrasound thickness; incline-only gained more at the 2nd intercostal space (mean diff 0.62 cm [0.23, 1.0] vs horizontal, p=0.003). Everything else supporting "incline targets the clavicular head" is activation work. No audit verified a 2020–2026 primary source adequate to support per-region set counting; stream 4's own risk register concedes this. The boundary is a continuous bench angle — is a 30° machine press "upper"? — forcing an angle judgement on ~35 pressing entries, the highest-volume authoring judgement available. Splitting also breaks comparability with every whole-pectoralis measurement in the literature. Regional emphasis, if the product wants it, is the exercise attribute `pressAngle`.

**2.2 `tricepsLongHead` / `tricepsLateralMedial` — REJECTED. Status: real, well-conducted trial; magnitude, not dissociation.**
Maeo S et al., *Eur J Sport Sci* 2023;23(7):1240-1250, DOI 10.1080/17461391.2022.2100279, PMID 35819335 — n=21, within-subject, MRI volume, 12 weeks, 5×10 at 70% 1RM. Long head **+28.5% overhead vs +19.6% neutral** (1.5-fold); whole triceps +19.9% vs +13.9%. The number that decides the taxonomy is the **19.6%**: the disfavoured condition still grew the long head substantially. Contrast Kinoshita's calf case, where the disfavoured condition produced 0.6–1.7%, non-significant. This is the internal standard that also rejects `rectusFemoris`. Encoded as the exercise attribute `shoulderPosition: overhead | neutral | extended`, driving the tip "no overhead triceps work this week."

**2.3 `rectusFemoris` — REJECTED. Status: both supporting claims refuted by audit.**
- The leg-extension hip-angle study is a **magnitude** difference, not a dissociation. Larsen S, Sandvik Kristiansen B, Swinton PA, Wolf M, Bao Fredriksen A, Nygaard Falch H, van den Tillaar R, Osteras Sandberg N. "The effects of hip flexion angle on quadriceps femoris muscle hypertrophy in the leg extension exercise." *J Sports Sci* 2025;43(2):210-221. DOI 10.1080/02640414.2024.2444713, PMID 39699974. n=22 untrained men, within-participant, 10 weeks. Rectus femoris grew in **both** conditions at **both** sites: proximal +12.4% (40°) vs +4.6% (90°), BF>100; distal +15.8% vs +10.9%, **BF = 88.4** (not >100 — the research's "BF>100 at both sites" is false). Vastus lateralis: strong evidence of no difference (BF = 0.07). Results, verbatim: "Increases in muscle thickness were observed at both regions for the rectus femoris and vastus lateralis across both the 40 and 90 degree conditions." A 1.45× distal ratio is arithmetically the same shape as Maeo's triceps result and must receive the same verdict. It belongs on the exercise as `hipPosition: flexed | neutral | extended`.
- The squat claim is an **underpowered null**. Kubo K, Ikebukuro T, Yata H. *Eur J Appl Physiol* 2019;119:1933-1942. DOI 10.1007/s00421-019-04181-y. **Seventeen** men randomised *between* groups: full squat n=8, half squat n=9. Verbatim: "the volumes of rectus femoris and hamstring muscles did not change in either group." Power > 0.8 is reported only for the significant changes. The defensible statement is "rectus femoris was the one knee extensor that did not measurably grow after 10 weeks of squat training in a small trial" — **not** "squats do not grow the rectus femoris."

With both claims reduced, no evidence licenses the token. Consequently **`quadriceps` means the whole quadriceps femoris**, one token, no children — which is also what makes it match Pelland's measured site exactly.

**2.4 `bicepsLongHead` / `bicepsShortHead` / `brachialis` — REJECTED. Status: the cited trial cannot separate them.**
The 2025 incline-vs-preacher curl trial (*Int J Sports Med*, DOI 10.1055/a-2517-0509) found proximal thickness +11.2% incline vs +8.3% preacher and distal +10.3% preacher vs +6.4% incline, but measured the **elbow-flexor compartment collectively** by ultrasound. "Preacher curls build the brachialis" is an inference, not a result. No trial separating biceps long head from short head by exercise selection was found. Pelland's own site is "biceps brachii/elbow flexors," so lumping matches the corpus. Elos reached this conclusion expensively: it authored `brachialis` (MuscleTaxonomy.swift:118) then discarded it into `.biceps` (:142).

**2.5 `bicepsFemoris` / `medialHamstrings` — REJECTED. Status: real evidence, fully carried by an exercise attribute.**
Bourne MN et al., *Br J Sports Med* 2017;51(5):469-477, DOI 10.1136/bjsports-2016-096130, PMID 27660368 — Nordic training preferentially grew semitendinosus and biceps femoris short head; hip-extension training produced greater biceps femoris long-head growth. That is a knee-flexion vs hip-extension **pattern** contrast, so `pattern: kneeFlexion | hipExtension` carries 100% of the actionable content ("you have no knee-flexion hamstring work") with zero new tokens. Maeo S et al., *Med Sci Sports Exerc* 2021;53(4):825-837, DOI 10.1249/MSS.0000000000002523 — seated beat prone for all three biarticular heads in the same direction; magnitude, so `hipPosition`. This is the closest call in the set and is recorded as such.

**2.6 `gluteMaxUpper` / `gluteMaxLower` — REJECTED. Status: the flagship contrast produced no regional dissociation.**
Plotkin DL, Rodas MA, Vigotsky AD, McIntosh MC, Breeze E, Ubrik R, et al. "Hip thrust and back squat training elicit similar gluteus muscle hypertrophy and transfer similarly to the deadlift." *Front Physiol* 2023;14:1279170. DOI 10.3389/fphys.2023.1279170, PMID 37877099, PMC10593473. Verbatim: estimates "modestly favored the HT versus SQ for lower [-1.6 ± 2.1 cm²; CI95% (-6.1, 2.0)], mid [-0.5 ± 1.7 cm²] and upper [-0.5 ± 2.6 cm²] gluteal mCSAs but with appreciable variance." Variance, not a dissociation.

**2.7 `lowerTraps`, `rhomboids`, `midTraps`, `teresMajor` — REJECTED. Status: no outcome trial isolates any of them.**
No hypertrophy outcome trial isolating lower trapezius growth by exercise selection was found; nor for rhomboids or mid-traps separately from each other. They fail Ground A (no dissociation measurement) and Ground B (all produce scapular retraction/depression in the same plane — they are not disjoint actions). Elos authored `lower_traps` and `rhomboids` and then discarded both into `.upperBack` (MuscleTaxonomy.swift:117, :136). **Note on the rejection reasoning:** the "too few credited exercises to ever fill a bar" argument is *not* used here. That floor is stated in §3 as applying only to score-gating tokens, and v1 has none — so `lowerTraps` is rejected on evidence, and `neck` survives on the authoring-correctness ground stated in §1.

**2.8 `serratusAnterior`, `tibialisAnterior` — REJECTED. Status: no dissociation evidence, no landmark.** Explicitly *not* rejected on drawability — wger draws serratus.

**2.9 `upperAbs` / `lowerAbs` — REJECTED. Status: within-head region, no outcome evidence, boundary not nameable.**

**2.10 `hipFlexors` — REJECTED. Status: exercise set overlaps `abs` almost perfectly.** A hanging leg raise is both. Elos's handling is the warning: `hip_flexors` originally hit a generic `contains("hip")` test and classified leg raises as **glutes**, requiring a special case at MuscleTaxonomy.swift:148-150.

**2.11 Individual cuff muscles, and internal vs external rotators — REJECTED.** Evidence is a BFR case series (infraspinatus +11.7%, ES 0.46) and a preliminary isokinetic study. Elos authored `external_rotators` and `internal_rotators`, which previously returned nil and made 7 seeded exercises invisible to every scorer (MuscleTaxonomy.swift:116, :140, :196-200).

**2.12 `gluteMedius` separate from `gluteMinimus` — REJECTED.** Plotkin measured them as one combined mCSA. `hipAbductors` is the granularity the measurement supports.

**2.13 Keeping `calves` undivided — REJECTED (this is an accepted split, listed here because it is the one the research originally recommended merging).** Kinoshita M, Maeo S, et al. *Front Physiol* 2023;14:1272106, PMC10753835. Within-subject contralateral-limb allocation, n=14 untrained young adults, MRI volume, 12 weeks, 2×/wk, 70% 1RM, 5×10. Verbatim: "The changes in muscle volume were significantly greater for the standing than seated condition leg in the lateral gastrocnemius (12.4% vs. 1.7%), medial gastrocnemius (9.2% vs. 0.6%), and whole triceps surae (5.6% vs. 2.1%) (p ≤ 0.011), but similar between legs in the soleus (2.1% vs. 2.9%, p = 0.410)." Under one `calves` token a seated-only lifter is told calves are covered while the gastrocnemius received a non-significant 0.6–1.7% — the exact false-negative the taxonomy exists to prevent. Attribution is free: knee-extended vs knee-flexed is in the exercise name.

**2.14 A muscle-length / ROM field, a "trains at long length" badge, or a length-based volume multiplier — REJECTED.**
Gschneidner D, Carlson L, Steele J, Fisher J. "The effects of lengthened-partial range of motion resistance training of the limbs on arm and thigh muscle area: A multi-site randomised trial." *J Sports Sci* 2025;43(23), DOI 10.1080/02640414.2025.2567805 (preprint SportRxiv 485). Across **15 training sites** (not 15 measurement sites), 12 weeks, lpROM n=163 vs fROM n=134: arm -0.032 [95%CI -0.123, 0.058]; thigh 0 [95%CI -0.094, 0.094]. **The equivalence test was met for thigh (p=0.019) and NOT for arm (p=0.071)** — the research's "reported statistical equivalence" for both sites is an over-read in the direction it wanted. Combined with the pre-registered null of Wolf et al., *PeerJ* 2025;13:e18904, DOI 10.7717/peerj.18904, PMID 39959841, the practical reading is that any lengthened-partial advantage is small — and there is no validated scale on which an author could score "length" for an arbitrary movement. Length lives in the author's reasoning, exactly as Pelland used it to classify rectus femoris as indirect on squats.

---

## 3. THE ROLLUP, AND THE SUMMING RULE

**Three quantities, three names, and they may never be conflated.**

| name | definition | may be compared to a target? |
|---|---|---|
| `hardSets` | count of distinct logged **working** sets (whole numbers, `isWarmup == false`) | no target exists; it is a workload figure |
| `fractionalSets(for: MuscleKey)` | Σ over logged sets of `SetCounting.weight(role)` for that one muscle | **yes — this is the only quantity that may ever be placed on a dose-response curve or compared to a band** |
| `setsTouching(group:)` | count of **distinct logged sets** crediting at least one member muscle of the group; each physical set counted exactly once | no |

### The rule

> **Fractional credits are a per-muscle accounting. They may never be summed across different muscles, at any level of the hierarchy — not at the group level, not at the whole-body level, not across a parent and its children.**

The cause is summing across muscles, **not** the coarse level and **not** compound movements. Worked example, verbatim from the seed: barbell-row is `primaryMuscle: "upperBack"` with secondaries lats, biceps, rearDelts, lowerBack (`Sources/HardsetCore/ExerciseCatalog.swift:265-272`). One set credits upperBack 1.0 + lats 0.5 + rearDelts 0.5 + lowerBack 0.5 = **2.5 "back sets" from one physical set**. The same set also adds biceps 0.5 to `arms`, so any whole-body total is inflated too — and a single-secondary isolation movement double-counts by 1.5× at the whole-body level. The problem is not compounds.

Secondly, and independently: every dose-response model in the literature is fitted **per measured muscle**. There is no weekly-set relationship for "back," "legs" or "arms," so even an arithmetically clean group sum would be uninterpretable.

### What a group *may* expose

`MuscleGroupStatus` holds `members: [MuscleVolume]`, `withDirectWork: Int`, `withAnyWork: Int`, `withNoWork: Int`, and `setsTouching: Int`. It has **no** `totalSets` member and no `fractionalSets` member — the absence is the enforcement. If one headline number per group is wanted, it is `setsTouching`, labelled "sets that touched this area," never "sets."

Bands, gap warnings and balance verdicts are **per-muscle only**.

### The credited-exercise-set floor

A token whose direct-credit exercise set is a tiny fraction of the catalogue reads zero permanently. **This floor applies only to tokens that gate a coverage score.** v1 has no score-gating tokens (§1: no bands exist), so the floor rejects nothing in v1. It is stated here because it becomes live the moment a band is defended, and because it is the reason `neck`, `obliques`, `hipAbductors`, `adductors` and `rotatorCuff` are `counted` rather than score-gating. Enforcement is the shrinking `unauthoredDirectSlots` allowlist (§8, test 14), not silent rejection.

---

## 4. FORWARD COMPATIBILITY

An unknown token is a token a newer Hardset authored and this build has never heard of. It arrives via CloudKit on a row synced from a peer.

### 4.1 Storage: byte-preserved, always

`Exercise.primaryMuscle` and `Exercise.secondaryMusclesJSON` **stay typed `String`** on the table type (Schema.swift:22-23), and **no `@Column(as:)` is ever applied to either**. This is the enforceable rule, and it is not the same as "keep `Muscle` non-Codable."

The audit refuted the belief that withholding `Codable` closes the throwing path. SQLiteData rows are decoded by StructuredQueriesCore, which decodes any `RawRepresentable` through `init?(rawValue:)` and throws `DataCorruptedError()` when it returns nil (`.build/checkouts/swift-structured-queries/Sources/StructuredQueriesCore/QueryDecodable.swift:171-180`; `.../QueryRepresentable/RawRepresentable.swift:58-64`). Because `String` is both `QueryBindable` (QueryBindable.swift:58) and `QueryDecodable` (QueryDecodable.swift:41), the `Muscle.RawRepresentation` typealias exists for any String-raw enum **with no conformance added at all** — so `@Column(as: Muscle.RawRepresentation.self) var primaryMuscle: Muscle` would compile today and throw on an unfamiliar token.

`Muscle` is still declared without `Codable` as defence in depth (a synthesized `Decodable` on a raw-value enum throws `DecodingError.dataCorrupted` on an unfamiliar string; adding an `unknown` case does not change that; `@frozen` is irrelevant and the compiler warns it has no effect on non-public enums). But the test that matters writes a row containing an unfamiliar token, reads it back through the real `Exercise` query path, and asserts the read succeeds and the bytes are unchanged.

### 4.2 The boundary type is a **struct**, not an enum

`MuscleKey { case known(Muscle); case unrecognized(String) }` was refuted: Swift has no per-case access control, so `MuscleKey.unrecognized("chest")` is constructible by any caller, is a *distinct* `Hashable` value from `.known(.chest)`, and returns the identical `storedValue`. Demonstrated: a `[MuscleKey: Double]` map fed `MuscleKey(stored: "chest") += 3` and `.unrecognized("chest") += 2` ends with **two buckets** — `known(chest) = 3.0` and `unrecognized("chest") = 2.0` — while the grand total still reconciles, so the totals-reconcile test passes and the per-muscle bars are wrong. Same failure class as Elos's split-bucket bug.

With a private stored `String` and a single public initialiser, **one token can only ever produce one key.**

### 4.3 Behaviour of an unknown token, exactly

1. **Stored:** byte-identically, forever. `MuscleKey(stored:)` does no normalisation — no trimming, no case folding, no Unicode normalisation. Verified lossless for known keys, v2-only keys, the empty string, the reserved sentinel, case variants, whitespace-padded input, non-ASCII and embedded NUL.
2. **Displayed:** never as the raw key. `"unknown"` → "Not attributed". Any other unrecognised string → "Not recognised". Both via String Catalog keys (`muscle.notAttributed`, `muscle.notRecognised`). `ExercisePickerView.title(for:)`'s `default: muscle.prefix(1).uppercased() + muscle.dropFirst()` branch (ExercisePickerView.swift:131) is **deleted** — it is a fallback that looks like a real label, and it currently produces the user-facing labels for chest, quadriceps, biceps, triceps, hamstrings, forearms, calves, traps and glutes.
3. **Counted:** into its own bucket in the `[MuscleKey: Double]` volume map. The sets are real work and appear in `hardSets` and in the session. The bucket renders one row: "Not recognised — N sets on M movements. Update Hardset." It contributes to no band, no group and no coverage statement.
4. **Effect on other numbers:** every known-muscle count for a period containing an unrecognised token renders as **"≥ N sets"**, and that period's per-muscle volume `Claim`s are combined with a `.low` input (so a `modelled` muscle's certainty drops from `.moderate` to `.low`). Presence statements ("this muscle has direct work") remain valid — an unknown token can only add credit this build cannot see. The period's coverage readout is **not** blanked. Stream 3's proposal to force the whole period to `Claim.unevaluated` is rejected as disproportionate by its own risk register: one v2-authored movement in a thirty-movement week must not dark-screen the flagship feature.
5. **Never rewritten.** Field-wise last-edit-wins has no notion of which version is more informed (`CloudKitSync.md:461-473`). If a v1 device reads `primaryMuscle = "adductorMagnus"`, fails to recognise it, and writes back `"unknown"` during any unrelated edit — a rename, an archive, a machine binding — that write carries a newer per-column timestamp and **wins**, and the newer device's attribution is gone from every device and from iCloud. **Hard rule, test-enforced: the two attribution columns are byte-preserved by every write path that does not explicitly intend to change attribution.**

### 4.4 Read path and the seeder

`CatalogSeeder.seed` currently rewrites attribution on **every launch** unconditionally (`Sources/HardsetStore/CatalogSeeder.swift:61-70`: `$0.primaryMuscle = #bind(entry.primaryMuscle)`, `$0.secondaryMusclesJSON = #bind(secondaryJSON)`), while its comment at :59-60 deliberately preserves `name`, `notes` and `isArchived` as "the user's." Under field-wise last-edit-wins a v1 and a v2 device would overwrite each other's attribution on every launch forever, burning CloudKit quota and making the volume readout depend on which phone was opened last.

Fixed rules:

- **Write** `primaryMuscle` / `secondaryMusclesJSON` **only on insert**, or when the stored value is empty or equals the reserved `"unknown"`.
- **Read**, for a curated row whose `catalogSlug` this build knows: the **bundled catalogue**. The columns are a snapshot that exists so a future build (and a peer) can read a movement this build has never heard of. This is what lets a v2 attribution correction reach every v2 device without a rewrite war.
- **Read**, for a slug this build does not know: the columns.
- **Never prune** rows whose slug is absent from the local catalogue. That is what lets a v2 device introduce curated movements a v1 device can still see and log.
- Consequence, stated honestly: two builds can report different counts for the same history. That is version skew, self-consistent per build, and vastly preferable to the ping-pong.

### 4.5 The JSON grammar — and why it must ship in v1

`secondaryMusclesJSON` is `TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '[]'` on a STRICT table (Migrations.swift:103), and the Swift property is a bare `var secondaryMusclesJSON = "[]"` (Schema.swift:23) with no `@Column(as:)`. The frozen artefact is the column name and type; **the grammar of the text inside it is not schema.** SQLiteData's permanently disallowed changes are exactly three and none of them constrains string values.

Permanent grammar — an array of objects:

```json
[{"muscle":"quadriceps","role":"direct","certainty":"moderate","source":"anatomy"},
 {"muscle":"glutes","role":"direct","certainty":"moderate","source":"convention",
  "citation":"Hardset convention; see MuscleAttribution.md §5.6"},
 {"muscle":"adductors","role":"indirect","certainty":"moderate","source":"trial",
  "citation":"Kubo 2019, DOI 10.1007/s00421-019-04181-y"},
 {"muscle":"abs","role":"stabilizer","certainty":"moderate","source":"anatomy"}]
```

The array is the **complete** contribution list, including the display primary at `role: "direct"`. `primaryMuscle` is a denormalised display/sort key (the picker sections on it — `Dictionary(grouping: entries, by: \.primaryMuscle)`, ExercisePickerView.swift:109 — so it must stay single-valued). The column's name says "secondary"; its contents are the whole list. That is deliberate, the name is frozen, and the property's doc comment must say so.

**This grammar must ship in v1, before any build reaches a second device.** The current reader is `(try? JSONDecoder().decode([String].self, from: Data(row.secondaryMusclesJSON.utf8))) ?? []` (CatalogSeeder.swift:126-129), and a `[String]` decode throws on the **whole array** for one non-string element — so it returns `[]`. A build shipped with the bare-array reader would read every later object-grammar row as *no secondaries at all*, silently zeroing every indirect credit, permanently for those installs. "Not a schema change" is not the same as "compatible."

### 4.6 The tolerant decoder — exact contract

```swift
public struct DecodedAttribution: Hashable, Sendable {
  public let contributions: [MuscleContribution]
  /// Elements that could not be read at all. A caller that discards this field is a test failure.
  public let unreadableEntryCount: Int
  /// Fields that were present but unparseable and fell back to a default.
  public let degradedFieldCount: Int
}
```

Parsed with `JSONSerialization` (not `JSONDecoder`) because element-wise salvage requires it. In order:

1. Root parse fails → `contributions: []`, `unreadableEntryCount: 1`. **Never `?? []` silently.**
2. Root is not an array → `contributions: []`, `unreadableEntryCount: 1`.
3. Element is a `String` → `MuscleContribution(key: MuscleKey(stored: s), role: .indirect, certainty: .low, sourceID: "legacy-bare-array", citation: nil)`. Accepting the bare form keeps user-created rows and CSV imports cheap. It is **never written**.
4. Element is a dictionary with a `String` value at `"muscle"` → build the contribution. `role` missing → `.indirect`; unknown `role` string → `.indirect`, `degradedFieldCount += 1`. `certainty` missing or unknown → `.low`, `degradedFieldCount += 1`. `source` missing → `"unspecified"`. An **unknown source id is kept as a string, not rejected** — a v2 source id must survive a v1 read. Unknown object fields ignored.
5. Any other element → `unreadableEntryCount += 1`.
6. Duplicate muscle keys inside one array → keep the highest-weight role (`direct` > `indirect` > `stabilizer`), `degradedFieldCount += 1`. This is the second guard against one muscle occupying two buckets.
7. Encoding always emits the object grammar, elements ordered by `Muscle.allCases` declaration order.

The decoder is only safe **because** it reports what it could not read. If any caller drops `unreadableEntryCount`, the decoder is strictly worse than the strict one it replaced, because it hides failures instead of throwing them. Test 15 enforces that.

### 4.7 Adding a token later

Permitted and cheap. The cost is precisely: installs that never update see `≥ N` lower bounds and a "Not recognised" row for movements crediting the new token, forever, because the older build's parsing is the constraint and there is no server-side backfill. That asymmetry — additive is easy, rename is impossible — is the single fact a future contributor most needs and is least likely to infer from the code. It goes in `DECISIONS.md` verbatim.

---

## 5. THE ATTRIBUTION RULE (paste-ready for the contributor guide)

> ### HARDSET MUSCLE ATTRIBUTION RULE — v1
>
> Every catalogue entry names its contributing muscles from the 22-token vocabulary in `MuscleTaxonomy.swift`. Each name carries a role, a certainty and a source. Work the gates in order. If a gate fails, stop — do not round up.
>
> **Lookup budget.** Four gates are mechanical and need no literature. Two do: the outcome override (G3-O) and the `.high` certainty test (G5). Your budget for those is **one table plus one list**: Pelland et al. 2025 Table 1, and the sanctioned-override list maintained separately from this authoring pass. You may not open a literature search per entry.
>
> **G0 — Attribute the movement, never the machine.** Describe the movement as a competent lifter performs it. Never copy a manufacturer's "muscles worked," a scraped `body_part` field, or another app: in the ancestor app, 242 equipment records claimed "Full Body." If two common executions attribute differently (upright vs leaning dip; hip-flexion vs pelvis-tucked leg raise), ship two named entries rather than averaging them.
>
> **G1 — Which joints move under load?** Write down every joint whose angle changes against the resistance, and the direction. A muscle is a candidate only if its documented action at one of those joints opposes the resistance. Nothing is attributed because "you feel it there."
>
> **G2 — Does the candidate work through a meaningful range under load?** It must lengthen and shorten under load across a substantial part of its available range. Muscles that hold a joint still, grip the implement, or brace the trunk get role `stabilizer`, weight 0.
>
> > **G2 is a Hardset convention, not a finding, and the guide must say so.** Do **not** claim that isometric work produces no hypertrophy — Oranchuk DJ, Storey AG, Nelson AR, Cronin JB, *Scand J Med Sci Sports* 2019;29(4):484-503, DOI 10.1111/sms.13375, PMID 30580468, reviewed 26 outputs and reported "substantial improvements in muscular hypertrophy and maximal force production ... regardless of training intensity." The convention's real justification is arithmetic and scope. **(a)** Pelland's indirect column contains no stabilisers at all — every entry is a synergist producing torque about a moving loaded joint (presses → triceps and anterior deltoid; pulldowns and rows → biceps and trapezius; squats → rectus femoris), so the 0.5 weight has no validated meaning for an isometric contribution. **(b)** Crediting the ten grip-holds in the current seed at 0.5 would report roughly 10 fractional forearm sets a week to a lifter who never performs a wrist curl, suppressing a real coverage gap. Also do **not** cite Pelland's 4-fractional-set figure as a threshold a credited total must clear: it is the volume at which growth exceeds the smallest detectable effect size (2.05%) in that meta-regression — a detectability artefact of the model, not a biological minimum.
>
> **Grip rule, applied uniformly (no per-exercise judgement):** `forearms` is `direct` only where wrist flexion/extension or radioulnar rotation is the loaded joint action (wrist curl, reverse wrist curl, wrist roller). Every hold — barbell, dumbbell, cable, machine, bodyweight hang — is `stabilizer`. Free-load vs machine is **not** the discriminator; that variant would re-credit most of the ten grip-holds and reproduce the arithmetic problem G2 exists to remove.
>
> **G3 — Which role?** The primary/secondary boundary is Pelland's, quoted:
>
> > "For hypertrophy, direct sets were those in which the measured muscle(s) was likely to be the primary force generator in the exercise. Indirect sets were those in which the measured muscle(s) was likely to be meaningfully trained but not the primary force generator of the exercise (i.e., synergist)." — Pelland JC, Remmert JF, Robinson ZP, Hinson SR, Zourdos MC, *Sports Med* 2025, §2.5. DOI 10.1007/s40279-025-02344-w, PMID 41343037.
>
> The unit of classification is the **(exercise, measured muscle) pair**, so one set can be direct for one muscle and indirect for another — exactly how a primary/secondary pair behaves.
>
> **Apply it with this terminating procedure.** The three sub-tests the research proposed (AGONIST / LIMITER / PROPORTIONALITY) are removed: the first presupposes which loaded joint action is "defining" — a back squat loads knee extension *and* hip extension and nothing in the test picks one — and the other two are unobservable counterfactuals about why a set ended and what happens if you selectively weaken a muscle. Instead:
>
> 1. List every joint whose angle changes against the resistance (G1).
> 2. Identify the joint that moves through the **largest loaded excursion**.
> 3. If exactly one vocabulary muscle produces torque about that joint in the direction opposing the resistance → it is **`direct`**.
> 4. If two do and neither excursion dominates → **both are `direct`** (RDL: hamstrings and glutes).
> 5. In every other case the muscle is **`indirect`** (or `stabilizer`, per G2).
>
> **Ties break toward `indirect`.** Calling an indirect muscle direct *doubles* its credited volume; the reverse *halves* it. The errors are not symmetric in consequence: an inflated count tells a lifter a muscle is covered when it is not, and they remove work — an error they cannot detect. A deflated count tells them a gap exists, and they add work. This is a stated Hardset policy with a stated rationale, not a finding.
>
> **G3-O — Outcome override, citation mandatory.** If a controlled trial measured that muscle's growth from that movement and found it comparable to a recognised direct exercise for that muscle, label it `direct` regardless of G3 and record the citation. An override without a citation does not compile. The sanctioned list is maintained outside this pass.
>
> **G4 — Caps.** ≤2 `direct`; ≤3 `indirect`; ≤3 `stabilizer`. Maximum credited fanout per performed set is therefore 2×1.0 + 3×0.5 = **3.5**; realistic catalogue mean should sit near 2.0. Both asserted in tests. If a fourth `indirect` survives the gates, drop the lowest-certainty one and write it into the entry's notes as prose. Stabilisers carry weight 0 and cannot inflate anything, which is why they are capped separately rather than against the credited cap.
>
> **G5 — Certainty and source, per name.** Bound to the wording already published in `Sources/HardsetCore/Certainty.swift:10-36`:
>
> | certainty | Certainty.swift's own definition | what earns it here |
> |---|---|---|
> | `.high` | "Directly supported, within the range the underlying method was validated on" (:17-18) | **only** a controlled trial that measured *that muscle's* growth from *that movement*. Nothing else. Source must be `trial` with a citation. |
> | `.moderate` | "Supported by evidence that does not cleanly cover this case" (:15-16) | an uncontested anatomical agonist; **or** the exact pair appearing in Pelland Table 1; **or** a stated Hardset convention with a citation. |
> | `.low` | "Directionally useful, wide error bars" (:13) | the label depends on execution, anthropometry or contested biomechanics. Allowed, but a `.low` name may **never** be the sole basis for a coaching prompt. |
> | `.unevaluated` | "No basis to produce a value" (:11) | not yet audited. Ship the entry empty rather than guessed. |
>
> **Pelland Table 1 is strong precedent, not adjudication, and caps at `.moderate`.** The paper introduces it with: "This process was not wholly objective; therefore, Tables 1 and 2 report the decisions made throughout the included studies to clarify the methods used and aid in interpretation," and the header adds "Effort was made to use similar language as manuscripts to best represent the classification decisions." It is also a **corpus census**, listing only exercises that appeared in the 67 included studies — quadriceps and hamstrings show "N/A" in the indirect column and trapezius shows "N/A" in the direct column. **A pair's absence from Table 1 carries no information.**
>
> **Never record EMG.** There is no `emg` source id and there never will be. Surface EMG amplitude is not a validated predictor of hypertrophy — Vigotsky AD, Halperin I, Trajano GS, Vieira TM, *Sports Med* 2022;52(2):193-199, DOI 10.1007/s40279-021-01619-2, PMID 35006527, concluding "we suggest that acute comparative studies that wish to assess stimulus potency be met with scrutiny"; and Zabaleta-Korta A, Latorre-Erezuma U, Fernandez-Pena E, Torres-Unda J, Santos-Concejero J, *Isokinet Exerc Sci* 2024, DOI 10.3233/IES-230079, n=36, preacher vs incline curl, concluding sEMG cannot predict regional hypertrophy. Two further dissociations in this very review: Plotkin 2023 recorded higher sEMG at every gluteal site for the hip thrust, which "did not **consistently** predict gluteal hypertrophy outcomes" (quote exactly — not "did not predict"); Maeo 2023 found greater long-head growth at 34–39% **lower** absolute loads. EMG may confirm a muscle is recruited at all. It may never set a role, rank exercises, or justify an attribution.
>
> **No name-based inference, anywhere on the attribution path.** `MuscleTaxonomy.fine(forMuscle:)` in the ancestor (MuscleTaxonomy.swift:125-155) is a 20-test ordered substring ladder whose comments are a changelog of shipped misclassifications: "lat" needed `&& !contains("lateral")` or lateral raises became lats; "rear shoulder" needed its own branch because rear-delt machines fell through to a generic shoulder test and credited side delts across 98 machines; "hip flexor" had to precede a generic "hip" test or leg raises became glutes; a generic "leg" test silently returned quads; the rotators returned nil and made 7 seeded exercises invisible to every scorer. The class of bug is not fixable by adding branches. Curated attribution is a compile-time literal. Custom attribution is an explicit user choice. A keyword matcher may exist **only** in an offline authoring tool that proposes a key for a human keypress.
>
> **G6 — Read it back.** "One set of X trains {each direct muscle} about as much as a set of the recognised direct exercise for that muscle, and {each indirect muscle} about half as much, and {each stabiliser} not at all for growth purposes." If that sentence is false, the entry is wrong.

### 5.6 The 0.5 credit: adopted convention, not inherited finding

**State it this way in the guide, and never the other way.**

Pelland et al. **did not fit** the 0.5 weight. Methods §2.5 fixes it a priori: "Total was the sum of direct and indirect sets, fractional counted indirect sets as half a set (indirect × 0.5 + direct), and direct did not account for indirect sets." The Bayes factors compare three **fixed** schemes (1.0 / 0.5 / 0.0) for model fit against 67 studies; no weight was estimated from data. The Discussion says so outright: "it must be acknowledged that assigning indirect sets a weight of 0.5 is still an assumption," and it "should be regarded as a heuristic to improve the accuracy of dose-response modeling, rather than a definitive standard for practical application across all contexts."

Therefore: **adopting their direct/indirect sentence verbatim improves the analogy between their classification and ours. It confers no entitlement to the number.** The claim that "the weight was fitted under that labelling, so we are entitled to it" is refuted and must not appear anywhere.

Hardset adopts 0.5 as a **stated product convention**: at `.moderate` certainty inside the eight muscles Pelland measured, and at `.low` outside them. The `stabilizer` weight of 0 is a **second Hardset convention**, extrapolating beyond a method that has two categories and no zero bucket — justified on the authoring need to record involvement-without-growth so that authors stop putting bracing and grip in the indirect bucket, **not** on any 'covered' threshold, which Pelland does not supply and this product does not define.

Certainty bounds on a weekly per-muscle total, all placed in `EvidenceSource.validRange` (Certainty.swift:51) so the App Review 1.4.1 disclosure is generated rather than hand-written:

- Never `.high`. `.high` requires a trial measuring that muscle's growth from that movement; an aggregate over many movements cannot qualify.
- `.moderate` maximum for a `modelled` muscle.
- `.low` for a `counted` muscle, i.e. any muscle outside {quadriceps, rectus femoris, hamstrings, pectoralis major, anterior deltoid, trapezius, triceps brachii, biceps brachii}.
- `.low` above ~25 fractional weekly sets: "few studies have explored ~25+ fractional weekly sets," and the best-fit hypertrophy model was a **square-root** form supporting "diminishing returns but not an inverted-U," with CrI widths at high volumes leaving it "compatible with multiple functional forms."
- `Certainty.combine` takes the minimum (Certainty.swift:33-35), so all of these compose automatically.

### 5.7 The one sanctioned override, stated correctly

**back squat → glutes = `direct`, source `convention`, certainty `.moderate`.**

Not `.high`, and not an evidence-backed override. The supporting claim was refuted twice: the participants were **untrained** college-aged (hip thrust n=18, 22±3 y; back squat n=16, 24±4 y), not "34 trained participants"; and the glute result is an **underpowered null**, not equivalence — SQ-vs-HT gluteus maximus mCSA was lower -1.6 ± 2.1 cm² (CI95% -6.1, 2.0), mid -0.5 ± 1.7 (-4.0, 2.6), upper -0.5 ± 2.6 (-5.8, 4.1), intervals wide enough to contain a large hip-thrust advantage, with no equivalence test run. Reading ~17-per-group novice CIs spanning zero as "a squat set trains the glutes as much as a hip thrust set" is the named failure pattern.

The convention's actual basis: **(a)** Pelland's corpus never measured glutes, so 0.5 has no precedent for them either — there is no defensible default to fall back to; **(b)** the meta-analytic evidence has squats significantly increasing gluteus maximus size (*Front Physiol* 2025, DOI 10.3389/fphys.2025.1542334); **(c)** hip extension through a large loaded excursion is one of two co-dominant joint actions in a squat, satisfying step 4 of the G3 procedure on its own.

Also from the same correction: keep `adductors` as `indirect` at `.moderate`, and **drop `hamstrings` from the back squat entry** (currently at `Sources/HardsetCore/ExerciseCatalog.swift:70-71`).

---

## 6. SWIFT DECLARATIONS

New file: `Sources/HardsetCore/MuscleTaxonomy.swift`.

```swift
import Foundation

/// The permanent muscle vocabulary.
///
/// Every raw value here is a value that reaches a CloudKit-synchronised TEXT column. Adding a
/// case is permitted and cheap. Renaming or removing one is permanently impossible from the
/// first build that reaches a second device: SQLiteData forbids renaming a column forever and
/// CloudKit's production schema is additive-only, so a re-spelling is a data migration across
/// every user's device rather than a schema edit.
///
/// Deliberately NOT `Codable`. That is defence in depth only — see `MuscleKey` for the rule
/// that actually closes the throwing-decode path.
///
/// Declaration order IS display order.
public enum Muscle: String, CaseIterable, Sendable, Hashable {
  case chest
  case frontDelts, sideDelts, rearDelts, rotatorCuff
  case lats, upperBack, traps, lowerBack
  case biceps, triceps, forearms
  case abs, obliques
  case neck
  case quadriceps, hamstrings, glutes, adductors, hipAbductors, gastrocnemius, soleus

  /// Total switch. There is no `default:` branch and there never may be — a title-cased
  /// fallback is a value that looks measured and is not (see `Certainty` doc comment).
  /// The returned strings are String Catalog keys resolved by the UI layer.
  public var displayNameKey: String { "muscle.\(rawValue)" }

  /// The tissue this slot owns, stated so two authors cannot split the same tissue two ways.
  /// This is the boundary the audit named as the real open item for `traps`/`upperBack`.
  public var tissueDefinition: String {
    switch self {
    case .traps: "Upper trapezius only. The tissue producing scapular ELEVATION."
    case .upperBack:
      "Rhomboids, MIDDLE and LOWER trapezius, teres. The tissue producing scapular "
        + "RETRACTION and DEPRESSION. Note: the lower trapezius lives here, not in `traps`."
    case .lats: "Latissimus dorsi. Humeral shoulder EXTENSION and ADDUCTION."
    case .abs: "Rectus abdominis. Trunk FLEXION."
    case .obliques: "External and internal obliques. Trunk ROTATION and LATERAL FLEXION."
    case .adductors: "Adductor group including adductor magnus. Hip ADDUCTION and, in flexed "
        + "positions, hip EXTENSION."
    case .hipAbductors: "Gluteus medius and minimus as one unit — the granularity the only "
        + "trial measuring them used. Hip ABDUCTION."
    case .quadriceps: "The whole quadriceps femoris, all four heads. Knee EXTENSION."
    case .gastrocnemius: "Both gastrocnemius heads. Plantarflexion with the knee EXTENDED."
    case .soleus: "Soleus. Plantarflexion at any knee angle."
    case .lowerBack: "Lumbar and thoracic erector spinae. Spinal EXTENSION."
    case .forearms: "Wrist and finger flexors and extensors. Wrist FLEXION/EXTENSION and "
        + "radioulnar ROTATION. Grip is never credited here — see the grip rule."
    // ... remaining cases, one line each.
    default: ""
    }
  }

  public var tier: MuscleEvidenceTier {
    switch self {
    case .chest, .frontDelts, .biceps, .triceps, .quadriceps, .hamstrings: .modelled
    default: .counted
    }
  }

  /// Rendering detail only. NOT a taxonomy gate: wger ships highlight art for serratus
  /// anterior and brachialis, so "has a distinct silhouette region" is not a real requirement.
  public var isDrawable: Bool {
    switch self {
    case .rotatorCuff: false
    default: true
    }
  }

  /// Written out rather than searched so the compiler checks exhaustiveness.
  /// `MuscleGroupPermutationTests` asserts this agrees with `MuscleGroup.members`.
  public var group: MuscleGroup {
    switch self {
    case .chest: .chest
    case .frontDelts, .sideDelts, .rearDelts, .rotatorCuff: .shoulders
    case .lats, .upperBack, .traps, .lowerBack: .back
    case .biceps, .triceps, .forearms: .arms
    case .abs, .obliques: .core
    case .neck: .neck
    case .quadriceps, .hamstrings, .adductors, .hipAbductors, .gastrocnemius, .soleus: .legs
    case .glutes: .glutes
    }
  }
}

/// Where a token's number may be interpreted, and where it may only be counted.
public enum MuscleEvidenceTier: String, Sendable, Hashable, CaseIterable {
  /// The token's meaning matches, one-to-one, a site measured as a hypertrophy outcome in the
  /// 67-study corpus behind the fractional-counting scheme. A weekly fractional count may be
  /// placed on the published dose-response relationship, at `.moderate` and no higher.
  case modelled
  /// A real token with real attribution, credited at full fractional weight and shown as a
  /// number and as present/absent. Never placed on a dose-response curve, never compared to a
  /// target. Weekly totals cap at `.low`.
  case counted
}

/// Derived in code and NEVER stored in any column. Storing a group would create a second
/// source of truth that can disagree with the first and would freeze the group set forever.
/// The moment any code path persists a group key — a CSV header, a widget configuration, a
/// notification payload — that freedom is silently gone. Exports must prefix
/// (`muscle.glutes` vs `group.glutes`), because those two raw values collide.
public enum MuscleGroup: String, CaseIterable, Sendable, Hashable {
  case chest, shoulders, back, arms, core, neck, legs, glutes

  /// The one canonical edge of the hierarchy.
  public var members: [Muscle] {
    switch self {
    case .chest: [.chest]
    case .shoulders: [.frontDelts, .sideDelts, .rearDelts, .rotatorCuff]
    case .back: [.lats, .upperBack, .traps, .lowerBack]
    case .arms: [.biceps, .triceps, .forearms]
    case .core: [.abs, .obliques]
    case .neck: [.neck]
    case .legs: [.quadriceps, .hamstrings, .adductors, .hipAbductors, .gastrocnemius, .soleus]
    case .glutes: [.glutes]
    }
  }
}

/// The ONLY type that crosses the storage boundary.
///
/// A struct, not an enum. Swift has no per-case access control, so an enum with
/// `case known(Muscle) / case unrecognized(String)` cannot prevent
/// `.unrecognized("chest")` being constructed as a SECOND bucket for a known muscle: it is a
/// distinct `Hashable` value that returns the identical `storedValue`, so a `[MuscleKey: Double]`
/// map splits one muscle's volume in two while the grand total still reconciles. With a private
/// stored String and a single public initialiser, one token can only ever produce one key.
public struct MuscleKey: Hashable, Sendable {
  /// Reserved permanently. Already the column DEFAULT (Migrations.swift:102) and the Swift
  /// property default (Schema.swift:22), so it is a live value whether or not anyone decides
  /// it is: any insert omitting the column — including a peer record arriving without the
  /// field — produces it. No `Muscle` case may ever take it as a raw value.
  public static let notAttributedRawValue = "unknown"

  private let raw: String

  /// Total, non-failable, non-throwing, and NON-NORMALISING. Non-normalising is the point:
  /// `storedValue` must be byte-identical to what came out of the column. No trimming, no
  /// case folding, no Unicode normalisation.
  public init(stored raw: String) { self.raw = raw }
  public init(_ muscle: Muscle) { self.raw = muscle.rawValue }

  public var storedValue: String { raw }
  public var muscle: Muscle? { Muscle(rawValue: raw) }
  public var isAttributed: Bool { muscle != nil }
  public var isReservedSentinel: Bool { raw == Self.notAttributedRawValue }

  /// Never the raw string. "Not attributed" and "Not recognised" are different facts about the
  /// same row — "nobody has attributed this yet" versus "a newer version knows something I do
  /// not" — and get different copy, with identical non-counting, non-grouping treatment.
  public var displayNameKey: String {
    if let muscle { return muscle.displayNameKey }
    return isReservedSentinel ? "muscle.notAttributed" : "muscle.notRecognised"
  }
}

/// Stored inside the JSON. Deliberately NOT `Codable`: decoded via
/// `MuscleRole(rawValue:) ?? .indirect` inside the tolerant decoder, which flags the fallback.
public enum MuscleRole: String, Sendable, Hashable, CaseIterable {
  case direct, indirect, stabilizer
}

/// The closed set of things that may justify an attribution in CURATED content.
/// There is deliberately no `emg` case, so an attribution justifiable only by an amplitude
/// study is structurally impossible to express, not merely against policy.
public enum AttributionSourceID: String, Sendable, Hashable, CaseIterable {
  case trial
  case pellandTable1 = "pelland-table-1"
  case anatomy
  case convention
  case user
}

public struct MuscleContribution: Hashable, Sendable {
  public let key: MuscleKey
  public let role: MuscleRole
  public let certainty: Certainty
  /// A `String`, not `AttributionSourceID`: a v2 source id must survive a v1 read unchanged.
  /// The allowlist is enforced against CURATED content at build time (test 6), not at decode.
  public let sourceID: String
  public let citation: String?
}

/// Store the ROLE, never the fraction. A number baked into 240 rows becomes a stale copy of a
/// counting convention the moment the convention is revisited, with no way to tell an
/// intentional per-exercise weight from a stale default.
public enum SetCounting {
  public static func weight(_ role: MuscleRole) -> Double {
    switch role {
    case .direct: 1.0
    case .indirect: 0.5
    case .stabilizer: 0.0
    }
  }

  /// One `EvidenceSource`, so the guideline 1.4.1 disclosure is generated by the same code
  /// that does the counting and cannot drift from it.
  public static let source = EvidenceSource(
    id: "hardset-fractional-credit-v1",
    title: "Fractional set counting",
    methodology: """
      A completed working set credits 1.0 set to each muscle labelled direct on the movement, \
      0.5 to each labelled indirect, and 0 to each labelled stabiliser. The 1.0/0.5 split \
      follows the fractional scheme that best fitted 67 training studies in Pelland et al. \
      (2025). Those authors fixed the 0.5 weight in advance rather than estimating it from \
      data, and describe it as an assumption and a heuristic; Hardset adopts it as a stated \
      convention. The 0 weight for stabilising and gripping muscles is Hardset's own \
      convention and is not part of the scheme that was tested.
      """,
    citation: """
      Pelland JC, Remmert JF, Robinson ZP, Hinson SR, Zourdos MC. Sports Med 2025. \
      DOI 10.1007/s40279-025-02344-w, PMID 41343037.
      """,
    validRange: """
      The scheme was compared against studies measuring eight sites: quadriceps/knee \
      extensors, rectus femoris, hamstrings/posterior thigh, pectoralis major, anterior \
      deltoid, trapezius, triceps brachii/elbow extensors, biceps brachii/elbow flexors. \
      Applying it to any other muscle is an extrapolation. Few studies examined more than \
      about 25 fractional weekly sets, so counts above that fall outside the fitted range. \
      No isometric or stabilising contribution appears anywhere in the classification.
      """
  )
}

/// Whether a weekly set TARGET exists for this muscle.
///
/// v1 returns `.unevaluated` for EVERY muscle, because no per-muscle weekly set target is
/// published for any muscle. Pelland et al. give a dose-response relationship for eight
/// measured sites, not targets; the reference app's own bands were practitioner numbers with
/// no citation; and the ~4-fractional-set minimum-effective-dose figure is the volume at which
/// growth exceeds the smallest detectable effect size (2.05%) in that meta-regression — a
/// detectability artefact, not a biological floor.
///
/// The function exists anyway so `warnings` can only iterate EVALUATED bands. That makes
/// warning-without-a-band unrepresentable, which is the bug the ancestor documented at
/// TrainingScience.swift:110-118, where deriving an `isOptional` flag from `mev == 0` made
/// every per-session band look optional and "silently emptied session volume scoring."
public func weeklyTarget(for muscle: Muscle, profile: TrainingProfile) -> Claim<VolumeBand>

/// Evaluated only for `.modelled` muscles: `.moderate` in 0...25 fractional sets, `.low` above.
/// `.unevaluated` for every `.counted` muscle.
public func doseResponse(fractionalSets: Double, for muscle: Muscle) -> Claim<DoseResponsePosition>

/// The counting function is structurally unable to see a band: it takes sets and roles, and
/// nothing else, so no flag can ever leak from warnings into arithmetic.
public func fractionalSets(for key: MuscleKey, in sets: [LoggedSet]) -> Double

/// Three names, so the three quantities cannot be conflated. Only `fractionalSets` may ever
/// be compared to a band or placed on a curve.
public func hardSets(in sets: [LoggedSet]) -> Int
public func setsTouching(group: MuscleGroup, in sets: [LoggedSet]) -> Int

public struct DecodedAttribution: Hashable, Sendable {
  public let contributions: [MuscleContribution]
  /// Elements that could not be read at all. A caller that discards this is a test failure —
  /// a tolerant decoder that hides failures is strictly worse than the strict one it replaced.
  public let unreadableEntryCount: Int
  public let degradedFieldCount: Int
}

/// The ONE conversion between the frozen TEXT columns and the vocabulary.
public enum MuscleColumn {
  public static func decodePrimary(_ stored: String) -> MuscleKey
  public static func decodeContributions(_ storedJSON: String) -> DecodedAttribution
  /// Always emits the object grammar, ordered by `Muscle.allCases`. Never the bare-array form.
  public static func encode(_ contributions: [MuscleContribution]) -> String
}

/// Append-only. Every entry is permanent. Renaming or removing one silently orphans every
/// peer record and user-created row that still carries the old spelling — visible only as
/// volume that quietly stopped counting. Nothing in CloudKit or SQLiteData detects this;
/// `SchemaRules.notValidatedAnywhere` records the same gap one level up, for columns.
public let shippedMuscleKeys: Set<String> = [
  "chest", "frontDelts", "sideDelts", "rearDelts", "rotatorCuff",
  "lats", "upperBack", "traps", "lowerBack",
  "biceps", "triceps", "forearms",
  "abs", "obliques", "neck",
  "quadriceps", "hamstrings", "glutes", "adductors", "hipAbductors",
  "gastrocnemius", "soleus",
]
```

### Mapping onto the frozen TEXT columns

| column (frozen) | Swift type on the table | holds | conversion |
|---|---|---|---|
| `exercises.primaryMuscle` (Schema.swift:22, Migrations.swift:102) | `String`, **never** `@Column(as:)` | exactly one `MuscleKey.storedValue`, or the reserved `"unknown"`. The **display/sort** key — the picker sections on it (ExercisePickerView.swift:109), so it must stay single-valued. | `MuscleColumn.decodePrimary` |
| `exercises.secondaryMusclesJSON` (Schema.swift:23, Migrations.swift:103) | `String`, **never** `@Column(as:)` | the **complete** contribution list in the object grammar of §4.5, including the display primary at `role: "direct"`. The column's name says "secondary"; its contents are the whole list. The name is frozen; the grammar is not. | `MuscleColumn.decodeContributions` / `.encode` |

Invariant, test-enforced: the value of `primaryMuscle` appears in the JSON with `role: "direct"`. This is what makes multi-prime-mover movements (conventional deadlift: hamstrings + glutes) expressible from day one with no new column ever — resolving the fact that a single TEXT primary would otherwise force the deadlift to demote glutes to a 0.5 secondary (currently ExerciseCatalog.swift:118-119).

Deletions in the same change: `ExercisePickerView.muscleOrder` (:102-106, replaced by `Muscle.allCases`), `ExercisePickerView.title(for:)` (:122-133, replaced by `MuscleKey.displayNameKey`) and its use in `spokenLabel(for:)` (:135-136), and the hard-coded 13-string `required` array in `ExerciseCatalogTests.coversMajorGroups` (`Tests/HardsetStoreTests/CatalogSeederTests.swift:163-176`, replaced by a walk over `Muscle.allCases`). `CatalogExercise` and `CatalogEntry` change from `primaryMuscle: String` / `secondaryMuscles: [String]` to `primaryMuscle: MuscleKey` / `contributions: [MuscleContribution]`. Total blast radius today: four files, because nothing in the app consumes muscle attribution yet — `SessionVolume` (SessionVolume.swift:15-55) carries only workingSets, warmupSets, volumeKg and reps, with no muscle dimension. That window closes the moment the volume engine is written.

Also fix the stale reference at `CatalogSeeder.swift:34` — it cites `CatalogTests`, which does not exist; the real suite is `ExerciseCatalogTests`, declared at `CatalogSeederTests.swift:124`.

---

## 7. MIGRATION OF THE 50 SEEDED ENTRIES

Verified by extracting every literal from all 50 entries in `Sources/HardsetCore/ExerciseCatalog.swift`: **50 entries, 16 distinct muscle strings**, 15 of which also appear as secondaries (`quadriceps` never does). Primary-value frequencies: chest 8, quadriceps 6, lats 5, biceps 5, triceps 4, hamstrings 4, upperBack 3, sideDelts 2, rearDelts 2, frontDelts 2, forearms 2, calves 2, abs 2, traps 1, lowerBack 1, glutes 1.

### 7.1 Per-value map — 15 identity, 1 split, zero orphans

| stored string today | maps to | note |
|---|---|---|
| `abs` | `abs` | identity |
| `biceps` | `biceps` | identity |
| `chest` | `chest` | identity — no upper/lower split (§2.1) |
| `forearms` | `forearms` | identity; **role** changes on 10 entries (grip rule) |
| `frontDelts` | `frontDelts` | identity |
| `glutes` | `glutes` | identity |
| `hamstrings` | `hamstrings` | identity |
| `lats` | `lats` | identity |
| `lowerBack` | `lowerBack` | identity |
| `quadriceps` | `quadriceps` | identity |
| `rearDelts` | `rearDelts` | identity |
| `sideDelts` | `sideDelts` | identity |
| `traps` | `traps` | identity |
| `triceps` | `triceps` | identity |
| `upperBack` | `upperBack` | identity |
| `calves` | **`gastrocnemius` and/or `soleus`** | the one non-identity edit, per knee position — 3 call sites |

### 7.2 The two collisions the brief named do not exist

**`quadriceps` vs `quads`: there is no collision.** `quads` appears **nowhere in Hardset**. It is the ancestor's spelling (`Elos/.../MuscleTaxonomy.swift:48`) in a separate app with a separate database and no migration path between them. Hardset keeps `quadriceps` — it is what is in the seed, and it matches Pelland's measured site name. `quads` is the **display name** ("Quads"), and it goes in the import alias table mapping to `quadriceps`. Do not rename the raw value; that would break the identity map for 6 primary sites for no benefit.

**`traps` vs `upperBack`: not a collision either — both are already distinct live values and both become distinct tokens.** `Shrug` carries `primaryMuscle: "traps"` (:422) and `Conventional Deadlift` lists both `"upperBack"` and `"traps"` in one secondary array (:119). The real open item the audit named is the **anatomical boundary**, and it is settled in §1 / `Muscle.tissueDefinition`: `traps` = upper trapezius, scapular **elevation**; `upperBack` = rhomboids + **middle and lower** trapezius + teres, scapular **retraction/depression**. The lower trapezius lives in `upperBack`, which is counterintuitive from the name and is exactly where two authors would otherwise diverge. This must be in the taxonomy file before the 240-entry pass starts.

Note the picker consequence being fixed at the same time: `Dictionary(grouping: entries, by: \.primaryMuscle)` (ExercisePickerView.swift:109) currently shows a one-item "Traps" section and a three-item "Upper back" section. With the boundary defined, that is correct behaviour, not a bug.

### 7.3 The calf split — three call sites

| site | today | becomes |
|---|---|---|
| `standing-calf-raise` (:156-159) | primary `calves`, no secondaries | `direct: [gastrocnemius, soleus]` — both are prime movers of plantarflexion with the knee extended. `primaryMuscle = "gastrocnemius"`. |
| `seated-calf-raise` (:164-167) | primary `calves`, no secondaries | `direct: [soleus]` only. Gastrocnemius appears at **no** role: Kinoshita's seated condition produced +0.6% medial / +1.7% lateral, both non-significant (p = 0.147–0.508). Omitting it *is* the dissociation. `primaryMuscle = "soleus"`. |
| `seated-leg-curl` (:126-127) | secondary `calves` | `indirect: [gastrocnemius]` at `.low` — the gastrocnemius crosses the knee and contributes to knee flexion. Applied to **both** leg curls (see 7.4), resolving the sibling inconsistency where `lying-leg-curl` (:134) credited nothing. |

`"calves"` goes into the **import alias table** as ambiguous → `Claim.unevaluated`, driving a "seated or standing?" prompt. It is not a retired Hardset key (it never shipped), but it is the common English term every external vocabulary and every user will supply.

### 7.4 Role corrections applied in the same change

Per the audits and the uniform grip / stabiliser / hinge rules:

- **`abs` → `stabilizer`** on back squat (:71), front squat (:79), overhead press (:303). Under fractional counting these three would otherwise credit a lifter doing 20 weekly sets across them **10 fractional ab sets with no direct ab work** — stated as a projection, because nothing credits anything today (`secondaryMuscles` is a bare `[String]` with no role or weight, ExerciseCatalog.swift:21-22, and `SessionVolume` has no muscle dimension).
- **`forearms` → `stabilizer`** on all 10 grip-hold sites: pull-up (:239), chin-up (:247), lat pulldown (:255), barbell curl (:351), dumbbell curl (:359), incline dumbbell curl (:367), preacher curl (:375), hammer curl (:383), shrug (:423), hanging leg raise (:439). It stays `direct` on wrist curl (:454) and reverse wrist curl (:462). Add `stabilizer` to conventional deadlift and single-arm dumbbell row, which currently omit it — the rule is uniform, not per-entry.
- **`upperBack` → `stabilizer`** on front squat (:79) — the torso angle is held.
- **`lats` → `stabilizer`** on RDL (:111) — bar-path isometric.
- **`glutes` → `direct`** on back squat (:71, convention per §5.7), front squat (:79), conventional deadlift (:119), RDL (:111).
- **Drop `hamstrings`** from back squat (:71) and leg press (:95). Kubo 2019: hamstring volume "did not change in either group."
- **Add `adductors` `indirect`** to back squat, front squat, leg press, bulgarian split squat (Kubo 2019, Plotkin 2023). This gives the token its first credit; it still has **no** `direct` entry in the 50 and stays on the unauthored allowlist.
- **`lowerBack`:** `indirect` at `.low` where the torso angle changes under load and the erectors resist a moving spinal flexion moment (conventional deadlift :119, RDL :111); `stabilizer` where the torso angle is held (back squat :71, barbell row :271); `direct` on back extension (:447). The underlying question is unresolved (§10) — Pelland never measured erector spinae and no trial exists either way — which is why the certainty is `.low` and the rule is mechanical rather than judged.
- **`traps` → `stabilizer`** on conventional deadlift (:119) — the upper trapezius resists scapular depression isometrically.
- **`chest` → `direct`** on close-grip bench (:415) alongside triceps. **`triceps` → `direct`** on dip (:231) alongside chest.
- **`frontDelts` stays `indirect`** on pec deck (:215) and cable fly (:223). The research's proposal to make them stabilisers "because front delts are already saturated by every press" is **rejected**: that is a programming argument, and attribution describes the movement, not the program. The shoulder joint moves under load through horizontal adduction and the anterior deltoid contributes to it.
- **`rotatorCuff` `indirect`** added to face pull (:343) — the external-rotation component. Still no `direct` credit anywhere.
- Bench press family (:174-175, :182-183, :190-191, :198-199, :206-207) is **unchanged**: `direct: [chest]`, `indirect: [frontDelts, triceps]`, matching Pelland Table 1 exactly (bench press → anterior deltoid and triceps both **indirect**, contradicting the common app convention of front delts as a co-primary on pressing). That five entries change nothing is the useful signal that the rule is not a rewrite.

### 7.5 Unauthored direct slots after this pass

`{rotatorCuff, obliques, adductors, hipAbductors, neck}` — five tokens with no `direct` credit anywhere in the 50 entries. This is a **content commitment**, recorded as a shrinking allowlist in CI (test 14), with the named exercise sets the 240-entry pass must author: cable external rotation; Pallof press and side bend; adduction machine and Copenhagen plank; abduction machine and banded lateral walk; neck flexion and extension.

---

## 8. ENFORCEMENT TESTS

Extend `ExerciseCatalogTests` (`Tests/HardsetStoreTests/CatalogSeederTests.swift:124`) and add `Tests/HardsetCoreTests/MuscleTaxonomyTests.swift`.

| # | test | prevents |
|---|---|---|
| 1 | Every muscle string in all 50 catalogue entries satisfies `MuscleKey(stored:).isAttributed` | free text reaching a permanent column; a typo introducing a 23rd value that the current `coversMajorGroups` (:163-176) would pass unchanged because it hard-codes 13 of 16 |
| 2 | No muscle key appears twice in one entry under **any** role | one muscle occupying two buckets in an entry. Generalises the existing primary-not-also-secondary check (:148-161), which is insufficient now that three roles exist |
| 3 | Every entry has ≥1 `direct` contribution, and `primaryMuscle` appears in the JSON at `role: "direct"` | a movement that credits nothing; the display key drifting away from the arithmetic |
| 4 | Caps: ≤2 `direct`, ≤3 `indirect`, ≤3 `stabilizer`; per-entry credited fanout ≤3.5; catalogue mean ≤2.0 | two-primaries drift, which inflates every large-muscle total by up to 100%; an unbounded number in the dashboard the user acts on |
| 5 | No `Muscle` raw value equals `MuscleKey.notAttributedRawValue` | the reserved sentinel colliding with a real token — it is already a live value via the column DEFAULT (Migrations.swift:102) |
| 6 | The set of `sourceID`s in curated content ⊆ `AttributionSourceID.allCases`; and no contribution with `sourceID != "trial"` carries `.high` | an EMG-justified attribution existing at all; `.high` being awarded to textbook anatomy or to Pelland Table 1 membership, both of which the file's own wording puts at `.moderate` |
| 7 | Every entry is either fully attributed or fully `.unevaluated` | half-audited rows, which contribute a confident-looking partial number |
| 8 | `MuscleGroup.allCases.flatMap(\.members)` is a permutation of `Muscle.allCases`, no group empty; and `Muscle.allCases.allSatisfy { $0.group.members.contains($0) }` | the two directions of the hierarchy drifting apart — the ancestor derived `children` from `group` for exactly this reason (MuscleTaxonomy.swift:8-13, :75-85) |
| 9 | `shippedMuscleKeys ⊆ Set(Muscle.allCases.map(\.rawValue))`, failure message naming the offending key and saying it is permanent | an accidental rename shipping green. Renaming `quadriceps` to `quads` compiles, passes every other test, seeds cleanly, and orphans every peer record and user row that still says `quadriceps` — visible only as volume that quietly stopped counting. `SchemaRules.notValidatedAnywhere` (:64-77) records the identical gap for columns |
| 10 | For every `Muscle` case and an adversarial set (`""`, `"unknown"`, `"Chest"`, `" chest "`, `"🦵"`, `"chest\0x"`, `"adductorMagnus"`): `MuscleKey(stored: s).storedValue == s` | a future normalising initialiser silently rewriting a peer's bytes |
| 11 | No `MuscleKey` whose `muscle` is nil has a raw value that `Muscle(rawValue:)` accepts; and `[MuscleKey: Double]` fed the same token twice yields exactly one bucket | the two-bucket split that an enum-based `MuscleKey` permits and that no totals-reconcile test can catch |
| 12 | Write a row with an unfamiliar token in **both** columns, read it back through the real `Exercise` query path, assert the read succeeds and both column strings are byte-identical | the throwing decode. This is the test that matters — `#expect(!(Muscle.self is any Decodable.Type))` passes while a `@Column(as: Muscle.RawRepresentation.self)` column decode of the same token throws `DataCorruptedError`. Keep the `Decodable` assertion too, labelled defence-in-depth |
| 13 | Write a row with unrecognised keys, then exercise rename / archive / machine-bind / re-seed, and assert both attribution columns are unchanged strings | field-wise last-edit-wins destroying a newer device's attribution permanently, with no recovery because the original value is stored nowhere else |
| 14 | `everyMuscleIsDirectOnAtLeastOneEntry`, with an explicit `unauthoredDirectSlots: Set<Muscle>` initialised to `{rotatorCuff, obliques, adductors, hipAbductors, neck}`, asserted **never to grow**, and printed on every run | a declared muscle the user can see in a picker and can never train. The shrinking allowlist is the visible progress metric for the 260–340-hour authoring pass |
| 15 | For each malformed input shape (bad root, non-array root, non-string/non-object element, unknown role, duplicate muscle), `decodeContributions` returns a non-zero `unreadableEntryCount` or `degradedFieldCount`; and no production caller discards those fields | the tolerant decoder becoming a silent-corruption surface worse than the strict one it replaced. Also guards against a regression to `(try? ... ) ?? []` (CatalogSeeder.swift:128), which returns `[]` for the whole array on one bad element |
| 16 | `MuscleGroupStatus` exposes no member of type `Double`/`Int` named or derived as a summed set count; and a fixture asserting `setsTouching(group: .back)` for one barbell-row set is `1`, not `2.5` | the group-level sum. One barbell-row set credits upperBack 1.0 + lats 0.5 + rearDelts 0.5 + lowerBack 0.5 (ExerciseCatalog.swift:265-272) |
| 17 | Re-seeding an existing row leaves `primaryMuscle` and `secondaryMusclesJSON` unchanged unless the stored value is empty or `"unknown"`; and no row is pruned for having a slug absent from the local catalogue | the v1/v2 launch-time ping-pong under field-wise last-edit-wins, which makes the volume readout depend on which phone was opened last; and a v1 device deleting a v2-introduced movement |
| 18 | No muscle-typed field exists on the `machines` table; every volume computation routes `sessionExercises.exerciseID` → `exercises.primaryMuscle`, never `loggedSets.machineID` | attribution drifting onto the machine. `loggedSets.machineID` (Schema.swift:90) makes machine-level attribution one join away, and scraped equipment body-part data is marketing copy — 242 ancestor records claimed "Full Body" |

---

## 9. WHAT WE ARE NOT CLAIMING

Statements the taxonomy must never make, in code, copy, marketing, or App Review disclosure.

1. **That 0.5 is a measured or fitted quantity.** It was fixed a priori and its authors call it "still an assumption" and "a heuristic ... rather than a definitive standard."
2. **That we are "entitled" to the 0.5 weight because we copied Pelland's wording.** Copying the wording buys a better analogy. Nothing more.
3. **That isometric or stabilising work produces no hypertrophy.** Oranchuk et al. 2019 (DOI 10.1111/sms.13375, PMID 30580468) reports the opposite: "substantial improvements in muscular hypertrophy ... regardless of training intensity." Weight 0 is our accounting convention, not a physiological claim.
4. **That 4 fractional weekly sets is a minimum effective dose in any biological sense.** It is the volume at which modelled growth exceeds a 2.05% smallest detectable effect — an artefact of that meta-regression's detectability floor.
5. **That any per-muscle weekly set target exists.** None is published for any muscle. The ancestor's bands (TrainingScience.swift:141-162) were practitioner numbers with no citation.
6. **Anything about MRV, an inverted-U, or an upper limit.** MRV has never been operationalised in a trial and is deleted from this product. Pelland's best-fit hypertrophy model was a square-root form supporting "diminishing returns but not an inverted-U," and above ~25 fractional weekly sets the app asserts nothing.
7. **That surface EMG amplitude tells us anything about growth.** Not as a source, not as a tiebreak, not as a ranking input.
8. **That squats do not grow the rectus femoris.** Kubo 2019 is n=8 and n=9 per group with power >0.8 reported only for the significant changes.
9. **That a squat set trains the glutes as much as a hip thrust set.** Plotkin's glute result is an underpowered null in an untrained sample with intervals wide enough to contain a large hip-thrust advantage and no equivalence test.
10. **That lengthened partials and full ROM are equivalent.** The equivalence test was met for thigh muscle area (p=0.019) and **not** for arm (p=0.071).
11. **That Pelland Table 1 membership validates a pair,** or that a pair's absence from it means the muscle is not a synergist. It is a transparency record of the review team's own "not wholly objective" decisions, restricted to the exercises those 67 studies prescribed.
12. **Any group-level set total.** No "Back: 18 sets," ever.
13. **Any per-user model of dose-response.** Pelland is a population-level meta-regression.
14. **That attribution is a property of a machine, a brand, or an equipment record.**
15. **Any upper/lower chest, triceps head, hamstring head, biceps head, glute region, or ab region distinction** — see §2 for each.
16. **That no competitor does fractional indirect counting.** What is verified is **silence, not absence**: Hevy's public material describes volume as counting "the number of sets done per muscle group" and confirms user-labelled secondary targets feed its graphs without stating a weight (hevyapp.com/features/sets-per-muscle-group-per-week, 2026-08-20); MacroFactor's Muscle Groups article states no weighting; Strong advertises only a "Muscle Heat Map"; Setgraph and Boostcamp publish no method. Settling it requires installing the apps and logging a compound lift, which no pass has done. **"Unclaimed differentiator" must not appear in any document a decision rests on.** (And for the record: Boostcamp **does** advertise a muscle breakdown — "Muscle Volume Tracking – See which muscle groups you're hitting and which ones you're neglecting." appears verbatim in its own App Store description's "WHAT YOU GET" block, three occurrences, in the same block as its "POPULAR PROGRAMS" list. The earlier finding attributing that line to a neighbouring app is withdrawn.)
17. **Ontology provenance beyond documentation.** An Uberon mapping, if recorded, is a static table in `HardsetCore` with an explicit alignment quality — never a column, never an interchange format. Verified anchors only: `UBERON:0002463` for hamstrings (**exact**, via exact synonym "hamstring muscle" — the earlier "no usable group term" claim is withdrawn), `UBERON:0001665` triceps surae for the gastrocnemius+soleus pair (**exact**, related synonym "calf muscle" — the earlier composite is withdrawn), `UBERON:0001377` quadriceps femoris (exact), `UBERON:0001112` latissimus dorsi (exact), `UBERON:0002381` pectoralis major (exact for our single `chest`), `UBERON:0003683` rotator cuff (exact), `UBERON:0002380` trapezius (**broader** — spans `traps` and `upperBack`), `UBERON:0001476` deltoid (**broader** — spans all three delt tokens). Individual gastrocnemius and soleus ids were not fetched in any pass and must be verified before the table ships. Uberon's confirmed resolution gaps — no deltoid-head term, no clavicular/sternal pectoralis head term, no upper/middle/lower trapezius term — are on their own sufficient to reject it as the stored representation. **FMA is declined on availability, not licence:** its canonical licence page refused connection (ECONNREFUSED 140.142.142.151:443, 2026-08-20), BioPortal returned HTTP 403, and Bioregistry records an `FMA_RETIRED` prefix. Do **not** repeat the claim that FMA's licence prevents citing it as a source — Bioregistry records FMA as CC-BY-3.0, and the restriction in secondary summaries applies to redistributing *modifications* under the FMA/UW names, materially identical to CC BY 3.0 §4(b), which Uberon also carries. And FMA is *finer* than Uberon, not worse.
18. **That the vocabulary's size is justified by body-map drawability.** It is not, and that argument is deleted.

---

## 10. UNRESOLVED

Genuinely open. Do not mistake any of these for settled.

1. **Do lumbar erectors hypertrophy from hinging?** No trial either way; Pelland's corpus never measured erector spinae. `lowerBack` `indirect` at `.low` on hinges and `stabilizer` on held-torso movements is a mechanical convention chosen to be uniform, not an evidence-backed call. This is the rule's most counterintuitive consequence and the most likely to be challenged by users.
2. **Is there any hypertrophy outcome trial — not EMG — dissociating latissimus dorsi growth from rhomboid/mid-trapezius growth by exercise selection?** None found. `lats` vs `upperBack`, the most-used back distinction in the taxonomy, rests on Ground B alone. NCT07360236 (lat pulldown vs row, latissimus and forearm flexor thickness) appears registered and unreported.
3. **`traps` vs `upperBack` has no dissociating trial.** The boundary is settled by decision (§1, §7.2) so authors cannot diverge, but the split itself is Ground B. It is the accepted token most likely to be wrong.
4. **Is there a three-arm trial randomising pressing vs lateral-plane vs posterior-plane shoulder work with all three deltoid heads measured?** None found. Every head-specific deltoid trial located is single-head. The strongest-feeling split in the taxonomy is justified structurally, not empirically.
5. **`abs` vs `obliques` has no outcome evidence.** No trained-lifter trial separates rectus abdominis from oblique growth by exercise selection. Ground B only, and `obliques` ships as presence-only.
6. **Has Chaves 2020's regional pec result been replicated in trained lifters, at a realistic frequency, or by MRI volume?** A clean replication reopens the `upperChest` decision — the rejection most likely to be revisited. NCT07539337 exists; details were not retrievable.
7. **Does adductor magnus (or any `counted` token) have a defensible weekly-set landmark anywhere?** If one is found, the `modelled`/`counted` line moves, which is purely additive.
8. **Does MacroFactor already weight indirect sets fractionally?** Their docs are silent and they are the most science-literate competitor. If they do, the resolution argument must stand on its own footing (Hevy's undifferentiated `shoulders` cannot carry a front-delt indirect credit regardless of what anyone else does) — which it does, but the differentiator framing would be wrong.
9. **Does SQLiteData silently drop a `CKRecord` field with no matching local column, or error?** Unverified from the checked-out documentation. It decides how safe a v2-added column is, and therefore how much weight the in-column JSON grammar has to carry. The grammar decision in §4.5 is deliberately robust to either answer.
10. **Should the `≥ N` lower-bound rendering apply per-muscle or per-period?** §4.4 specifies per-period-with-a-narrow-trigger; whether users read "≥ 12 sets" as informative or broken is untested.
11. **Is `.high` ever reachable in practice?** It requires a controlled trial measuring that muscle's growth from that movement. Across the 50 seeded entries, plausibly zero attributions qualify. If the answer is zero at 240 entries too, the tier is dead weight and the UI must not imply it exists.
12. **The ~25-fractional-set certainty boundary is a convention.** The paper says "few studies have explored ~25+ fractional weekly sets"; the exact cut point is ours.
13. **What vocabulary does MuscleWiki use?** Cloudflare-blocked in every pass (musclewiki.com/directory → HTTP 403). If a widely-used consumer reference has trained users to expect a granularity we are not offering, this analysis missed it.
14. **Should CSV/JSON export emit raw keys or display names?** Raw keys make a round-trip lossless; display names are what a reader expects. Note the `MuscleGroup`/`Muscle` raw-value collision on `glutes` and `neck` — any export must namespace.
15. **Is "Not recognised" the right user-facing label, or should the raw key sit behind a diagnostic disclosure?** Hiding it entirely is cleaner but costs support the ability to diagnose a bad row from a screenshot.
16. **Should users be allowed to author `stabilizer` on their own exercises,** or is role selection curated-only with user rows restricted to direct/indirect? A three-way choice invites mis-tagging that then feeds their own volume maths.
17. **A one-person pass over 240 entries at 260–340 hours will drift, and the drift will be systematic** (the author's model of the G3 procedure will move) rather than random, so spot-checks will miss it. No second reviewer is in the plan.