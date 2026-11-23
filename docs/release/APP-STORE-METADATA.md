# Hardset — App Store Connect metadata

Everything App Store Connect asks for, written as text the owner can paste. Values that
depend on the developer account or on hosting are marked **PLACEHOLDER** in a way that
cannot be mistaken for final. Character limits were counted with `python3 len()` on the
exact strings below.

Verified against `origin/main` at `31f7c45` unless a line says otherwise. The code
verification notes in §9 are part of this document: the privacy answer that Apple reads
and the code that ships must agree, and one of them currently needs a release decision.

---

## 1. App information

| Field | Value | Notes |
| --- | --- | --- |
| App name | `Hardset` | 30-character limit. |
| Subtitle | `The log that won't lie to you` | 29 / 30 characters. Chosen in `docs/LAUNCH-PLAN.md` §1. |
| Bundle ID | `com.francisbisignano.hardset` | From `Hardset.xcodeproj/project.pbxproj`. Widget: `com.francisbisignano.hardset.widget`. |
| SKU | `HARDSET-IOS-1` | Internal only; the owner may choose another. |
| Primary language | English (U.S.) | The app ships one language. |
| Version | `1.0` | `MARKETING_VERSION = 1.0`. |
| Build | `1` | `CURRENT_PROJECT_VERSION = 1`; increment for every upload. |
| Minimum iOS | `26.1` | `IPHONEOS_DEPLOYMENT_TARGET = 26.1`. |
| Devices | iPhone only, portrait | `TARGETED_DEVICE_FAMILY = 1`; one portrait orientation. |
| Copyright | `© 2026 Frankie Bisignano` | App Store Connect "Copyright" field. |
| Operator | Frankie Bisignano, `frankabisignano@gmail.com` | Public support and privacy contact. |
| Price | Free download | The one-time Lifetime In-App Purchase is the only paid item. |
| Availability | All territories where the app is sold | Do not submit to the EU store before the trader declaration in `RELEASE-RUNBOOK.md` §11. |
| Pre-order | No | The app is submitted when the membership and the build are ready. |
| What's New (1.0) | `First release.` | App Store Connect shows this only for an update; harmless to fill. |
| Demo account | Not required | There is no account or login. |

### 1.1 In-App Purchase record

| Field | Value |
| --- | --- |
| Type | Non-consumable |
| Product ID | `com.hardset.app.lifetime` |
| Reference name | `Hardset Lifetime` |
| Display name (English U.S.) | `Hardset Lifetime` |
| Description | `Unlocks the deep muscle map. One purchase, no subscription.` |
| Launch price | **$19.99** |
| Standing price | **$29.99** after the launch period (D17) |
| Review screenshot | `docs/release/screenshots/6.9/02-volume.png`, or a capture of Settings → Hardset Lifetime |
| Status | Create it in App Store Connect and make it match `LifetimeAccess.productID`; see `RELEASE-RUNBOOK.md` §6. This is a blocking step. |

---

## 2. Promotional text

Limit: 170 characters. This is 167.

```text
A local-only training log for evidence-based lifters. Honest certainty on estimates, machine-separated history, and fractional volume math. No feeds. No subscriptions.
```

---

## 3. Description

Limit: 4000 characters. This is 3,485. Plain text; the blank lines are intentional.

