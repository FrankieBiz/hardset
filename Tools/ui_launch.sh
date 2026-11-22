# Launch helpers for the real-app step of .github/workflows/ios-ui.yml. Source this file; it only
# defines functions. Kept to bash 3.2 syntax because macOS runners may resolve `bash` to the system one.
#
# The failure these exist for. The simulator can refuse to launch the UI test runner while it is still
# installing or removing the runner bundle:
#
#   Simulator device failed to launch com.francisbisignano.hardset.uitests.xctrunner.
#   Application "...xctrunner" is installing or uninstalling, and cannot be launched. (Busy)
#
# Nothing is wrong with the app or the tests when that happens, and it has cost whole 60 to 90 minute
# runs on pull requests and on main. `xcodebuild test-without-building` installs the runner and
# launches it inside one process, so a script cannot wait between the two. What it can do is begin
# every invocation from a device that has stopped changing (ui_settle_simulator) and, when that exact
# denial comes back before any test ran, wait and run the same invocation again (ui_xcodebuild).
#
# What is never retried here: a run in which any test case started. A test that ran and failed an
# assertion, a crash, a compile error and a denial that lands mid-run all keep their one attempt, so a
# real failure cannot be turned into a pass by this file. The workflow passes no
# -retry-tests-on-failure either: it reran tests that had failed their assertions and let the job go
# green when the rerun passed, so a test gets one attempt and the only thing retried anywhere in the
# UI step is a refusal to launch the runner.
#
# Environment, all optional:
#   UI_SIM_UDID, UI_SIM_BUNDLES   device and the bundle identifiers whose install state is watched
#   UI_LAUNCH_ATTEMPTS            attempts per invocation, default 3
#   UI_LAUNCH_BACKOFF             seconds before the second attempt, doubled before the third; default 20
#   UI_SETTLE_TIMEOUT, UI_SETTLE_POLL, UI_SETTLE_STABLE
#                                 seconds to wait at most (90), seconds between looks (3), and how many
#                                 identical looks in a row count as settled (2)

# A launch denied by the simulator. The second form is the same refusal as FrontBoard words it.
UI_LAUNCH_DENIED_PATTERN='installing or uninstalling, and cannot be launched|denied by service delegate \(SBMainWorkspace\).*Busy'
# The first line xcodebuild prints for any test case, in both the old and the new output formats.
UI_TEST_STARTED_PATTERN='Test [Cc]ase .* started'
# What the job log shows while xcodebuild runs; the whole output goes to the log file regardless. The
# denial is included so a reader sees the message itself, not only that a retry happened, and so is
# the EXECUTE form of the verdict, which test-without-building prints and the old filter hid.
UI_LOG_FILTER='error:|Test [Cc]ase|TEST (EXECUTE )?(SUCCEEDED|FAILED)|Executed|failed to launch|installing or uninstalling'

# ui_launch_denied ATTEMPT_LOG: success only when the attempt was refused at launch and nothing ran.
ui_launch_denied() {
  grep -Eq "$UI_LAUNCH_DENIED_PATTERN" "$1" || return 1
  grep -Eq "$UI_TEST_STARTED_PATTERN" "$1" && return 1
  grep -Eq 'TEST (EXECUTE )?SUCCEEDED' "$1" && return 1
  return 0
}

# ui_simulator_probe UDID BUNDLE_ID...: sets UI_SIM_STATE (compared between looks) and UI_SIM_SUMMARY
# (printed). It does not use a subshell, so both variables reach the caller.
ui_simulator_probe() {
  local udid=$1 id path listing line
  shift
  UI_SIM_STATE=not-booted
  UI_SIM_SUMMARY=""
  listing=$(xcrun simctl list devices 2>/dev/null || true)
  line=$(printf '%s\n' "$listing" | grep -F "$udid" || true)
  case "$line" in
    *"(Booted)"*) UI_SIM_STATE=booted ;;
  esac
  for id in "$@"; do
    if path=$(xcrun simctl get_app_container "$udid" "$id" app 2>/dev/null) && [ -n "$path" ]; then
      UI_SIM_STATE="$UI_SIM_STATE $path"
      UI_SIM_SUMMARY="$UI_SIM_SUMMARY $id=installed"
    else
      UI_SIM_STATE="$UI_SIM_STATE -"
      UI_SIM_SUMMARY="$UI_SIM_SUMMARY $id=absent"
    fi
  done
}

