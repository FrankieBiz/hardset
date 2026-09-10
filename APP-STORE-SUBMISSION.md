# Hardset App Store submission

This is the handoff from an engineering-complete candidate to App Store Connect. A checked repo
item means it was verified from source or a built app; it does not substitute for the account and
physical-device checks below.

## Binary identity

| Field | Candidate value |
|---|---|
| Name | Hardset |
| Version | 1.0 |
| Build | 1 |
| Platform | iPhone |
| Minimum iOS | 26.1 |
| Primary category | Health & Fitness |
| Bundle ID | `com.francisbisignano.hardset` — confirm this final ID in the paid team before upload |
| Business model | Free, with no in-app purchases in the current binary |

If paid features or subscriptions are part of version 1, this binary is not the submission
candidate: implement StoreKit purchase and restore behavior, the paywall, purchase-state handling,
and the required legal disclosures first.

## Listing copy draft

**Subtitle** (26 characters)

> Fast, honest strength logs

**Description**

> Hardset is a focused strength-training logger built for fast use in the gym.
>
> Log work sets, warmups, drops, notes, and effort without fighting the interface. Review progress
> for each exercise and machine, plan rotating training splits, and see transparent seven-day
> volume totals with the methodology explained inside the app.
>
> A rest timer can keep counting through AlarmKit when you leave the app. Your workout history is
> local-first and can sync privately between your Apple devices with iCloud. Bodyweight entries stay
> on the device. Export your logged sets to CSV whenever you want your own copy.
>
> Hardset contains no ads, analytics, tracking, or developer-operated account.

**Keywords** (83 bytes)

`strength,workout,gym,lifting,hypertrophy,volume,progression,rest timer,training log`

Do not make medical, injury-prevention, or guaranteed-result claims in the listing or screenshots.
Hardset records and summarizes training; it does not diagnose or treat a condition and is not a
regulated medical device.

## App Review notes draft

> Hardset has no login, demo account, advertising, analytics, tracking, purchases, or subscription.
> All functionality is available immediately.
>
> To exercise the core flow: tap Start Workout, choose or create a gym, add an exercise, and log a
> set. The first workout asks the user to choose a rest-timer behavior. Alarm permission is requested
> only after the user chooses a timer duration. Progress, History, Plan, and Volume populate from
> logged workouts. Settings contains CSV export, an offline-readable privacy policy, and permanent
> deletion of all Hardset data.
>
> Workout records are local-first and synchronize through the user's private CloudKit database when
> iCloud is available. Bodyweight is intentionally device-only. The app's derived training numbers
> are explained under Settings > How the numbers work.

Add a short note describing anything reviewers cannot discover, and make every backend or CloudKit
environment used by the submitted build live for the review window.

## App privacy answers

The current code has no analytics, ads, tracking, account system, developer server, or third-party
data recipient. On that exact binary, answer **No, we do not collect data from this app** only after
confirming the developer and its partners cannot access the user's private CloudKit records. Apple
defines collection around off-device data accessible to the developer or a partner; Apple-service
processing alone is not automatically developer collection. Re-answer the questionnaire if an SDK,
support upload, account, purchase, or server is added.

The shipped privacy manifest declares no collected data or tracking and declares the UserDefaults
required-reason API. Confirm the manifest is still at the built app-bundle root for every archive.

## Account, legal, and store gates

- [ ] Paid Apple Developer Program membership is active.
- [ ] Regenerate `Hardset.xcodeproj` with the paid team and **without** `--local`. The checked local
      project deliberately omits `CODE_SIGN_ENTITLEMENTS`; it is suitable for local verification,
      not the CloudKit-enabled distribution archive.
- [ ] The final App ID, bundle ID, distribution certificate, provisioning profiles, iCloud
      container, push entitlement, and widget App ID belong to the paid team.
- [ ] The CloudKit development schema is reviewed and deployed to production.
- [ ] Production CloudKit is tested on two physical devices, including offline edits, sign-out,
      account switching, reinstall/restore, and Delete All Data propagation without resurrection.
- [ ] AlarmKit permission, background alert, Lock Screen Live Activity, and Dynamic Island layout are
      tested on physical supported hardware.
- [ ] A stable public privacy-policy URL matches the policy bundled in Settings; put it in App Store
      Connect and `LegalLinks.live.privacyPolicy`.
- [ ] A stable support URL contains real contact information; put it in App Store Connect and
      preferably `LegalLinks.live.support`.
- [ ] Use Apple's standard EULA for the free binary, or configure a valid custom EULA. If a
      subscription is added, expose the Terms of Use link in the binary.
- [ ] Complete App Privacy for the exact uploaded binary.
- [ ] Complete Apple's current age-rating questionnaire. An unrated app cannot be published.
- [ ] Supply 1–10 accurate screenshots. Capture the highest required iPhone portrait resolution;
      a 6.9-inch screenshot may be 1260×2736, 1290×2796, or 1320×2868 pixels and must have no alpha.
- [ ] Set description, subtitle, keywords, category, copyright, availability, pricing, and review
      contact details; proofread them on the product page.
- [ ] Declare EU Digital Services Act trader status and complete verification if distributing in
      the European Union.
- [ ] If the app charges money, finish the Paid Apps Agreement, tax, banking, and pricing setup.
- [ ] Archive with Xcode 26 or newer, validate the archive, upload it, run internal TestFlight, then
      submit the selected build with the review notes above.

## Engineering checks already in the repository

- [x] Opaque 1024×1024 app icon and dark launch appearance.
- [x] Version and build values come from Xcode build settings and appear in Settings.
- [x] Encryption declaration, AlarmKit usage description, and Live Activities declaration.
- [x] Privacy manifest, offline-readable privacy policy, CSV export, and methodology disclosure.
- [x] Permanent deletion of local and synchronized user data, with a regression test for CloudKit
      deletion tombstones.
- [x] Destructive schema-migration fallback removed.
- [x] Retained-v1 database upgrade tested without deleting its existing workout.
- [x] iPhone-only deployment target and embedded ActivityKit widget extension.

## Candidate verification — August 26, 2026

- The complete package run passed: 760 engine-independent tests plus five isolated sync-engine,
  account-change, and CloudKit-deletion tests.
- The `Release` configuration built for an arm64 iPhone 17 simulator with Xcode 26.4 and the iOS
  26.4 SDK, with no emitted build diagnostics.
- The built app is Hardset 1.0 (1), minimum iOS 26.1, device family iPhone. It contains the root
  privacy manifest, the dependency manifests, the asset catalog, and the matching 1.0 (1) widget.
- The optimized binaries are arm64. The required-reason guard scan found none of the file-timestamp
  APIs that would require another declaration.
- The Release app installed and launched on iPhone 17. A retained v1 database upgraded in place;
  both migrations are recorded, `PRAGMA integrity_check` is `ok`, and the prior recovery error is
  absent from the post-upgrade launch log.
- The final interaction candidate keeps launch seeding, large plan/history/volume/progression
  reads, movement searches, export preparation, workout start, and interrupted-workout recovery
  off the UI actor. Its Release launch log contained no Hardset storage, migration, or crash fault;
  the only error-level messages were simulator app-launch measurement telemetry.

Keep the deeper device matrix and evidence log in `DEVICE-CHECKLIST.md`; do not convert an unrun
physical check into a checked item based on a simulator build.

## Apple references

- [Upcoming submission requirements](https://developer.apple.com/news/upcoming-requirements/)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)
- [Set an app age rating](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/)
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- [Submit an app for review](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/)
