# Known issues

Findings that are open. They are written down here with their evidence instead of being hidden by a
test that was loosened or a report that was dismissed. When one is fixed, remove its entry in the
same change.

## 1. The staged phone is reachable by assistive technology at every tour step

**Where.** The first-launch tour (`TourStage`) stages two real `HardsetRootView`s in a scaled
phone (`ScaledPhoneFrame`). Only step two, the staged set's check, asks the lifter to touch it. At
every other step the phone is meant to be a picture: inert to touch and hidden from VoiceOver.

**What is wrong.** Inert to touch holds. Hidden from VoiceOver does not. XCUITest lists the staged
roots' two tab bars (UIKit-hosted, from each root's `TabView`) and the staged start screen's
"Start workout" button at all eight inert tour steps. What XCUITest lists is what an assistive
technology is offered, so a VoiceOver user can swipe into a preview and meet controls that do
nothing. How VoiceOver actually reads the tour has not been confirmed.

**Evidence.** CI run 44755327282 on `1acb3b7`, with `ScaledPhoneFrame` as it is on main:
`testOnboardingJourneyDark` recorded 32 failures, 16 of each of two assertions (tab bar count
`2`, not `0`; "Start workout" exists), which is eight tour steps over two attempts. The reverse-order
pass failed the same way. The control recorded in the same journey read `2` tab bars at the
interactive step as well, so the marking changes nothing the tree lists.

**Tried, and why each failed.**

1. `accessibilityHidden(true)` on the frame. It does not reach the UIKit-hosted tab content
   (`docs/superpowers/plans/2026-11-16-frontend-rebuild-phase-4-onboarding.md`, R66).
2. A hosting controller per staged root. Reverted: it rendered the roots in the wrong appearance,
   and XCUITest still listed the content.
3. The frame made one accessibility leaf (`accessibilityElement(children: .ignore)`) and then hidden,
   as a value rather than a branch so the frame kept its identity. Commit `45afb77`, reverted in
   `fb3caf7` after CI run 44738794794: the same two tab bars and the same button were still listed,
   and the interactive control read the same, so it changed nothing the tree exposes.

**How the test records it.** `assertStagedPhoneIsHidden` in `HardsetUITests/AppScreensUITests.swift`
keeps both assertions and wraps each in a strict `XCTExpectFailure`. The journey passes while the
defect stands, and fails with "failure expected but none occurred" on the day it is fixed, so the
expectation is removed deliberately. The assertions are not weakened.

**Open question.** Which layer owns the fix. The candidates are the frame (the SwiftUI layer that has
now failed twice), the staged roots' `TabView` (the UIKit tab bar controller is the thing still
listed), a UIKit-level hide of that controller's view, or a change to what the tour stages. None of
these has been tried or ruled out beyond the three attempts above.

**Needs a device.** VoiceOver on the tour, at each step, on hardware.

## 2. The scrolled Volume audit reports about fourteen contrast failures that the render does not show

**Where.** `testWorkoutJourneyDark`, the audit named "volume with a workout, scrolled": Volume with
a finished workout, after `swipeUp()` has brought the muscle rows into view.

**What is open.** The audit reports fourteen "Contrast failed" lines on text that the render shows as
plain chalk on canvas or steel: the "Where the work went" heading and its description, two of the
`Moderate confidence` badges, "Nothing logged for" and its description, the two counts, and five
muscle chips (Side delts, Rear delts, Lats, Upper back, Traps). The palette gate (`make check`,
`Tools/check_contrast.py`, 184 pairs) holds every text role to 7:1 on those surfaces. The two
cannot both be right, and no explanation has been found. This is recorded as unexplained, not
dismissed as a false positive.

**Evidence.** CI run 44755327282: `accessibility-audit-workout.txt`, and
`18b-volume-with-workout-scrolled.png`, in which the same text reads clearly. The audit of the same
screen before scrolling flags five chips and one description too, but there the pinned "Deep muscle
map" button and the tab bar cover them (`18-volume-with-workout.png` shows the "Nothing logged for"
heading cut by the button), which is the same occlusion that explained the picker's contrast
reports under the keyboard. That explanation does not apply to the scrolled audit.

**Not tried.** A hypothesis, not tested: the audit sampled while the list was still settling after
the swipe. A longer settle before the audit, or auditing the same position twice, would test it. No
change was made to the screen or to the palette, because nothing was found to fix.

**Needs a device.** A glare and contrast check of the Volume screen on hardware is owed.