# ui_settle_simulator: wait until the device is booted and the install state of the watched bundles has
# stopped changing. The simulator offers no query for "is installing", so settled is the closest thing
# the host can observe: booted, and each bundle's container path (new on every install) unchanged and
# its presence unchanged across several looks. A bundle that is absent and stays absent is settled too,
# because xcodebuild may or may not leave the runner installed between invocations. This narrows the
# window; it cannot close it, which is why ui_xcodebuild also retries. Bounded: after the timeout it
# says so and carries on, and the launch gets its own attempts.
ui_settle_simulator() {
  local udid=${UI_SIM_UDID:-}
  [ -n "$udid" ] || return 0
  local timeout=${UI_SETTLE_TIMEOUT:-90} poll=${UI_SETTLE_POLL:-3} needed=${UI_SETTLE_STABLE:-2}
  local step=$poll waited=0 stable=0 previous=""
  [ "$step" -ge 1 ] || step=1
  while :; do
    # shellcheck disable=SC2086 # bundle identifiers hold no whitespace
    ui_simulator_probe "$udid" ${UI_SIM_BUNDLES:-}
    if [ "$UI_SIM_STATE" = "$previous" ] && [ "${UI_SIM_STATE#booted}" != "$UI_SIM_STATE" ]; then
      stable=$((stable + 1))
    else
      stable=0
    fi
    previous=$UI_SIM_STATE
    if [ "$stable" -ge "$needed" ]; then
      echo "Simulator settled after ${waited}s:${UI_SIM_SUMMARY:- booted}"
      return 0
    fi
    if [ "$waited" -ge "$timeout" ]; then
      echo "Simulator did not settle within ${timeout}s (${UI_SIM_STATE%% *}${UI_SIM_SUMMARY}); launching anyway"
      return 0
    fi
    sleep "$step"
    waited=$((waited + step))
  done
}

# ui_xcodebuild LABEL LOG XCODEBUILD_ARGS...: run xcodebuild once the simulator has settled, appending
# everything it prints to LOG and showing the filtered lines in the job log. If it is refused at launch
# before any test ran (ui_launch_denied), print one line naming LABEL and the attempt, wait, and run it
# again, up to UI_LAUNCH_ATTEMPTS in all. Returns the exit status of the last xcodebuild, so a launch
# that is denied every time still fails with xcodebuild's own message in LOG and in the job log.
ui_xcodebuild() {
  local label=$1 log=$2
  shift 2
  local max=${UI_LAUNCH_ATTEMPTS:-3} backoff=${UI_LAUNCH_BACKOFF:-20}
  local attempt=1 rc=0 offset delay line errexit=0 bundle="" prev="" arg attempt_log
  # xcodebuild refuses to write a result bundle over an existing one, so a retry has to move the
  # denied attempt's aside first; find the path the caller asked for.
  for arg in "$@"; do
    if [ "$prev" = "-resultBundlePath" ]; then bundle=$arg; fi
    prev=$arg
  done
  case $- in *e*) errexit=1 ;; esac
  attempt_log=$(mktemp "${TMPDIR:-/tmp}/ui_launch.XXXXXX")
  : > "$log"
  ui_settle_simulator
  while :; do
    offset=$(($(wc -c < "$log")))
    # The pipeline's own status is not wanted, only xcodebuild's, so errexit is off around it.
    set +e
    xcodebuild "$@" 2>&1 | tee -a "$log" | grep -E "$UI_LOG_FILTER"
    rc=${PIPESTATUS[0]}
    if [ "$errexit" = 1 ]; then set -e; fi
    tail -c "+$((offset + 1))" "$log" > "$attempt_log"
    if [ "$rc" -eq 0 ] || ! ui_launch_denied "$attempt_log"; then
      break
    fi
    if [ "$attempt" -ge "$max" ]; then
      line="::error title=Simulator launch denied (Busy)::${label}: launch still denied on attempt ${attempt} of ${max}, giving up"
      printf '%s\n' "$line" | tee -a "$log"
      break
    fi
    delay=$((backoff * (1 << (attempt - 1))))
    line="::warning title=Simulator launch denied (Busy)::${label}: launch denied on attempt ${attempt} of ${max}, launching again in ${delay}s"
    printf '%s\n' "$line" | tee -a "$log"
    sleep "$delay"
    if [ -n "$bundle" ] && [ -e "$bundle" ]; then
      mv "$bundle" "${bundle%.xcresult}.attempt${attempt}.xcresult"
    fi
    ui_settle_simulator
    attempt=$((attempt + 1))
  done
  rm -f "$attempt_log"
  return "$rc"
}
