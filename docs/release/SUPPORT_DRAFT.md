# Hardset support — review draft

Before publishing: choose a monitored contact route, identify the operator, and
host this page at a public HTTPS URL. App Store Connect needs that support URL.
Do not publish this draft with an unconfigured contact section.

## Record a workout

1. Choose a gym if you want to identify individual machines. You can start without
   one and add it during a workout.
2. Tap Start workout, then Add movement. Search the catalogue or add a custom
   movement when needed.
3. Enter the weight and repetitions, then tap the check to log the set. A green
   logged state means the save succeeded. Numbers entered without logging are
   drafts and are not promised to survive closing the app.
4. Add more sets or movements. Choose a rest duration when you want a timer.
5. Tap Finish workout and confirm. Open History to read the saved receipt.

## Correct a mistake

Long-press a logged set for Undo log or Edit set. Use a movement's options to
remove it. Discarding an active workout and deleting saved history require
confirmation. These actions remove data; an export cannot currently be imported
as a Hardset database restore.

## Change weight units

Open Settings from any main tab and select kilograms or pounds. Saved sets keep
their original stored loads; changing the unit converts their display. Unitless
Strong CSV weights are interpreted using the selected unit shown before import.

## Protect your history

The current build says Saved on this iPhone only in Settings. It does not sync
workouts to another device. Deleting the app deletes local history. Reinstall
an update over the existing app when keeping that history.

Use Settings → Your data to prepare and share a CSV, JSON, or SQLite copy. Save
it somewhere you control. JSON and SQLite can include copied Apple Health data.
Hardset's exports are readable copies, not an in-app restore format.

## Rest alarms

Grant alarm access if you want system alerts outside the app. If access is denied,
the in-app timer remains available and the banner offers Open Settings. A
scheduling failure offers Retry. If saved timer state could not be recovered,
Reset rest timer clears only that timer state and keeps workouts intact.

Background alerts, Focus, and Lock Screen behavior still need to be verified on
the release build before this support text promises their behavior publicly.

## Apple Health

Connection is optional. Choose Connect Apple Health in Settings, then use the
explicit copy or send actions. Access is controlled in Apple Health. Denied read
access can look like an empty result; it does not prove you have no Health data.
Changing permissions does not delete existing copies or Health records.

## Lifetime purchase

The optional one-time purchase unlocks the deep muscle map. Use Restore purchases
with the Apple Account that bought it. A temporary product-loading failure does
not mean a previous purchase has been lost. Core logging, history, importing and
exporting do not require Lifetime access.

Development builds include the map and say that nothing was purchased. This
does not verify the App Store purchase flow; the release must be tested with
Apple's sandbox before publication.

## Contact

The final page needs a monitored support address or form. Ask for the app version,
iOS version, what happened, and steps to reproduce. Never ask for an Apple
Account password or payment-card details. Only request workout or Health exports
when necessary and with the person's informed choice.
