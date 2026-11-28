# Hardset launch kit

The executable version of `docs/LAUNCH-PLAN.md`: text to paste, a script to film, a tester
programme and a 30-day channel plan. It needs no Apple account to prepare. Nothing here has been
posted, sent or published, and nothing should be until the owner has read it and the relevant
gate below is met.

Every claim about the app was checked against `main` at `95c3fb5`. Where a line depends on
something outside the repository (a subreddit's rules, Apple's TestFlight review, a number of
people), it is marked **unverified** or **owner to confirm**.

Two corrections to older documents, so nobody copies them forward:

- `docs/LAUNCH-PLAN.md` says the catalogue has 50 movements. `main` ships 150
  (`ExerciseCatalog.swift`), and the site and store metadata say 150. This kit says 150 or says
  nothing.
- `docs/LAUNCH-PLAN.md` mentions Apple Health in its checklist and quotes "standard iOS device
  backups" as a safeguard. Hardset 1.0 has no Health connection, and no repository document
  verifies what an iOS backup contains for the app. This kit claims neither. The backup is the
  export.

Gates before anything public:

1. The app is on the App Store, or the post says plainly that it is a TestFlight build and gives
   the link. A post that points at nothing is worse than no post.
2. The disclosure line ("I made this") is in every post. `docs/LAUNCH-PLAN.md` §4 already rules
   this: no sockpuppets, no third-party voice, no incentivised reviews.
3. The owner has read the current rules of each place (sidebar, pinned post, channel topic). This
   kit cannot verify them. If a place bans self-promotion outright, drop that post.

---

## 1. Positioning and the two objections

### The line

> Hardset is a local-only lifting log for people who distrust app numbers. It keeps every set on
> your phone, says when a number is an estimate, and shows the sets behind it.

Short form for a bio or a reply: **A lifting log that shows its working.**

The App Store subtitle stays "The log that won't lie to you" (`APP-STORE-METADATA.md` §1). Use it
as the name of the idea, not as the opening of a post: a lifter who distrusts app numbers also
distrusts the sentence "won't lie to you" from a stranger. Lead with the problem and let the
screen prove it.

What it costs, in one sentence that can be said in any thread: **free to log, keep your history
and export it; one purchase of $19.99 unlocks muscle history.** (D17: $19.99 at launch, $29.99
after the launch period. Do not quote the $29.99 unless asked; do not quote any other price.)

### Objection 1: "Local-only means I'll lose my data."

Honest answer, usable verbatim:

> Yes, if you do nothing. There is no account and no server, so the phone is the only copy, and
> deleting the app deletes the history on it. The protection is the export: Settings writes your
> history as JSON, CSV or SQLite, and JSON restores everything Hardset can restore, including saved
> workouts and body mass. CSV restores workouts. SQLite is a full copy you can open yourself, but
> Hardset cannot read it back. The trade is real: privacy and no account in exchange for you
> remembering to export.

What not to say: that your data is "safe", that iOS backs it up (not verified), or that sync is
coming. Sync is not in 1.0 and this kit promises none. If someone asks, the answer is "not in
1.0, and I won't promise a date."

What to do about it in the product pitch: say the trade first, before the reader finds it. The
site already does ("The trade, stated"); copy that order.

### Objection 2: "$20 when Hevy is free."

Honest answer, usable verbatim:

> You do not have to pay anything to log. Logging, history, correcting sets, CSV import, the
> weekly Volume view and every export are free. The one purchase opens muscle history: when each
> muscle was last trained, the last four weeks against the four before, a lifetime set count and a
> twelve-week shape. If you do not want that screen, there is nothing to buy. If another free app
> already does what you need, use it; Hardset is for people who want the working shown and the data
> kept on the phone.

What not to say: anything about what Hevy or any other app charges or does. It is not verified in
this repository and it changes. Do not call another app dishonest. Do not call the price cheap.
The honest framing is that the paid part is narrow and everything a lifter needs to keep their
own log is free.

---

## 2. Three community post drafts

Rules for all three, written down because they are the easiest to break:

- Disclose in the first lines: "I made this."
- Lead with a problem the reader has. The app arrives in the third paragraph at the earliest.
- No emoji, no exclamation marks, no "excited", no "game changer", no "revolutionary".
- Ask a question that can be answered by criticising the app. Mean it.
- Reply to every comment in the first 48 hours, including the hostile ones. Concede points that
  are right.
