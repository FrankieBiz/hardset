# Hardset — release runbook (owner-only steps)

This is the ordered list of things only the owner can do. Everything that can be done
without an Apple Developer Program membership is in `site/`, `docs/release/APP-STORE-METADATA.md`
and `docs/release/screenshots/`. The steps below need the membership, the Apple account,
the signing key, the bank/tax details, and the legal declarations. Do them in order; each
step names what to write down so the next person does not derive it again.

The app code and tests are not changed by this kit. Where a step requires a code change
(the HealthKit removal, or the product identifier if the account already has a different
one), it says so and stops; that change belongs on the release branch, not in this
documentation PR.

---

## 0. Values to fill in once, then reuse

| Value | Where it comes from | Write it here |
| --- | --- | --- |
| Apple Developer Team ID | `developer.apple.com` → Membership | **PLACEHOLDER** |
| App Store Connect Apple ID (the app's numeric ID) | App Store Connect → App Information | **PLACEHOLDER** |
| Bundle ID (app) | `Hardset.xcodeproj/project.pbxproj` | `com.francisbisignano.hardset` |
| Bundle ID (widget) | same | `com.francisbisignano.hardset.widget` |
| SKU | owner choice; this kit proposes one | `HARDSET-IOS-1` |
| App name | App Store Connect | `Hardset` |
| Subtitle | `docs/LAUNCH-PLAN.md` §1 | `The log that won't lie to you` |
| Version / build | project | `1.0` / `1` (increment build on every upload) |
| Minimum iOS | project | `26.1` |
| Devices | project | iPhone only, portrait |
| In-App Purchase type | decision D17 | Non-consumable |
| In-App Purchase product ID | `LifetimeAccess.productID` | `com.hardset.app.lifetime` |
| Launch price | decision D17 | **$19.99** |
| Standing price after launch | decision D17 | **$29.99** |
| Marketing URL | published site root | **PLACEHOLDER** |
| Support URL | published `support.html` | **PLACEHOLDER** |
| Privacy Policy URL | published `privacy.html` | **PLACEHOLDER** |
| Review contact phone | owner | **PLACEHOLDER** |
| EU trader status | owner/legal decision | **PLACEHOLDER** |

Exact code locations, so nobody greps twice:

- The single constant the app reads: `LifetimeAccess.productID` in
  `Packages/HardsetKit/Sources/HardsetFeature/LifetimeAccess.swift` (line 37 on
  `31f7c45`), value `com.hardset.app.lifetime`.
- The bundle identifier: `PRODUCT_BUNDLE_IDENTIFIER = com.francisbisignano.hardset` in
  `Hardset.xcodeproj/project.pbxproj` (the app target; the widget and test targets have
  their own suffixes).
- Version: `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 1` in the same file.
- Minimum iOS: `IPHONEOS_DEPLOYMENT_TARGET = 26.1`.
- Health entitlement and usage strings: `Hardset/Hardset.entitlements`,
  `Hardset/Info.plist` (`NSHealthShareUsageDescription`,
  `NSHealthUpdateUsageDescription`).

---

## 1. Buy the Apple Developer Program membership

1. Go to `https://developer.apple.com/programs/` and enroll. The individual membership is
   **$99/year**. An organization enrollment needs a D-U-N-S number and legal-entity
   verification and takes longer.
2. Choose **Individual** or **Organization** deliberately. An individual seller name is
   the person's legal name; an organization shows the company. The site and privacy policy
   currently name **Frankie Bisignano** as the operator. If the App Store seller becomes a
   company, update the operator line in `site/privacy.html`, `site/support.html`,
   `site/index.html`, and this runbook before submitting.
3. Complete the enrollment purchase and wait for the confirmation email. Record the
   **Team ID** in §0.
4. Sign in to `https://appstoreconnect.apple.com` with the same Apple Account. Accept any
   pending agreements.

**Do not proceed until the membership is active.** A personal team cannot create a
distribution certificate, a production provisioning profile, or a real In-App Purchase.

---

## 2. Accept the paid-app agreements and complete tax and banking

An In-App Purchase cannot be tested or sold until this is done.

1. App Store Connect → **Business** (or **Agreements, Tax, and Banking**).
2. Accept the **Paid Applications Agreement**.
3. Complete **Tax** and **Banking** for the countries where the owner is tax-resident.
   Apple will not pay out until these are approved.
4. Wait for the status to show **Active** for the Paid Applications Agreement.

This is also where the **EU trader** declaration lives; see §11. You can do that later,
but do not submit to the EU store without it.

---

## 3. Remove Apple Health for 1.0, or revise the public copy (BLOCKING)

Decision D25 says Apple Health is removed from 1.0. The public site, the description and
the App Privacy answer in this kit are written for that 1.0. The current branch still
links HealthKit; `docs/release/APP-STORE-METADATA.md` §9.1 lists the exact files. Before
archiving:

1. Remove the `HardsetHealth` target and its `HardsetFeature` dependency (or exclude it
   from the 1.0 target), the Health section in `SettingsSheet`, the HealthKit entitlement,
   and both Health usage strings.
2. Build and run the app; confirm Settings has no Apple Health section and the app never
   prompts for Health access.
3. Re-check `site/privacy.html`, `site/support.html`, the description, and the App Privacy
   answer. The "Data Not Collected" answer stays correct either way because local access
   is not collection; the Health sections must match the build.
4. If the owner decides instead to ship HealthKit in 1.0, **stop** and revise the site and
   `APP-STORE-METADATA.md` before archiving. Do not submit a policy that says the app does
   not connect to Health while the build offers it.

Record the decision and the commit that implements it here: **PLACEHOLDER — commit/date**.

---

## 4. Register the App IDs and capabilities

1. `developer.apple.com` → **Certificates, Identifiers & Profiles** → **Identifiers**.
2. Create an App ID for `com.francisbisignano.hardset` (explicit, not wildcard).
3. Enable only the capabilities the 1.0 build uses:
   - **In-App Purchase** (enabled by default for an explicit App ID).
   - **HealthKit** only if §3 keeps it; D25 says no.
   - **Push Notifications**: not needed. The `Info.plist` declares
     `UIBackgroundModes` `remote-notification` for an iCloud build that does not ship in
     1.0; it is not an App ID capability and does not require an entitlement.
   - **iCloud**: **do not enable**. 1.0 is local-only (D7). No CloudKit container.
   - **Live Activities**: the widget uses ActivityKit; the app declares
     `NSSupportsLiveActivities`. If Xcode's Signing & Capabilities adds a Live Activities
     capability, keep it; it is not a server capability.
   - **AlarmKit**: no entitlement and no capability. It needs the
     `NSAlarmKitUsageDescription` string, which is already present.
4. Create the widget App ID `com.francisbisignano.hardset.widget` if the project requires
   a separate identifier, and enable only what the widget uses (no Health, no iCloud).
5. Record the App ID prefixes and any capability changes in §0.

**Check the entitlements after archiving** in §7. A missing required entitlement fails at
runtime; an extra one invites a review question.

---

## 5. Create the app record

1. App Store Connect → **My Apps** → **+** → **New App**.
2. Platform: **iOS**. Name: `Hardset`. Primary language: **English (U.S.)**. Bundle ID:
   `com.francisbisignano.hardset`. SKU: the value in §0. User access: full.
3. Record the numeric **Apple ID** in §0.
4. Do not fill the metadata yet; `docs/release/APP-STORE-METADATA.md` has every field.

---

## 6. Create the In-App Purchase — and close the product-ID trap (BLOCKING)

The app reads exactly one product identifier: `com.hardset.app.lifetime`
(`LifetimeAccess.productID`). The bundle identifier is
`com.francisbisignano.hardset`. A product identifier does **not** have to be prefixed by
the bundle ID, so this is legal, but it is the single most likely reason a purchase will
fail in review. Make the account and the code agree before the archive.

1. App Store Connect → the Hardset app → **Monetization** → **In-App Purchases**.
2. Look for **any** existing product. Write down every product identifier you find:
   **PLACEHOLDER**.
3. Choose one of these two paths and record which:
   - **Path A (recommended, no code change):** create the product with the exact ID the
     app reads, `com.hardset.app.lifetime`. This matches `LifetimeAccess.productID`
     with no edit.
   - **Path B (code change):** if a product already exists under a different identifier
     and cannot be recreated, change `LifetimeAccess.productID` to that exact string on
     the release branch, rebuild, and re-run the purchase tests. Do not create a second
     product for 1.0.
4. Create the product:
   - Type: **Non-Consumable**.
   - Reference name: `Hardset Lifetime` (internal).
   - Product ID: the exact value from §0 / Path A.
   - Price: **$19.99** for launch (D17). Set the standing **$29.99** after the launch
     period; changing a non-consumable's price does not remove the entitlement from
     people who already bought it.
   - Availability: all territories where the app is sold.
   - Localization (English U.S.): display name `Hardset Lifetime`; description
     `Unlocks the deep muscle map. One purchase, no subscription.`
   - Review screenshot: use `docs/release/screenshots/6.9/02-volume.png`, or a capture of
     Settings → Hardset Lifetime. App Review needs to see what the purchase unlocks.
   - Tax category: the default for an app unlock; confirm with the owner's tax adviser.
   - **Cleared for sale**: yes.
5. Attach the In-App Purchase to the 1.0 version when you submit. A first IAP can be
   submitted with the app version; it does not need a separate app.
6. Verify the match before archiving:
   - Read the constant: `rg -n 'productID =' Packages/HardsetKit/Sources/HardsetFeature/LifetimeAccess.swift`
   - Read the account: App Store Connect shows the product ID exactly.
   - They must be byte-for-byte identical. Case matters.

**If they do not match, stop. Do not archive.** A mismatch shows the app's own message,
"The lifetime purchase isn't available right now. Logging, history and exports stay
free.", and the paid feature can never be bought.

---

## 7. Signing, build, and archive

1. Open `Hardset.xcodeproj` in the Xcode version the project's CI uses (26.6 at the time
   of writing). Select the **Hardset** target → **Signing & Capabilities**:
   - Team: the Team ID from §0.
   - Automatically manage signing: on, unless the owner uses manual profiles.
   - Bundle Identifier: `com.francisbisignano.hardset`.
   - Confirm the capabilities from §4. Do not add iCloud.