```text
Hardset is a local-only training log for evidence-based lifters. It keeps your workouts on your iPhone, shows where every number comes from, and refuses to invent a target when the research has not settled one.

LOCAL-ONLY IS THE FEATURE
No account. No server. No sync. Your training history is stored in an SQLite database on your iPhone and nowhere else. There is no Hardset cloud to sign into and no company holding your log. That also means the phone is the only copy: export a JSON or CSV file to keep one you can restore, and do not delete the app before you do.

CALIBRATED CERTAINTY
Every estimate says how much it should be trusted. A formula-derived one-rep max is Moderate confidence up to 10 repetitions, Low at 11 and 12, and no estimate is produced above 12. Only a measured single is High. When there is no basis for a number, the app says "Not evaluated" rather than guessing.

MACHINE-LEVEL PROVENANCE
A 200 lb leg press on one sled is not the same lift on another. Hardset keys history to movement and machine, starts a separate series when you switch, and never draws progress across a machine change. If a suggestion comes from another machine, the row says so: "From another machine."

FRACTIONAL VOLUME, WITH THE WORKING SHOWN
A completed working set credits 1.0 to each direct muscle and 0.5 to each indirect one. Tap a muscle's count to see the sets it was worked from. Hardset cites the research behind the scheme and states plainly that the 0.5 weight is an adopted convention, not a finding estimated from the data. There are no weekly set targets, because no target is established for any muscle; the app shows what you did and what was not trained, without a red bar pretending to know your recovery limit.

150 MOVEMENTS, ATTRIBUTED
The catalogue ships 150 movements, each with its complete direct, indirect and stabilising attribution and the anatomy it was inferred from. Add a custom movement when yours is not listed; your attribution is yours. Import past history from an English Strong or Hevy CSV.

BUILT FOR THE GYM FLOOR
- High-contrast monochrome interface for bright gym lighting and chalky fingers.
- A single-thumb numeric keypad with weight-to-reps traversal and the machine's own load steps.
- A rest countdown with a stored deadline, so returning to the app does not restart it, plus system alarms when you grant alarm access.
- A figure scale that makes measurements large and estimates small: size is earned by being a measurement.

YOUR DATA, YOUR COPY
Export every finished workout as CSV, JSON, or SQLite. JSON is the complete restorable copy, including saved workouts and body mass. CSV restores workouts. SQLite is the database itself, for keeping and inspecting, and cannot be read back in. There is no account and no cloud copy. Deleting the app deletes local history, so export first.

HARDSET LIFETIME
The app is free. Logging, history, CSV import, and every export are free. An optional one-time In-App Purchase, Hardset Lifetime, unlocks the deep muscle map. It does not unlock your own history and there is no subscription. $19.99 at launch; $29.99 after the launch period. One purchase, no recurring fee.

WHAT HARDSET IS NOT
- Not a social network: no profiles, followers, likes, or leaderboards.
- Not a cloud subscription: no account, no recurring fee, no server holding your history.
- Not a coaching oracle: no auto-regulated routine and no claim to know your biological recovery rate.
- Not a source of medical advice.
```

The description deliberately does not claim sync, iCloud, Apple Health, a server, or a
subscription. It does not claim a weekly set target. It says the 0.5 credit is an adopted
convention, as `SetCounting.source.methodology` does.

---

## 4. Keywords

Limit: 100 characters. This is 95.

```text
workout log,hypertrophy,lifting log,strength,gym tracker,weightlifting,bodybuilding,rpe,rep max
```

No spaces after commas; App Store Connect counts the commas and the string as typed.
"workout log", "lifting log", and "gym tracker" are the transactional terms;
"hypertrophy", "rpe", and "rep max" are the evidence-based vocabulary; "strength",
"weightlifting", and "bodybuilding" are the broad intent buckets.

---

## 5. Categories and rating

| Field | Value | Reason |
| --- | --- | --- |
| Primary category | Health & Fitness | The app is a training and body-composition log. |
| Secondary category | Sports | Strength training is the subject; Sports is the closest second bucket. |
| Age rating | 4+ | No objectionable content of any kind. |

Age-rating questionnaire answers, each with the reason for the answer:

| Question | Answer | Reason |
| --- | --- | --- |
| Cartoon or fantasy violence | None | No violence, characters, or conflict. |
| Realistic violence | None | No violence. |
| Prolonged graphic or sadistic realistic violence | None | No violence. |
| Profanity or crude humor | None | No user-generated text is shown to anyone; the app's own copy contains no profanity. |
| Mature or suggestive themes | None | No sexual content, nudity, or suggestive themes. |
| Horror or fear themes | None | None. |
| Medical or treatment information | None | The app logs loads, repetitions, and cited exercise-volume research. It does not diagnose, treat, prescribe, or give medication or emergency-care guidance. |
| Health or wellness topics | None | The app reports training data and research methodology; it does not provide health or wellness guidance, a treatment plan, or a diagnosis. If App Review reads the volume disclosures as wellness information, the honest fallback is 9+; the content does not change. |
| Alcohol, tobacco, or drug use | None | None. |
| Gambling | None | No gambling, simulated gambling, or loot boxes. |
| Contests | None | None. |
| Unrestricted web access | No | No web view and no browser. |
| User-generated content | No | No feed, comments, profiles, or sharing inside the app. Exports leave only through the system share sheet the user chooses. |
| Messaging or chat | No | None. |
| Advertising | No | No ads, ad SDK, or ad identifier. |
| Social media | No | No social features, links, or integrations. |
| In-App Purchases | Yes | One non-consumable, Hardset Lifetime. This is disclosed on the product page. |
| Made for Kids | No | Not directed to children; no Kids Category. |

If App Store Connect asks a question this table does not name, answer "None" or "No" and
write the reason in the review notes. There is no content in the app that could justify a
higher rating.

---

## 6. App Privacy

### 6.1 The answer to give

**Data Not Collected.**

Apple defines "collect" as transmitting data off the device in a way that lets the
developer or a third party access it beyond the real-time request. Hardset has no server,
no account, no analytics, and no advertising SDK. Workout data, preferences, and any
export file remain on the device until the user shares the file. StoreKit entitlement
checks happen on the device. Under that definition there is no collected data.

Question-by-question:

| Data type | Answer | Reason |
| --- | --- | --- |
| Contact Info | Not collected | No account, name, email, phone, or address is requested. |
| Health & Fitness | Not collected | Training data is entered by the user and stored locally; it is never transmitted to Hardset. 1.0 does not connect to Apple Health (D25). |
| Financial Info | Not collected | Apple handles payment; Hardset never sees card or bank details. |
| Location | Not collected | No location permission and no location API. |
| Sensitive Info | Not collected | No racial, sexual, religious, political, or biometric data. |
| Contacts | Not collected | No contacts permission. |
| User Content | Not collected | Workouts, notes, and exports stay on the device unless the user shares a file. |
| Browsing History | Not collected | No browser. |
| Search History | Not collected | The movement search is local and is not recorded off device. |
| Identifiers | Not collected | No user ID, device ID, or advertising identifier. |
| Purchases | Not collected | Ruled 23 November 2026; see §9.3. StoreKit is read on device and there is no server-side purchase record held by Hardset. |
| Usage Data | Not collected | No analytics or product-interaction SDK. |
| Diagnostics | Not collected | No crash or performance SDK; Apple's own diagnostics are under Apple's policy. |
| Tracking | No | `NSPrivacyTracking` is false; no tracking domains; no ATT prompt. |
| Third-party advertising | No | No ad SDK. |
| Data linked to the user | Not applicable | Nothing is collected. |
| Data used to track | No | Nothing is collected or tracked. |

**Privacy Policy URL:** `PLACEHOLDER — the published privacy.html URL` (see §8).

### 6.2 What the manifest says

`Hardset/PrivacyInfo.xcprivacy` declares:

