# Hardset privacy policy — review draft

This is a local draft for the current local-only app. Before publishing, confirm
the operator's name and contact route, set the effective date, review the signed
release's capabilities, and publish this text at a stable public HTTPS URL. Add
that URL to App Store Connect and a visible Privacy Policy link in Settings.
The draft does not satisfy those release steps by itself.

## Training data

Hardset keeps the workouts you record on your iPhone: movements, gym and machine
names, loads, repetitions, set types, workout times, and notes. It also keeps
preferences such as your weight unit and rest choices. You can use the workout
logger without creating a Hardset account.

The current build does not sync your workout database to iCloud or send it to a
Hardset server. Settings states where your data lives. Device backups are managed
by Apple and your device settings; Hardset does not provide a separate backup or
restore service.

## Apple Health

Hardset 1.0 does not connect to Apple Health, does not request Health access, and
does not read or write Health data. If a future version adds an optional Apple
Health connection, this policy will be updated before that version is released,
and the connection will be off until you choose it.

## Purchases

Apple handles the optional one-time Lifetime purchase. Hardset checks verified
StoreKit transactions on the device to decide whether the deep muscle map is
unlocked. Hardset does not receive your payment-card details. Workouts, personal
history, CSV import, and exports remain available without this purchase.

## Imports, exports, and sharing

A workout CSV you choose is read to prepare a preview and is saved only when you
confirm the import. Import fingerprints are stored on this device to identify
repeat imports.

Exports and workout receipts are shared only through an action you choose.
CSV contains logged training data and machine identifiers. JSON and SQLite
exports also include the device-local tables Hardset holds; in 1.0 that does not
include Apple Health data, because 1.0 does not connect to Apple Health.
The recipient or app you select controls the copies you share. Deleting data in
Hardset does not delete those copies. JSON is the complete restorable copy; CSV
restores workouts; SQLite is for keeping and inspecting and cannot be read back
into Hardset.

## Tracking and third parties

The current app contains no advertising or analytics SDK and does not track you
across other companies' apps or websites. Apple provides the system services
used for purchases, alarms, and device backups under Apple's own policies.

## Retention and deletion

Training records remain on your iPhone until you remove them. Saved workouts
and sets can be deleted through History and workout receipts; an active workout
can be discarded after confirmation. Archiving a gym or machine retains its
training history.

Deleting Hardset removes its local app data, including the workout database and
preferences. Offloading an app, restoring a device backup, and removing
records from Apple Health are different actions controlled by iOS. Exports,
shared receipts, Apple Health records (if any), and Apple's purchase records are
not erased by deleting Hardset. Export anything you want to keep before deletion.

## Changes and contact

Review and update this policy before changing how the app handles data,
including before enabling iCloud sync. The final public page must identify the
operator and a working privacy contact route.
