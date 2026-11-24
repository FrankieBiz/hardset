# Known issues

Findings that are open. They are written down here with their evidence instead of being hidden by a
test that was loosened or a report that was dismissed. When one is fixed, remove its entry in the
same change.

## 1. The scrolled Volume audit reports about fourteen contrast failures that the render does not show

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