2. Select the **HardsetWidget** target and set the same team.
3. Set the version and build in the app target's General tab: `1.0` / `1`. Every upload
   needs a new build number.
4. Choose **Any iOS Device (arm64)** as the run destination.
5. **Product → Archive**. Do not archive a simulator build.
6. In the Organizer, select the archive → **Validate App**. Fix anything it reports
   before uploading.
7. Inspect the archive's entitlements and embedded profile before upload:

   ```bash
   APP=$(find ~/Library/Developer/Xcode/Archives -name 'Hardset.app' -path '*.xcarchive/*' | tail -1)
   codesign -d --entitlements :- "$APP"
   ls "$APP/embedded.mobileprovision" 2>/dev/null && echo "DEVELOPMENT PROFILE PRESENT — DO NOT UPLOAD"
   ```

   - The entitlements must contain only what §4 approves. In particular, there must be
     **no** `com.apple.developer.icloud-*` and, after D25, **no**
     `com.apple.developer.healthkit`.
   - An App Store archive must not contain `embedded.mobileprovision`. If it does, the
     build is a development/ad-hoc build: `LifetimeAccess.detectDevelopmentBuild()` would
     include the deep muscle map and show the development note, so the paywall would not
     be tested. Re-export for **App Store Connect**.
8. Confirm the product ID inside the signed build one more time:
   `strings "$APP/Hardset" | grep 'com.hardset.app.lifetime'` should print the ID. (The
   Swift string is in the binary; this is a smoke check, not a substitute for §6.)