- One post per place. Do not cross-post the same text.
- **The first-person lines are drafts for the owner to make true.** "I count weekly sets in a
  spreadsheet", "my log used to show me", "I read where the formula stops" are written as
  plausible openings, not as facts about Frankie. Rewrite each to what actually happened, or cut
  it. Do not post an anecdote that did not happen: this product's whole claim is that it does not
  invent things, and a community that checks numbers will check a story.

The screenshot suggestions use the gallery files in `docs/release/screenshots/6.9/`. Those are
renders of the real views fed fixed fixture data (see that folder's README), not captures from a
phone. In a post, either use a real capture of the same screen from your own phone or say "App
Store gallery image, fixture data" under the image. Do not let a render pass as a screenshot of
real training.

### Post 1: an evidence-based lifting subreddit, weekly thread

The plan names r/naturalbodybuilding and r/weightroom. Which has a weekly thread that allows this
is **owner to confirm** from the current sidebar. Post in the thread, not as a top-level post.

**Title** (if the thread asks for one): `Tool feedback: a log that shows the sets behind a muscle's weekly count`

**Body:**

> I count weekly sets per muscle in a spreadsheet because every app I tried gives me a number I
> can't check. A close-grip bench "counts" for triceps, but how much? Half? Full? The app doesn't
> say, so I can't tell whether its 14 and my 11 disagree about the training or about the
> arithmetic.
>
> I made an iPhone log to fix that for myself, so: I made this, it's called Hardset, and it isn't
> on the App Store yet, I'm running a small TestFlight. A completed working set counts 1.0 for each
> direct muscle and 0.5 for each indirect one, which is the Pelland et al. 2025 scheme. The app
> says the 0.5 is an adopted convention, not something that paper estimated. Tap any muscle's
> count and it lists the sets that made it up and the ones it left out, with the reason. There is
> no weekly target line, because it doesn't think one is established.
>
> What I want from this thread: tell me where the counting is wrong. Which movements would you
> credit differently? Is leaving out the target line the right call or just annoying?
>
> Free to log and export. No account, everything stays on the phone. TestFlight link in a reply if
> anyone wants it, since I'd rather not drop a link in the main post.

**Screenshot:** `02-volume.png` (the Volume screen: "14 working sets in the last 7 days", the muscle
list, and the "no target line" note). It is the one that makes the arithmetic visible.
Alternatively a real capture of the "Worked from" sheet for one muscle.

### Post 2: a general fitness subreddit, self-promotion thread

**Title:** `Self-promo: I got tired of logging apps that merge my leg presses, so I made one that doesn't`

**Body:**

> If you've changed gyms, you know the problem. Your leg press is a 45 degree sled at one gym and
> a horizontal one at the other, 200 lb feels nothing alike, and most apps put both on one graph.
> Either it looks like you got weaker or it hands you a fake record.
>
> I made an iPhone log, Hardset (I'm the developer), that keeps history per movement and per
> machine. Change machines and it starts a second series instead of drawing a line across the
> switch. If it borrows a suggestion from another machine, the row says "From another machine"
> and marks it Low confidence.
>
> It's local-only: no account, no server, no sync in the first version. That means the phone is
> the only copy, so it can export your whole history as JSON, CSV or SQLite, and JSON restores.
> Logging, history and export are free; one $19.99 purchase unlocks muscle history, which is a
> separate screen about when each muscle was last trained. It isn't a social app and it doesn't
> tell you what to do next.
>
> I'd like to hear how you handle the two-gym problem today. A note in your phone? Separate
> exercise names? If there's something it gets wrong for how you actually train, say so.

**Screenshot:** `03-progress.png` (Leg Press on a 45 degree sled and a horizontal cable sled as
two separate rows, "no 6-week comparison" on the second).

### Post 3: a forum or Discord where lifters discuss training logs

The plan names Stronger By Science and 3D Muscle Journey communities. Use a channel or section
about training logs or tools, never a general chat, and **owner to confirm** the place allows tool
posts. If a community asks you to contact a moderator first, do that and wait.

**Title** (forum) or first line (Discord): `Do you trust the 1RM your log shows you?`

**Body:**

> Genuine question for people who keep logs. My log used to show me an "estimated 1RM" for a set
> of 12 and I knew the number was wrong, because those formulas were fitted on low-rep sets. But
> it showed it in the same size and colour as a lift I'd actually done. Nothing told me which
> numbers to believe.
>
> So I built a log (I'm the developer, iPhone only) where size and wording track certainty. A
> weight and reps you typed are big. An estimate is small and carries a phrase: "Moderate
> confidence" up to 10 reps, "Low" at 11 and 12, and no estimate at all above 12. Only a measured
> single is ever High. When a set sets a record, the notice says which set it beat and "Worked
> from" shows the formula and every set it left out.
>
> I'm not sure the thresholds are right. 10 and 12 are my reading of where the formula stops being
> reliable, and I'd like people who know the literature better to say where they'd put them, or
> whether showing an estimate at all is the mistake.
>
> If you want to try it, it's on TestFlight and free to log. There's no account and nothing leaves
> the phone.

**Screenshot:** `01-train.png` (the live session with the record notice and the "Moderate
confidence" phrase). Note that this image is a render with fixture data; the cropping hides the
title and machine line by design.

---

## 3. Thirty-second demo script

Shot on the phone, portrait, screen recording with no voiceover required. Burn in at most one
caption per beat. Target 30 seconds; a 35 second cut is fine, 45 is not.

**Preparation (not filmed):**

- Install a build with a movement that has at least a few sets of history on the machine you will
  use. Hardset only announces a record on the same machine as its history; with no history there
  is nothing to beat and the key beat does not happen.
- Choose a set that beats the previous best by one rep, so the record is modest and believable.
- Switch on Do Not Disturb, set the phone to portrait, hide notifications, and record at the
  phone's native resolution. Do not add a device frame.
- Rehearse the keypad beat three times. Weight, Next, reps, Log set has to be one fluid motion.

| Time | Do | Caption (on screen) | The viewer should understand |
| --- | --- | --- | --- |
| 0:00-0:04 | Open Hardset on the Train tab and tap the Start button on the saved workout. | Starts in one tap. | There is no sign-in, no feed, no setup between the lifter and the first set. |
| 0:04-0:09 | On the first set row, tap its check to log it as prefilled. A haptic is felt on the phone, the check stamps, and the rest bar arrives. | One tap per set. | Logging a set that went as planned costs one tap. The rest timer starts from the length the lifter chose for that movement. |
| 0:09-0:16 | On the next set, tap the weight. The keypad opens. Type a weight, tap Next, type the reps, tap Log set. | Weight, reps, log. No keyboard. | Changing a set is still fast and happens on the app's own keypad, not the system keyboard. |
| 0:16-0:20 | The record notice appears: the movement and "New record", a line such as "Best estimated 1RM: About ... up from about ...", and "Moderate confidence". Hold on it for a full second. | It says it is an estimate. | The app announces a record, but it labels the number as an estimate and says how sure it is. |
| 0:20-0:27 | Tap "Worked from" on the notice. The sheet opens. Scroll slowly through the formula, the sets that fed it and the "Left out" lines. | Every number shows its working. | This is the thesis. A figure that could flatter you opens up to show the formula, the sets used and the sets it excluded, and why. |
| 0:27-0:30 | Close the sheet. Cut to the Progress tab, or to the end card. | Local-only. Nothing leaves your phone. | The log lives on the device. The end card can be the app name and nothing else. |

**The thesis moment** is 0:20-0:27: the record notice followed by Worked from. If the cut has to
be shortened, cut the keypad beat to a single "weight, Log set" and keep both of those. If it has
to be cut further, lose the Progress tab, not the sheet.

**Do not**: speed up the sheet so it cannot be read, add music that implies a feeling the app does
not claim, show a number from a fabricated history as if it were the lifter's training, or
describe the figures as "AI". The text in the sheet is the product; leave it on screen long
enough to be read once.

Check before publishing: every word visible in the clip matches the build that is on the store.

---

## 4. TestFlight

### What has to be true first (owner to confirm in App Store Connect)

- A build is uploaded and processed (`RELEASE-RUNBOOK.md` §8).
- External testing generally requires Apple's beta review of the build. Plan for it to add time;
  this kit does not know how long it takes now.
- A public TestFlight link or individual email invitations. A public link can be limited to a
  maximum number of testers; set a cap that matches the programme size below.
- In a TestFlight build, purchases run in Apple's test environment. Tell testers they are not
  charged for the Lifetime unlock; muscle history starts locked, so they can try the purchase flow
  (`RELEASE-RUNBOOK.md` §9). Confirm this on the build before sending the email.

### Invitation (email text)

Subject: `Hardset TestFlight: a week of logging, five questions at the end`

> Hi [name],
>
> You said [in the thread / in your reply] that [the specific thing they said, in their words].
> That's the problem I made Hardset for, so I'd like you to try it for a week and tell me where it
> falls short.
>
> Hardset is an iPhone lifting log. It keeps everything on your phone, says when a number is an
> estimate, and keeps history separate for each machine. It needs iOS 26.1 or later. It is free to
> log. The one purchase, which unlocks muscle history, is free in this test build.
>
> To install: [TestFlight link]. It takes about two minutes.
>
> What I'm asking: use it for your real training for seven days, logging the sessions you would
> have logged anyway. After a week I'll send five questions. They are short and mostly pick-one.
> They're about whether the app got in your way and whether its numbers held up, not whether you
> like it.
>
> Two things you should know. There is no account and no server, so the only copy of your history
> is on your phone. If you want to keep it, use Settings to export a JSON file. And there is no
> sync, so a second device starts empty.
>
> If something breaks or is wrong, email me at frankabisignano@gmail.com. Include what you
> tapped, what you expected and what you saw. I read everything and I will tell you if I can't
> fix it.
>
> Frankie Bisignano

Notes: send it only to people who have asked, replied to a post, or know you. Do not mass-mail.
Do not offer a reward for feedback; it distorts the answers and `docs/LAUNCH-PLAN.md` §4 already
rules out incentives for ratings.

### Five intake questions (send on day 7)

Each is answerable in a sentence or by picking an option, so the answers can be tallied across
testers. Keep the wording identical for everyone.

1. **Coverage.** In the last seven days you trained N times. How many of those sessions did you
   log in Hardset from the first set to the last? Reply with two numbers, "N" and "logged in
   Hardset." If any session was not fully logged, pick the main reason: forgot, too slow, app got
   in the way, other (name it).
2. **Speed.** Of the sets you logged, roughly how many were logged with the one-tap check and how
   many needed the keypad? Pick one: nearly all one tap / about half / mostly keypad / I never
   used the one-tap check. Then: did you ever give up on entering a figure or leave it unlogged
   because it took too long? Yes (how many times) or No.
3. **Trust.** Pick the first number in the app you checked against your own records or your own
   arithmetic. Say which screen it was on. Did it match? Pick one: matched / did not match
   (give both numbers) / I didn't check any. Did you open "Worked from" at least once? Yes or no.
4. **Machines.** Did you do any movement on more than one machine or at more than one gym this
   week? If yes, pick one: Hardset's split into separate histories matched how I think of it /
   it split what I would merge / it merged what I would split / I couldn't tell. If you answered
   "split" or "merged", name the movement and the two machines.
5. **Keeping it.** Pick one, then give one sentence of reason. (a) I would use this as my main log
   next month. (b) I would use it alongside something else. (c) I would not keep using it. If (a)
   or (b): would you pay $19.99 for muscle history, yes or no, and if no, what would change it?

Why these five: 1 and 2 measure whether it works as a log, with counts. 3 and 4 measure the two
claims the product makes (honest numbers, separate machines) against what the tester knows. 5 is
the only retention and price signal, and it is a choice, not a mood. Record answers in one table,
one row per tester, one column per question, so patterns are visible by the end of the first
cohort.

Do not ask "how do you like it", "would you recommend it" or for a star rating. Those answers are
not comparable and are easy to give politely.

---

## 5. First thirty days: channel plan

"Day 1" is the first day anything is public: the first TestFlight post, or the first App Store
listing day, whichever comes first. Efforts are the owner's hours for the whole thirty days, an
estimate, not a measurement.

Numeric targets below are **hypotheses chosen to be falsifiable, not forecasts**. They are set
low on purpose for a niche, free-to-log, zero-budget app from an unknown developer. If the first
cohort misses them, the response is to read the intake answers, not to post more. Measure source
with one App Store campaign link per channel (App Store Connect provides them; **owner to
confirm** the current parameter format) because the site has no analytics, by design, and must not
get any.

### Ranked by effort to return

| Rank | Channel | Artefact | Effort (hours) | "This worked" |
| --- | --- | --- | --- | --- |
| 1 | The site and the App Store listing | Already built: `site/`, gallery, metadata. Add the changelog page. | 0.5 beyond this PR | Not a channel to measure on its own. It is where every other channel lands, so check it loads and every claim matches the build. |
| 2 | Replies in existing threads where the problem is already being discussed | The three comment frameworks in `docs/LAUNCH-PLAN.md` §4, with disclosure | 1.5 a week, about 6 | At least 8 replies in 30 days that get an answer from another person, and at least 10 installs attributed to those campaign links. Zero removed by moderators. |
| 3 | Post 1 (evidence-based lifting thread) | The post above plus a Worked from capture | 3 including replies | At least 5 substantive replies, at least 2 of which name a specific thing the app gets wrong or should do differently, and at least 10 TestFlight installs or installs. |
| 4 | Post 3 (training-log forum or Discord) | The post above | 2 including replies | At least 3 replies from people who use a training log, and at least 5 installs. If a moderator declines the post, that is information; do not repost elsewhere to compensate. |
| 5 | The TestFlight programme itself | Invitation and five questions | 6 including reading answers | At least 15 testers install; at least 8 return all five answers; at least 4 answer (a) or (b) to question 5. It is also the main source of reviews that mean something: ask testers who chose (a) whether they would leave an honest review after launch, and accept a no. |
| 6 | Post 2 (general fitness self-promotion thread) | The post above | 2 including replies | At least 10 installs. This is the broadest audience and the one least likely to value the thesis, so it is placed after the others. |
| 7 | The 30-second demo clip | The script above, on the owner's own accounts and in the posts above | 5 to film and edit | At least 1 post where the clip is used gets more replies than the same post without. This is the one asset that should be filmed once and reused; do not film a second one before the first has been used. |
| 8 | A newsletter or podcast pitch | `docs/release/PRESS-ONE-PAGER.md` sent to 5 writers who have written about lifting apps or training science | 3 for five tailored emails | At least 1 reply of any kind. Expect none. Send one email per writer, tailored, never a list. |

### Not worth it in the first 30 days

- **Paid advertising, in any form.** The plan has no budget, there is no analytics on the site by
  design, and a niche app with a $19.99 optional unlock cannot be shown to pay for itself on this
  timescale. Not worth the money or the measurement burden.
- **Daily short-video posting.** It rewards volume and entertainment; the product's audience is a
  lifter who distrusts both. Several hours a week with no way to tell whether the people it
  reaches are the ones the app is for.
- **Product Hunt or a similar launch site.** The audience there is not people who log training,
  and a launch day spike of the wrong people is worse than none. This is a judgement, not a
  measurement.
- **Influencer sponsorship.** Expensive in hours, and a paid mention in a niche that prizes
  honesty needs a disclosure that undercuts the point. Gifting the app free is not a sponsorship
  but should be disclosed by them and not asked for.
- **Review swaps, incentivised reviews or asking friends for five stars.** Ruled out, and for a
  product that sells "does not lie to you" a single discovered act would cost more than every
  review it bought.
- **Cross-posting the same text to many subreddits.** Moderators and readers see it quickly, and
  the replies are the point, so one place done properly beats five done thinly.

### Weekly cadence (about 8 hours a week at most)

- Week 1: read the rules of each place; run the TestFlight invitation to people who already know
  you or have asked; do not post publicly until three testers have used it for three days and any
  breakage is fixed.
- Week 2: Post 1 and Post 3, on different days, replying within hours. Send the day-7 questions
  to week-1 testers.
- Week 3: tally the intake table. Change the app or the copy on what it says. Post 2 only if the
  tally is good enough that you would stand behind it.
- Week 4: the press pitch if a build is on the store, and one honest write-up of what the testers
  said, including what was wrong. That write-up, not a promotion, is the thing most likely to be
  shared in a community that values honesty.

### What would change the plan

- If fewer than 8 testers return answers, the problem is recruitment, not the app. Spend the next
  week on rank 2 and rank 3, not on new channels.
- If question 3 shows a mismatch (a number a tester checked did not match), stop posting and fix
  it before anything else. A wrong number found by a stranger is the one failure this product
  cannot afford.
- If question 1 shows people not logging fully, the problem is the logging path, not the
  positioning. Stop all promotion until it is understood.
