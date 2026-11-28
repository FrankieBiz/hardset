# Hardset: press one-pager

## What it is

Hardset is an iPhone app for logging weight training. It keeps every set on the phone, with no
account, no server and no sync. It labels each estimated number with how far it can be trusted,
and it shows the sets behind any figure it calculates. Version 1.0 requires iOS 26.1 or later and
runs on iPhone in portrait.

Logging, history, correcting sets, CSV import (English Strong or Hevy files) and every export are free. One non-consumable
purchase, Hardset Lifetime, costs $19.99 at launch and unlocks muscle history: when each muscle
was last trained, the last four weeks against the four before, a lifetime set count and a
twelve-week shape. There is no subscription.

## Who it is for

Lifters who already keep their own records, often in a spreadsheet, and who distrust the figures
workout apps produce because they cannot see how they were made. It is not for anyone who wants a
coach, a plan, a feed or a way to share workouts. It does not sync between devices.

## Three facts you can check in the app

1. **An estimate says how reliable it is.** Log a set of 5 reps and the app shows an estimated
   one-rep max labelled Moderate confidence. Log 11 or 12 reps and the label is Low. Log 13 or
   more and no estimate appears. Only a lifted single is ever labelled High. The same thresholds
   are on the in-app method sheet and on the website.
2. **A weekly count opens to its working.** On the Volume tab, tap a muscle's set count. The
   sheet lists each set that was counted, at 1.0 for a direct muscle and 0.5 for an indirect one,
   and every set that was left out with the reason. The app states that the 0.5 weight is an
   adopted convention, and cites the 2025 paper it follows. The Volume screen has no target line,
   and says why.
3. **Two machines are two histories.** Log the same movement on two different machines and
   Progress shows two separate rows. The app does not draw a line, a record or a percentage change
   across the switch.

A fourth, for anyone testing the privacy claim: the app's code contains no network requests, so
logging a workout works with airplane mode on. (Buying the optional unlock and restoring a
purchase go through the App Store, which is Apple's service, not Hardset's.)

## Two screenshots worth running

Both are in `docs/release/screenshots/6.9/` at 1320 by 2868. They are renders of the real
interface with fixed example data, not captures of a real person's training. Say so in the
caption: "App Store gallery image; example data."

- `01-train.png`: a live workout with a record notice reading "Moderate confidence" beside the
  estimated max, and the rest timer. It shows the one-tap logging and the honesty label in one
  frame.
- `03-progress.png`: Leg Press on two different machines as two separate rows, the second
  marked "no 6-week comparison". It is the clearest picture of the machine rule.

Real-device captures of the same screens are better where they exist.

## What it does not do

No account, no cloud, no sync between devices, no Apple Health connection, no social features, no
coaching or recommended targets. Deleting the app deletes the history on the phone; the export
files are the backup. JSON and CSV exports can be restored in Hardset; a SQLite export is a copy
for inspection and cannot be read back.

## The person

Frankie Bisignano makes Hardset alone.
frankabisignano@gmail.com

For a quote, a build to try, or a question about how a figure is
calculated, write to that address. Questions about the method are welcome and will be answered
with the source.

## Status

As of this writing 1.0 is being prepared and is not yet on the App Store. The site
(https://frankiebiz.github.io/hardset/) carries the current state. Update this page when the
listing is live and before sending it to anyone.