---

## 8. Upload and TestFlight

1. Organizer → **Distribute App** → **App Store Connect** → **Upload**. Use Xcode's
   upload, not a script with an app-specific password in shell history.
2. Answer the export-compliance question. The app uses no encryption beyond Apple's
   standard OS and StoreKit transport; use the standard exemption (see
   `APP-STORE-METADATA.md` §7).
3. Wait for processing in App Store Connect → **TestFlight**. Processing can take from
   minutes to an hour.
4. Add the owner as an internal tester, install the TestFlight build on a physical
   iPhone, and run §9. TestFlight builds are App Store-signed, so the deep muscle map
   starts locked and the development note must not appear.
5. If the build is missing an entitlement or crashes at launch, fix it and upload a new
   build; do not reuse the build number.

---

## 9. Purchase test matrix (physical iPhone, TestFlight build)

Use a **sandbox Apple Account** for purchases. On the test iPhone: Settings → App Store →
Sandbox Account (or sign out of the media account and let the purchase prompt offer the
sandbox environment). Do not use the owner's real Apple Account for test purchases.

For every row, record the date, the build number, the result, and a screenshot if it
failed.

| # | Test | Steps | Expected result |
| --- | --- | --- | --- |
| 1 | Fresh purchase | Settings → Hardset Lifetime → Unlock Lifetime · price → confirm with Face ID/password | "Lifetime access is active." The deep muscle map opens. Relaunch: still unlocked. The transaction is finished, so it is not re-offered. |
| 2 | Cancel the payment sheet | Tap Unlock, then cancel at Apple's sheet | No purchase, no error message, map stays locked, the offer is still available. |
| 3 | Pending / Ask to Buy | Use an account with Ask to Buy, or a purchase that Apple marks pending | "Purchase is pending approval." No unlock yet. After approval, the transaction listener unlocks the map without a reinstall; if it does not, relaunch and confirm. |
| 4 | Restore after reinstall | Delete the app, reinstall from TestFlight, Settings → Restore purchases | "Lifetime access restored." Map unlocked. No charge. |
| 5 | Restore with no purchase | Use a sandbox account that never bought it → Restore purchases | "No lifetime purchase was found for this Apple Account." Map stays locked. No crash. |
| 6 | Refund / revocation | Request a refund through Apple for the sandbox purchase; wait for Apple to revoke it, then relaunch the app | `Transaction.currentEntitlements` no longer contains a valid transaction; the map locks again. No crash. If the change has not propagated, relaunch and recheck; record how long it took. |
| 7 | Offline launch with a cached entitlement | After a successful purchase, enable Airplane Mode, force-quit, relaunch | The entitlement is read from the device; the map stays unlocked. The product may not load, but the paid feature must not disappear. |
| 8 | Product unavailable | Use a build whose product ID does not exist in the account, or block the network on a fresh install | "The lifetime purchase isn't available right now. Logging, history and exports stay free." No crash. Restore purchases is still offered. Free logging, history, import and export work. |
| 9 | Free path | On a fresh account with no purchase, log a set, finish, read History, export JSON/CSV, import the JSON | All free features work. The map is the only gated feature. |
| 10 | Development-build sanity | Install a development build with an embedded provisioning profile | The map is included and the app says "Development build: the deep muscle map is included. Nothing was purchased." This is expected and must not be used to judge the App Store paywall. |

