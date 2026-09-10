# Putting Hardset on your phone, and what to look for

Read this the night before. The install is fifteen minutes if nothing surprises you, and the part
that most often surprises people is signing.

---

## 1. Which path are you on

**Everything hinges on whether you have a paid Apple Developer Program membership**, because iCloud
/ CloudKit and push notifications are paid-only capabilities. A free Apple ID can still put the app
on your own phone — it just cannot have those two, and the app already runs local-only when sync
cannot start.

| | Paid membership | Free Apple ID |
|---|---|---|
| Install lasts | 1 year | **7 days**, then reinstall |
| CloudKit sync | Yes | No — local only |
| Everything a gym session touches | Yes | **Yes** |

Sync is not on tomorrow's test list either way: no alarm has ever fired on hardware and no sync has
ever happened, and the rest timer is the thing worth proving first.

## 2. Find your Team ID

Do not copy the value in parentheses from `security find-identity`. That value is part of the
certificate's display name and is not necessarily its Team ID. The Team ID is the certificate
subject's `OU` field. Read it directly:

```bash
security find-certificate -c "Apple Development" -p \
  | openssl x509 -noout -subject -nameopt multiline \
  | sed -n 's/^[[:space:]]*organizationalUnitName[[:space:]]*=[[:space:]]*//p'
```

That prints the 10-character Team ID. On this Mac it is `ZBP387D523`; the certificate display name
ends in `(7R2SW36YX3)`, which is exactly why copying the parenthesized value generated a project
Xcode could not sign.

What that output does *not* tell you is whether the team is paid or free — an "Apple Development"
certificate looks identical either way. Check at
[developer.apple.com/account](https://developer.apple.com/account): a paid membership shows a
Membership section with an expiry date; a free Apple ID does not. If in doubt, use `--local` in
step 3 — it works on both, and the only thing it costs is sync, which is not on tomorrow's list.

If no identity is listed at all: Xcode → Settings → Accounts → add your Apple ID first.

Check free space before the first Release build:

```bash
df -h /System/Volumes/Data
```

Leave at least 4 GB free. A clean Hardset device build uses about 2.8 GB of DerivedData; with only
103 MB free, SwiftPM reported `databaseFull` and code signing ended with an unrelated-looking
"internal error in Code Signing subsystem".

## 3. Generate the project with signing in it

The Xcode project is generated (`Tools/generate_project.py`), so signing goes in through the
generator rather than the Xcode UI — set it in the UI and the next regeneration silently drops it.

**Paid membership:**

```bash
cd ~/dev/hardset && HARDSET_TEAM_ID=YOURTEAMID python3 Tools/generate_project.py
```

**Free Apple ID** — the `--local` flag drops the CloudKit and push entitlements, which a personal
team cannot sign:

```bash
cd ~/dev/hardset && HARDSET_TEAM_ID=YOURTEAMID python3 Tools/generate_project.py --local
```

If Xcode complains the bundle identifier is unavailable, someone else has registered
`com.hardset.app`. Override it locally rather than editing the generator:

```bash
HARDSET_BUNDLE_ID=com.yourname.hardset \
HARDSET_TEAM_ID=YOURTEAMID \
python3 Tools/generate_project.py --local
```

The app, widget and test bundle identifiers move together, so the widget remains embeddable.

## 4. Build to the phone — as Release, not Debug

Open `Hardset.xcodeproj`, plug the phone in, pick it as the run destination.

**Then switch the build to Release: Product → Scheme → Edit Scheme → Run → Build Configuration →
Release.** Debug builds are slower, and the logger — the screen you will touch forty times — is
where that shows. It is a recommendation, not a requirement: a Debug build works.

It used to be a requirement. `HardsetApp` called `assertionFailure` when the sync engine could not
start, which does nothing in Release but **traps in Debug** — and a free-Apple-ID build has no
CloudKit entitlement, so it hit that line on every launch. The default build configuration would
have crashed on launch, at the gym. That is fixed (DECISIONS #35); it now logs and runs local-only.

Then ⌘R. On the phone: Settings → General → VPN & Device Management → trust the developer.

Also worth knowing: `eraseDatabaseOnSchemaChange` is `#if DEBUG`, so your Release build will not
wipe itself. Do not install a *Debug* build over it after a schema change or it will.

## 5. At the gym — in priority order

The app will ask about the rest timer the first time you start a workout. **Pick a real duration**,
not "No timer" — the whole first section depends on it. Say yes to the alarm permission.

### A. The rest timer — nothing here has ever run on hardware

This is the flagship feature and the entire reason for the trip. `DEVICE-CHECKLIST.md` §B is the
long version; these are the four that matter:

1. **It fires at all.** Log a working set, put the phone down, wait.
2. **It fires with the app backgrounded**, and with the phone locked. Look at the Lock Screen and
   the Dynamic Island — you should see the movement name and "Set 2 of 4", not a bare countdown.
3. **It fires through silent mode and through a Focus.** Turn on Do Not Disturb and do a set.
4. **It survives a force-quit.** Log a set, swipe the app away, wait. The alarm should still fire,
   and reopening should show the countdown still running rather than a blank bar.

Also check: the ±15s and skip controls from the Lock Screen, and that a **warm-up starts no timer**.

### B. The two new things

- **Superset.** Long-press a movement's name → "Superset with next movement". Log a set of A —
  *no timer should start*. Log the matching set of B — *now it starts*. That is the whole feature.
- **Drop set.** Log a working set, tap **Drop**, drop the pin, log it. The rest timer must not start
  until the last link of the chain. Check the counts afterwards: a set dropped twice is **one** set
  in the bar and in the week, and its reps still count in the tonnage.

### C. Logging craft, which is the thing you will actually feel

- How many taps does an unchanged set take? It should be one.
- Is the prefill right — last week's numbers, on the machine you are actually standing at?
- Change machines mid-exercise and check the loads re-prefill from the new machine's history.
- Try it with sweaty hands and one earbud in. That is the real test.

### D. Recovery

Mid-workout, force-quit the app and reopen it. Everything logged should come back ticked, with only
the unlogged rows open, and the notes and machine intact.

### E. Before you leave

Finish the workout and read the summary. Then Settings → Export — you should get a CSV of everything
you just did. Open it on the Mac later and check the numbers match what you remember.

## 6. What to write down

Anything that made you hesitate. This app's whole record is that its real defects were found by
using a screen, not reading one — five in the planner, three in the set counts, and none of them by
the 638-test suite. Specifically worth capturing:

- Any moment the app told you a number you did not believe.
- Any tap that did nothing.
- Whether the rest timer ever alerted late, or not at all, and what state the phone was in.
- Anything you wanted to do and could not find.

Then update `DEVICE-CHECKLIST.md` §B and §C — an unchecked box is not "probably fine", and if
something could not be tested, write *why* next to it.
