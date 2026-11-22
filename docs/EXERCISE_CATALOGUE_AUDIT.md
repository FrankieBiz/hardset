# Catalogue expansion audit

The original 50 entries are retained byte for byte, including names, modalities, roles,
citations and permanent ids. New ids are fixed lowercase UUID literals generated offline
with UUIDv5, URL namespace, and `https://hardset.app/catalog/v1/<slug>`; that recipe is
authoring provenance, never an on-device identity generator. Renaming never regenerates ids.

## Evidence boundary

The source corpus is `docs/research/tax-spec.md` §1 (muscle/action definitions), §2
(limits on subdivisions) and §5 (loaded-action attribution), plus the corrected,
ratified `docs/MuscleTaxonomy-spec.md` §5 and §7.5. Earlier `tax-research.md` proposals
are superseded where the ratified spec corrects them, particularly high certainty,
grip credit, and the squat/glute outcome claim. `tax-research.md:41` explicitly
defines elbow flexion, hip extension, adduction, abduction, trunk flexion, rotation,
lateral flexion, scapular elevation/retraction and shoulder extension/adduction.

Every new dynamic contribution is `anatomy`, with a citation naming its loaded action
and corpus section. These are anatomical inferences under G1–G3, **not claims that
the exact variant was tested**. No new entry uses trial evidence as a proxy for a
different machine, a head-specific benefit, an EMG ranking, or a fitted set weight.
All new certainty is moderate or low. New grip and held-posture entries explicitly
cite the zero-credit convention under G2. Lists cover the app's 22-token vocabulary,
not every anatomical muscle. Unlisted balance demands do not earn growth credit.

## Load and equipment

Keep the existing unit-aware fallback: **2.5 kg or 5 lb** (`WeightUnit.plateIncrement`),
overridden by the physical machine's configured step (`machineIncrementKg`). No
manufacturer stack, unloaded sled resistance, pulley ratio or dumbbell increment
is invented. Small isolation loads may require a smaller physical-machine setting;
the catalogue does not assert equipment-specific precision. Bodyweight remains
added load only, with no estimated 1RM. Smith and lever/plate-loaded devices are
`machine`; a landmine uses a barbell and is `barbell`. Assisted devices are deferred
because the existing positive added-load model cannot honestly represent assistance.

## Authored additions

Each row states the execution that supports the literal roles in `ExerciseCatalog.v1`.
D = direct, I = indirect, S = stabilizer (weight zero). A parenthesized `low` marks
execution-dependent attribution; everything else is moderate.