Notes:

- The restore path is deliberately available even when the product fails to load.
  `LifetimeAccess.restore()` calls `AppStore.sync()` and checks current entitlements, so a
  product outage does not strand a buyer.
- A purchase made on another device with the same Apple Account arrives through
  `Transaction.updates`; test it if a second device is available.
- If a test fails, capture the app's own message and the Xcode/Console log. The messages
  are defined in `LifetimeAccess.swift`; quote the exact string in the bug report.

---

## 10. Submit the version

1. App Store Connect → the app → the 1.0 version.
2. Paste the metadata from `docs/release/APP-STORE-METADATA.md`: name, subtitle,
   promotional text, description, keywords, categories, age rating, App Privacy, URLs,
   review notes, contact phone.
3. Upload the screenshots from `docs/release/screenshots/6.9/` (required) and
   `6.5/` (if App Store Connect asks for the older size). Do not upscale a smaller image
   and call it native; regenerate with `Tools/render_store_screenshots.sh` instead.
4. Attach the TestFlight build that passed §9.
5. Attach the In-App Purchase from §6. Confirm it shows **Ready to Submit** and is
   included with this version.
6. Set the price: free app, $19.99 IAP. Set availability. If the app should not launch in
   every territory on day one, limit it now, not after approval.
7. Answer **Export compliance** and **Content rights**.
8. **Add for Review** → **Submit to App Review**.
9. Record the submission ID and date in §0.