- `NSPrivacyTracking` = `false`.
- `NSPrivacyTrackingDomains` = empty.
- `NSPrivacyCollectedDataTypes` = empty.
- `NSPrivacyAccessedAPITypes`: `NSPrivacyAccessedAPICategoryUserDefaults` with `CA92.1`
  (the app's own preferences) and `NSPrivacyAccessedAPICategoryFileTimestamp` with
  `C617.1` (the app's own export folder sweep).

That matches "Data Not Collected". The manifest's comments still describe a private
CloudKit database and an iCloud-entitled build. The 1.0 build has **no iCloud
entitlement** (`Hardset/Hardset.entitlements` contains only `com.apple.developer.healthkit`
today), so the comments are stale, not the machine-readable declarations. Do not edit the
comments in this kit; correct them when the Health decision in §9.1 is executed.

### 6.3 What the code that touches StoreKit and Health does

- `LifetimeAccess` uses StoreKit 2 only: `Product.products(for:)`,
  `Transaction.currentEntitlements`, `Transaction.updates`, and `AppStore.sync()`. There
  is no server, no receipt upload, and no third-party purchase SDK. The entitlement is
  verified on the device and the transaction is finished on the device.
- `HealthBridge` reads body mass and workout summaries from HealthKit and writes
  completed strength workouts and entered body mass, but only after the user chooses
  Connect. `DeviceHealthStore` stores those samples in the local database. Nothing is
  transmitted to Hardset. That code is still present on this branch; see §9.1.

---

## 7. App Review information

**Contact:** Frankie Bisignano · `frankabisignano@gmail.com` · **PLACEHOLDER — phone
number** (App Store Connect requires one; use a number the owner will answer). **Demo
account: not required; there is no account or login.** **Privacy Choices URL: not
applicable** (no tracking, no data sale, no account).

**Review notes (paste):**

```text
Hardset is a local-only iPhone training log. There is no account, no login, no server,
and no network dependency for the core app. Launch it, tap Start workout, tap Add
movement, choose a movement, enter a weight and reps, and tap the check to log a set. A
green seal means the write succeeded. Finish the workout and open History to read the
receipt. Settings → Your data prepares CSV, JSON and SQLite exports; JSON and CSV can be
chosen again under "Restore or bring in workouts".

Hardset Lifetime is one non-consumable In-App Purchase. It unlocks the deep muscle map
on the Volume tab. Logging, history, imports and exports stay free. Use a sandbox Apple
Account to buy it; then use Settings → Hardset Lifetime → Restore purchases to verify
restore. A development build includes the map and says "Nothing was purchased"; an App
Store build does not.

The app stores history on the device only. Deleting the app deletes the history, which
the app states in Settings and on a finished workout's receipt. There is no iCloud sync
and no server copy. The CSV, JSON and SQLite exports are the user's copy; JSON and CSV
are the restorable formats.

Rest alarms use AlarmKit and ask for alarm permission only when the user chooses a rest
timer. The in-app timer works if permission is denied. The app has no web view, no
user-generated content shown to others, no ads, and no analytics.

If the deep muscle map is not visible, the Lifetime product may not have loaded; the free
screens remain usable. The product identifier in the build is
com.hardset.app.lifetime.
```

Do not put sandbox credentials in the review notes. Apple supplies the sandbox
environment; the reviewer signs in with a sandbox Apple Account. The product ID above is
the only identifier the reviewer needs.

**Export compliance:** The app does not implement or use encryption beyond Apple's
standard OS and StoreKit transport. Answer "No" to "Does your app use encryption?" and
use the standard exemption. If App Store Connect asks for a CCATS or classification, the
correct answer is that the app uses only exempt standard encryption; confirm the exact
wording on the upload screen before submitting.

**Content rights:** The app contains no third-party content, trademarks, or media. The
research citations are bibliographic facts, not reproduced text.

**Advertising identifier:** Not used. Do not enable "Contains advertising."

**Sign in with Apple / Game Center:** Not used.

---

## 8. URLs and hosting

Hosting is not chosen yet. These are the only placeholders in this kit. App Store Connect
will not accept the submission until they are real, public HTTPS URLs.

| App Store Connect field | Value |
| --- | --- |
| Marketing URL | `PLACEHOLDER — https://<host>/` (the site root) |
| Support URL | `PLACEHOLDER — https://<host>/support.html` |
| Privacy Policy URL | `PLACEHOLDER — https://<host>/privacy.html` |

The publish steps, including the GitHub Pages default and the owner-only decision, are in
`site/README.md`. After publishing, replace the three placeholders here and in App Store
Connect in the same sitting so the document and the listing cannot drift.

The site's copy is final for the 1.0 decision, subject to the Apple Health verification
in §9.1: local-only, no account, no server, CSV/JSON/SQLite exports with JSON/CSV restore,
the Lifetime limits, deletion, and the operator line. See `site/README.md` for the
pre-publication checklist.

---

## 9. Code verification notes and discrepancies

These are not marketing copy. They are the checks behind the claims above, including the
places where the repository and the decision of record disagree today.

### 9.1 D25 says Apple Health is removed from 1.0; this branch still links HealthKit

The site, the description, and the App Privacy answer are written for a 1.0 that does not
connect to Apple Health, per decision D25. **The code on this branch still does.** Verified
on `31f7c45`:

- `Packages/HardsetKit/Sources/HardsetHealth/HealthBridge.swift` imports `HealthKit` and
  requests read/write authorization.
- `HardsetFeature/HealthSettingsSection.swift` is wired into `SettingsSheet` under
  `#if os(iOS)` and is constructed by `HardsetRootView`.
- `Hardset/Hardset.entitlements` carries `com.apple.developer.healthkit`.
- `Hardset/Info.plist` carries `NSHealthShareUsageDescription` and
  `NSHealthUpdateUsageDescription`.

This is a release blocker for the copy, not a copy problem. D25 stands: the removal is a
separate stream, and this kit does not touch app code. Before the 1.0 archive:

1. Remove the `HardsetHealth` target and its `HardsetFeature` dependency, or exclude it
   from the 1.0 build.
2. Remove the Health section from Settings and the Health usage descriptions and
   entitlement.
3. Re-run the app privacy check and this document. The "Data Not Collected" answer is
   unchanged either way, because local Health access is not collection. The site's
   "Apple Health" section and the support FAQ are the parts that must match.
4. Do not submit until that separate removal has landed. Do not rewrite the site or the
   description to include Apple Health in 1.0; D25 is the decision of record.

### 9.2 The privacy manifest and the App Privacy answer

The manifest declares no collected data and no tracking. The code has no server, no
analytics, and no advertising SDK. The answer above ("Data Not Collected") matches the
manifest and Apple's definition of collection. The manifest's *comments* about a private
CloudKit database are stale for this local-only build. That is a documentation defect in
the app target, not a disagreement that changes the answer; correct the comments when the
Health change touches the target.

### 9.3 Purchase history: the older note is superseded

`DECISIONS.md` §6 says: "Purchase history still must be disclosed in the App Store Connect
questionnaire, where the inheritance rule does not apply." That line predates the removal
of RevenueCat and is **superseded** by the owner's ruling of 23 November 2026. The ruling
is **Purchases: Not collected**.

Apple defines collection as transmitting data off the device in a way that lets the
developer or a third party access it. Hardset has no server, no analytics, and no
StoreKit server call. `LifetimeAccess` reads `Transaction.currentEntitlements` and
`Transaction.updates` on the device; the transaction is verified and finished on the
device. There is nothing to disclose. Do not re-open this question or add a Purchase
History entry; the answer in §6.1 is final for 1.0.

### 9.4 The bundle ID and the product ID do not share a prefix

`PRODUCT_BUNDLE_IDENTIFIER = com.francisbisignano.hardset`, while the code loads
`com.hardset.app.lifetime` (`LifetimeAccess.productID`, the single constant the app
reads). This is legal — a product identifier does not have to be prefixed by the bundle
ID — but it is the most likely submission trap. The runbook makes it a blocking step:
confirm which product exists in App Store Connect and make the account and the code agree.
Do not change the constant in this kit; that is an app-code change and belongs to the
release branch that fixes the account.

### 9.5 There is no in-app privacy policy link on this branch

`docs/release/PRIVACY_POLICY_DRAFT.md` asks for a visible Privacy Policy link in Settings.
No such link exists in `HardsetFeature` on this branch. App Store Connect only requires
the public Privacy Policy URL; the in-app link is a product choice, not a submission
blocker. Adding it is an app-code change outside this kit. If the owner wants the draft's
promise kept, add a link from Settings to the published `privacy.html` in a release
branch and note the URL in that build's review notes.

### 9.6 Movement count

`ExerciseCatalog.v1` contains 150 entries (`rg -c "CatalogExercise\(" ... ` = 150), and
`docs/EXERCISE_CATALOGUE_AUDIT.md` records the 50 → 150 expansion. The old launch plan's
"v1 ships 50" line is stale; the copy here uses 150, per D19.

### 9.7 Price

The app is free. The one non-consumable is $19.99 at launch and $29.99 standing (D17). The
price is set in App Store Connect, not in the app; the app displays `product.displayPrice`,
so it will show whatever the storefront charges. Do not hard-code a price in the copy that
the storefront cannot honor in a given territory.

---

## 10. App icon

The current asset is the documented interim one:
`Hardset/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`, 1024 × 1024, RGB with no
alpha channel. Re-running `Tools/render_interim_icon.py` reproduces it byte for byte
(verified with a pixel diff: no differing pixel). It is a front-on six-plate machine
weight stack with one cyan selector pin on the fourth plate, on a graphite gradient.

It meets the App Store's size and alpha requirements: 1024 × 1024, flattened, no
transparency. The PNG carries no embedded ICC profile; treat it as sRGB and let App Store
Connect confirm on upload. If it warns about the profile, re-export with an explicit sRGB
profile rather than changing the artwork.

**Decision for 1.0: ship the interim asset.** This is deliberate, not a gap. The asset is
legible at small sizes and is not misleading, and it is what 1.0 ships. The owner is
commissioning a proper mark separately, built from D21's Scale and tested at 29 and 60 px.
This kit does not design, generate, or replace it; nothing here should be read as a
pending icon task.

The separate commission should be a deliberate mark built from the app's own visual
signature and palette, not another gradient object:

- One idea, readable at 29 px and 60 px: a stamped measurement numeral, a single
  calibrated plate, or the selector pin on a stack, not all three at once.
- Use the app's plate colours rather than the current teal: action blue `#6FB7FF`, chalk
  `#F3F3F5`, graphite `#050608`. The teal pin is not a token in `DesignTokens.swift`.
- Strong silhouette against both a black and a white Home Screen; no text, no thin
  hairlines, no transparency, no pre-rounded corners (iOS masks the icon).
- Test the 1024 px master, the 60 px Home Screen size, and the 29 px Settings size before
  replacing the asset. Keep the master as a source file outside the asset catalogue.
- Replace it in a dedicated icon change with a new build; do not swap the PNG inside a
  release that is already in review.

The icon is the only store asset not produced by `Tools/render_store_screenshots.sh`; that
is expected, because it is a brand asset rather than a screen.

---

## 11. Submission checklist (metadata side)

- [ ] App name, subtitle, promotional text, description, and keywords pasted exactly.
- [ ] Primary and secondary category set.
- [ ] Age rating questionnaire answered; 4+ expected.
- [ ] App Privacy "Data Not Collected" selected; §9.3 is ruled (Purchases: Not collected).
- [ ] Privacy Policy URL, Support URL, and Marketing URL replaced with live HTTPS URLs.
- [ ] Review notes pasted; contact phone filled.
- [ ] Export compliance answered.
- [ ] Content rights answered.
- [ ] Icon: the interim asset is the deliberate 1.0 choice; no replacement in this kit.
- [ ] Screenshots uploaded from `docs/release/screenshots/` (see its README).
- [ ] In-App Purchase created and attached (see `RELEASE-RUNBOOK.md`).
- [ ] EU trader status answered (see `RELEASE-RUNBOOK.md`).
- [ ] §9.1 Health decision executed or the copy revised.
- [ ] The bundle ID / product ID trap in §9.4 closed.