| Movement / permanent slug | Modality | D | I | S | Execution and source limits |
|---|---|---|---|---|---|
| Horizontal Leg Press (`horizontal-leg-press`) | machine | quadriceps | glutes (low), adductors (low) | — | Seated horizontal sled; knee-dominant range, hip extensors secondary; no transfer of the squat trial to this machine. |
| Single-Leg Press (`single-leg-press`) | machine | quadriceps | glutes (low), adductors (low) | — | One leg on the sled; knee-dominant range, no assertion that a particular foot position isolates a region. |
| Smith Machine Squat (`smith-machine-squat`) | machine | quadriceps | glutes (low), adductors (low) | abs, lowerBack | Guided bar; conservative hip-extensor secondary credit, not the back-squat outcome override. |
| Pendulum Squat (`pendulum-squat`) | machine | quadriceps | glutes (low), adductors (low) | — | Guided squat arc; knee-dominant execution, no manufacturer muscle claims. |
| Belt Squat (`belt-squat`) | machine | quadriceps | glutes (low), adductors (low) | abs | Hip belt loads a knee-dominant squat; no bar held and no grip credit. |
| Goblet Squat (`goblet-squat`) | dumbbell | quadriceps | glutes (low), adductors (low) | forearms, abs, upperBack | One dumbbell held at chest; the hold is stabilisation. |
| Dumbbell Front Squat (`dumbbell-front-squat`) | dumbbell | quadriceps | glutes (low), adductors (low) | forearms, abs, upperBack | Two dumbbells at shoulders, distinct loading from a goblet squat. |
| Barbell Split Squat (`barbell-split-squat`) | barbell | quadriceps | glutes (low), adductors (low) | forearms, abs, lowerBack | Both feet on floor; knee-dominant stationary split stance. |
| Dumbbell Reverse Lunge (`dumbbell-reverse-lunge`) | dumbbell | quadriceps | glutes (low), adductors (low) | forearms, abs | Step back and return; hip credit remains secondary because stride and depth vary. |
| Dumbbell Walking Lunge (`dumbbell-walking-lunge`) | dumbbell | quadriceps | glutes (low), adductors (low) | forearms, abs | Forward travelling lunge, not a grip-only variant. |
| Dumbbell Step-Up (`dumbbell-step-up`) | dumbbell | quadriceps | glutes (low) | forearms, abs | Knee-dominant step onto a box; height-dependent hip extension receives low secondary certainty. |
| Smith Machine Split Squat (`smith-machine-split-squat`) | machine | quadriceps | glutes (low), adductors (low) | abs | Stationary split squat under a guided bar; rear foot on floor. |
| Single-Leg Extension (`single-leg-extension`) | machine | quadriceps | — | — | One knee extends against a shin pad. |
| Standing Leg Curl (`standing-leg-curl`) | machine | hamstrings | gastrocnemius (low) | — | Standing knee flexion; gastrocnemius synergy is anatomical, not a curl growth finding. |
| Single-Leg Seated Leg Curl (`single-leg-seated-leg-curl`) | machine | hamstrings | gastrocnemius (low) | — | One knee flexes in the seated curl; no new head-specific claim. |
| Nordic Hamstring Curl (`nordic-hamstring-curl`) | bodyweight | hamstrings | gastrocnemius (low) | abs, glutes | Controlled knee extension/flexion with hips held; corpus: tax-spec §2.5, Bourne 2017, DOI 10.1136/bjsports-2016-096130. |
| Dumbbell Romanian Deadlift (`dumbbell-romanian-deadlift`) | dumbbell | hamstrings, glutes | — | forearms, abs, lowerBack | Hip hinge with slight fixed knee bend; trunk and grip hold still. |
| Single-Leg Romanian Deadlift (`single-leg-romanian-deadlift`) | dumbbell | hamstrings, glutes | — | forearms, abs, lowerBack | Loaded single-leg hinge; balance is not extra hip-abductor growth credit. |
| Smith Machine Romanian Deadlift (`smith-machine-romanian-deadlift`) | machine | hamstrings, glutes | — | forearms, abs, lowerBack | Guided hip hinge; not a lumbar-extension movement. |
| Barbell Good Morning (`barbell-good-morning`) | barbell | hamstrings, glutes | — | forearms, abs, lowerBack | Bar on upper back, hip hinge with fixed slight knee bend. |
| Cable Pull-Through (`cable-pull-through`) | cable | glutes, hamstrings | — | forearms, abs, lowerBack | Cable resists hip extension; lumbar spine held still. |
| Machine Hip Thrust (`machine-hip-thrust`) | machine | glutes | hamstrings (low) | abs | Bent-knee hip extension; hamstring credit is execution-dependent anatomical inference. |
| Dumbbell Hip Thrust (`dumbbell-hip-thrust`) | dumbbell | glutes | hamstrings (low) | abs | Shoulders on bench; dumbbell rests across hips, no grip training credit. |
| Glute Bridge (`glute-bridge`) | bodyweight | glutes | hamstrings (low) | abs | Shoulders on floor; shorter hip-extension range than bench-supported thrust. |
| Cable Glute Kickback (`cable-glute-kickback`) | cable | glutes | hamstrings (low) | abs | Ankle cuff, hip extends with knee angle held; avoid lumbar swinging. |
| Hip Extension Machine (`hip-extension-machine`) | machine | glutes | hamstrings (low) | abs | Thigh-pad hip extension with fixed knee angle, not a back-extension machine. |
| Hip Adduction Machine (`hip-adduction-machine`) | machine | adductors | — | — | Thigh pads resist hip adduction; tax-spec §7.5 explicitly calls for this movement. |
| Hip Abduction Machine (`hip-abduction-machine`) | machine | hipAbductors | — | — | Thigh pads resist hip abduction; no glute-max region or manufacturer isolation claim. |
| Standing Cable Hip Abduction (`standing-cable-hip-abduction`) | cable | hipAbductors | — | abs | Ankle cuff resists moving leg out to side; standing-leg balance remains uncredited. |
| Leg Press Calf Raise (`leg-press-calf-raise`) | machine | gastrocnemius, soleus | — | — | Straight knees, ankle plantarflexion only; anatomical transfer of tax-spec §2.13 knee-position distinction, not a machine-specific trial. |
| Single-Leg Dumbbell Calf Raise (`single-leg-dumbbell-calf-raise`) | dumbbell | gastrocnemius, soleus | — | forearms | Straight-knee unilateral heel raise; free hand supports balance. |
| Smith Machine Calf Raise (`smith-machine-calf-raise`) | machine | gastrocnemius, soleus | — | forearms, abs | Guided standing straight-knee heel raise; no claim about machine leverage. |
| Decline Barbell Bench Press (`decline-barbell-bench-press`) | barbell | chest | frontDelts, triceps | forearms | Declined bench, loaded shoulder adduction and elbow extension; chest stays one token. |
| Decline Dumbbell Bench Press (`decline-dumbbell-bench-press`) | dumbbell | chest | frontDelts, triceps | forearms | Independent dumbbells on declined bench; no lower-chest isolation claim. |
| Smith Machine Bench Press (`smith-machine-bench-press`) | machine | chest | frontDelts, triceps | forearms | Guided bar over flat bench; machine history stays separate from free-bar history. |
| Incline Smith Machine Press (`incline-smith-machine-press`) | machine | chest | frontDelts, triceps | forearms | Guided incline press; no attribution to a separate upper-chest region. |
| Incline Chest Press Machine (`incline-chest-press-machine`) | machine | chest | frontDelts, triceps | forearms | Inclined lever or selectorized press; actions, not manufacturer muscle labels. |
| Single-Arm Chest Press Machine (`single-arm-chest-press-machine`) | machine | chest | frontDelts, triceps | forearms, abs | One independent machine lever; anti-rotation is held posture and credits zero. |
| Cable Chest Press (`cable-chest-press`) | cable | chest | frontDelts, triceps | forearms, abs | Standing horizontal cable press; torso held still. |
| Single-Arm Cable Chest Press (`single-arm-cable-chest-press`) | cable | chest | frontDelts, triceps | forearms, abs | Unilateral cable press with fixed torso; no rotational oblique credit. |
| Dumbbell Floor Press (`dumbbell-floor-press`) | dumbbell | chest | frontDelts, triceps | forearms | Floor limits shoulder extension; no claim of equal stimulus to full-range bench. |
| Push-up (`push-up`) | bodyweight | chest | frontDelts, triceps | abs | Loaded shoulder adduction and elbow extension; straight trunk is stabilisation. |
| Feet-Elevated Push-up (`feet-elevated-push-up`) | bodyweight | chest | frontDelts, triceps | abs | Feet on bench; angle/load differs from floor push-up, without a regional growth claim. |
| Dumbbell Fly (`dumbbell-fly`) | dumbbell | chest | frontDelts | forearms, biceps | Flat bench; elbows hold a slight bend, so biceps do not receive moving-joint credit. |
| Incline Dumbbell Fly (`incline-dumbbell-fly`) | dumbbell | chest | frontDelts | forearms, biceps | Incline bench fly; no separate upper-chest token. |
| Single-Arm Cable Fly (`single-arm-cable-fly`) | cable | chest | frontDelts | forearms, abs, biceps | One cable, fixed elbow and torso; no anti-rotation credit. |
| Shoulder Press Machine (`shoulder-press-machine`) | machine | frontDelts | sideDelts, triceps | forearms | Seated supported overhead press; inferred analogue of corpus shoulder presses. |
| Smith Machine Shoulder Press (`smith-machine-shoulder-press`) | machine | frontDelts | sideDelts, triceps | forearms | Seated upright bench under guided bar. |
| Standing Dumbbell Press (`standing-dumbbell-press`) | dumbbell | frontDelts | sideDelts, triceps | forearms, abs | Standing overhead press; abdominal bracing contributes zero sets. |
| Single-Arm Dumbbell Press (`single-arm-dumbbell-press`) | dumbbell | frontDelts | sideDelts, triceps | forearms, abs | One standing dumbbell overhead; torso held still. |
| Single-Arm Landmine Press (`single-arm-landmine-press`) | barbell | frontDelts (low) | chest (low), triceps | forearms, abs | Anchored bar pressed forward/up; angle-dependent shoulder excursion makes front-deltoid and chest roles low confidence; barbell modality follows the implement. |
| Lateral Raise Machine (`lateral-raise-machine`) | machine | sideDelts | — | — | Upper-arm pads resist shoulder abduction; no hand-held grip required. |
| Cable Front Raise (`cable-front-raise`) | cable | frontDelts | — | forearms, abs | Cable resists shoulder flexion; no elbow movement. |
| Dumbbell Front Raise (`dumbbell-front-raise`) | dumbbell | frontDelts | — | forearms, abs | Dumbbells raised forward through shoulder flexion, without trunk swing. |
| Bent-Over Dumbbell Reverse Fly (`bent-over-dumbbell-reverse-fly`) | dumbbell | rearDelts | upperBack | forearms, abs, lowerBack | Hip hinge held; horizontal shoulder abduction and scapular retraction, lumbar hold credits zero. |
| Cable Reverse Fly (`cable-reverse-fly`) | cable | rearDelts | upperBack | forearms, abs | Standing cables resist horizontal shoulder abduction; fixed torso. |
| Single-Arm Pulldown Machine (`single-arm-pulldown-machine`) | machine | lats | upperBack, biceps | forearms, abs | One independent lever pulls the humerus down from overhead; plate-loaded machine history remains separate from cable history. |
| Chest-Supported T-Bar Row (`chest-supported-t-bar-row`) | machine | upperBack | lats, rearDelts, biceps | forearms | Dedicated lever machine with chest pad, rather than an unsupported anchored barbell; no lumbar movement credit. |
| Pulldown Machine (`pulldown-machine`) | machine | lats | upperBack, biceps | forearms | Independent lever/plate-loaded vertical pull, distinct from cable lat pulldown. |
| Single-Arm Cable Pulldown (`single-arm-cable-pulldown`) | cable | lats | upperBack, biceps | forearms, abs | One handle pulls overhead humerus down, with fixed trunk. |
| Seated Row Machine (`seated-row-machine`) | machine | upperBack | lats, rearDelts, biceps | forearms | Supported torso; row with meaningful scapular retraction, not an elbows-tucked lat isolation claim. |
| Single-Arm Seated Row Machine (`single-arm-seated-row-machine`) | machine | upperBack | lats, rearDelts, biceps | forearms, abs | One independent row lever; trunk rotation held still. |
| T-Bar Row (`t-bar-row`) | barbell | upperBack | lats, rearDelts, biceps | forearms, abs, lowerBack | Unsupported anchored barbell row; barbell modality rather than machine; lumbar hold has zero credit. |
| Chest-Supported Dumbbell Row (`chest-supported-dumbbell-row`) | dumbbell | upperBack | lats, rearDelts, biceps | forearms | Prone on incline bench; shoulder extension, elbow flexion and scapular retraction. |
| Inverted Row (`inverted-row`) | bodyweight | upperBack | lats, rearDelts, biceps | forearms, abs | Body pulls toward fixed bar; no body-mass-derived estimated max. |
| Single-Arm Cable Row (`single-arm-cable-row`) | cable | upperBack | lats, rearDelts, biceps | forearms, abs | Unilateral seated cable row with scapular retraction; held torso, no rotation credit. |
| Dumbbell Shrug (`dumbbell-shrug`) | dumbbell | traps | — | forearms | Scapular elevation against dumbbell load; no elbow curl or rolling claim. |
| Smith Machine Shrug (`smith-machine-shrug`) | machine | traps | — | forearms | Guided bar, dynamic scapular elevation. |
| Cable Shrug (`cable-shrug`) | cable | traps | — | forearms | Low cable resists scapular elevation. |
| Cable Curl (`cable-curl`) | cable | biceps | — | forearms | Standing low cable elbow flexion; held wrist is not forearm training. |
| High Cable Curl (`high-cable-curl`) | cable | biceps | — | forearms, sideDelts | Upper arms held out to side, elbows flex against high cables; shoulder hold is zero credit. |
| Bayesian Cable Curl (`bayesian-cable-curl`) | cable | biceps | — | forearms | Upper arm held behind torso; elbow flexion only; no long-head or lengthened superiority claim. |
| Dumbbell Preacher Curl (`dumbbell-preacher-curl`) | dumbbell | biceps | — | forearms | Free dumbbell on preacher pad; distinct from original machine preacher curl. |
| Concentration Curl (`concentration-curl`) | dumbbell | biceps | — | forearms | Seated, upper arm supported against thigh, elbow flexion. |
| Spider Curl (`spider-curl`) | dumbbell | biceps | — | forearms | Prone incline bench, upper arms hang forward; no biceps-head split. |
| Triceps Extension Machine (`triceps-extension-machine`) | machine | triceps | — | forearms | Supported upper arms, lever resists elbow extension. |
| Single-Arm Cable Pushdown (`single-arm-cable-pushdown`) | cable | triceps | — | forearms | One high-cable handle, upper arm held at torso. |
| Dumbbell Overhead Triceps Extension (`dumbbell-overhead-triceps-extension`) | dumbbell | triceps | — | forearms | One dumbbell held in both hands overhead; no long-head isolation claim. |
| Single-Arm Dumbbell Overhead Extension (`single-arm-dumbbell-overhead-extension`) | dumbbell | triceps | — | forearms | One arm extends the elbow overhead; shoulder angle held. |
| Lying Dumbbell Triceps Extension (`lying-dumbbell-triceps-extension`) | dumbbell | triceps | — | forearms | Supine, independent dumbbells, elbow extension with upper arms held. |
| Dumbbell Triceps Kickback (`dumbbell-triceps-kickback`) | dumbbell | triceps | — | forearms, rearDelts, lowerBack | Supported hinge, upper arm held behind torso; elbow extension, shoulder and trunk held. |
| Cable Triceps Kickback (`cable-triceps-kickback`) | cable | triceps | — | forearms, rearDelts, lowerBack | Low cable, upper arm held behind torso, elbow extension without shoulder swing. |
| Barbell Wrist Curl (`barbell-wrist-curl`) | barbell | forearms | — | — | Forearms supported, dynamic loaded wrist flexion; grip convention does not exclude actual wrist work. |
| Barbell Reverse Wrist Curl (`barbell-reverse-wrist-curl`) | barbell | forearms | — | — | Forearms supported, dynamic loaded wrist extension, not a grip-only variation. |

## Movement counts

Each movement is counted once by its primary muscle and the app's region partition, not once per contribution.

| Region | Original | Added | Total |
|---|---:|---:|---:|
| Chest | 8 | 14 | 22 |
| Shoulders | 6 | 10 | 16 |
| Back | 10 | 13 | 23 |
| Arms | 11 | 15 | 26 |
| Core | 2 | 0 | 2 |
| Legs (including calves) | 12 | 26 | 38 |
| Glutes | 1 | 6 | 7 |
| Neck | 0 | 0 | 0 |
| **Total** | **50** | **84** | **134** |