After approval:

- Release manually if the owner wants a chosen launch moment; otherwise automatic.
- The launch price is $19.99. Change the IAP price to $29.99 after the launch period
  (D17). Existing buyers keep the entitlement.
- Watch the first reviews and the purchase failure messages. A product-ID mismatch shows
  up as "The lifetime purchase isn't available right now"; a missing entitlement shows up
  as an immediate lock after purchase.

---

## 11. EU trader status (Digital Services Act)

This is a legal declaration, not a marketing field. The owner must decide it; this kit
cannot decide it for them.

1. App Store Connect → **Business** → **Compliance** / **Trader Status** (account holders
   and admins only).
2. Declare whether the owner is a **trader** under the EU DSA. Distributing an app with a
   paid In-App Purchase is commercial activity; the conservative reading is **trader**.
   Do not select non-trader merely to avoid publishing contact details.
3. A trader declaration requires a legal name, a postal address, a phone number, and an
   email address. Apple verifies them and displays them on the app's EU App Store product
   page. For an individual, that may be a home address; decide before declaring. A
   business address or a registered agent may be appropriate.
4. If the owner is a non-trader, Apple may still require a declaration; the app's EU
   distribution can be affected if it is missing. Do not submit to EU storefronts with an
   unanswered declaration.
5. Record the declared status and the exact contact details in §0, and keep the
   confirmation email.

This is not legal advice. If the owner is unsure, they should ask a qualified adviser
before declaring.

---

## 12. After submission: what can still go wrong

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| "The lifetime purchase isn't available right now." | Product ID mismatch, product not cleared for sale, or the Paid Applications Agreement is not active. | Close §6; check the product's status and the agreement. |
| Purchase succeeds but the map stays locked. | The build is a development build, or `currentEntitlements` has not refreshed. | Confirm the archive has no embedded profile; relaunch; check `Transaction.currentEntitlements`. |
| Restore finds nothing. | Wrong Apple Account, or the product was never bought on that account. | Use the buying account; Apple's purchase history is authoritative. |
| App Review cannot find the paid feature. | Review notes do not say where the map is, or the IAP is not attached to the version. | Update the notes; attach the IAP. |
| App Review asks about Health access. | The 1.0 build still contains HealthKit. | Execute §3 or revise the copy; do not explain around it. |
| Privacy label rejected. | The App Privacy answer and the manifest disagree. | Check `APP-STORE-METADATA.md` §9; the manifest is the machine-readable source. |
| Screenshots rejected. | Wrong pixel size. | Re-run `Tools/render_store_screenshots.sh`; it verifies 1320x2868 and 1242x2688. |

---

## 13. The short version

1. Buy the membership; accept the paid-app agreement; complete tax and banking.
2. Remove Apple Health for 1.0 or revise the copy.
3. Register the App ID, no iCloud.
4. Create the app record.
5. Create the non-consumable `com.hardset.app.lifetime`; make the code and account agree.
6. Archive an App Store build, validate it, upload it, test it on a physical iPhone.
7. Run all ten purchase tests.
8. Paste the metadata, upload the native screenshots, attach the IAP, submit.
9. Declare EU trader status.
10. Release at $19.99; move to $29.99 after the launch period.
