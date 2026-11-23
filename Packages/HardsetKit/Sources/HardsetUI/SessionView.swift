import HardsetCore
import SwiftUI

/// The live workout screen.
///
/// Deliberately knows nothing about storage. It takes the exercise states, reports taps, and
/// renders whatever error the caller hands it — so `HardsetUI` keeps depending on `HardsetCore`
/// alone, and this screen compiles and previews on the host without a database, a CloudKit
/// container or a simulator.
///
/// The app target owns the wiring: it holds the `SessionCoordinator`, passes
/// `$coordinator.exercises` in, and forwards `onLogSet` to `coordinator.logSet`, which is the
/// only thing allowed to mark a row logged.
///
/// This screen hosts the session's only keypad. One presenter means a tap on another row's field
/// moves the open keypad there instead of highlighting a second row while digits keep going into
/// the first, and every other sheet or dialog is opened only after the keypad has gone, so none is
/// queued behind it and popped up later.
public struct SessionView: View {
  @Binding private var exercises: [ExerciseLogState]
  private let unit: WeightUnit
  private let title: String?
  private let gymName: String?
  private let startedAt: Date?
  private let lastLoggedAt: Date?
  private let isStale: Bool
  private let restState: RestTimerState
  private let restMetadata: RestMetadata?
  private let errorMessage: String?
  private let errorEvent: Int
  private let restEndsSilently: Bool
  private let records: [PersonalRecord]
  private let recordsExerciseName: String?
  private let lastRest: [UUID: Duration]
  private let restExerciseID: UUID?
  private let onChooseNextRest: ((UUID, Duration) -> Void)?
  private let onLogSet: (UUID, SetSlot) -> Void
  private let onStartRest: ((UUID, Duration) -> Void)?
  private let onAdjustRest: (Duration) -> Void
  private let onPauseResumeRest: () -> Void
  private let onSkipRest: () -> Void
  private let onAddExercise: (() -> Void)?
  private let onSelectMachine: ((UUID) -> Void)?
  private let onShowHistory: ((UUID) -> Void)?
  private let onShowSettings: (() -> Void)?
  private let onChangeGym: (() -> Void)?
  private let onUndoSet: ((UUID, SetSlot) -> Bool)?
  private let onCorrectSet: ((UUID, SetSlot, SetEntryDraft) -> Bool)?
  private let onRemoveSet: ((UUID, SetSlot) -> Void)?
  private let onRemoveExercise: ((UUID) -> Void)?
  private let onMoveExercise: ((UUID, Int) -> Void)?
  private let onDismissError: (() -> Void)?
  private let onDismissRecords: (() -> Void)?
  private let onExplainRecords: (() -> Void)?
  private let recordsWorkingError: String?
  private let showsCorrectionHint: Bool
  private let onCorrectionHintShown: (() -> Void)?
  private let onDismissCorrectionHint: (() -> Void)?
  private let onFinish: () -> Void
  private let onFinishAt: ((Date) -> Void)?
  private let onDiscard: (() -> Void)?

  /// Finishing closes the session for good, so it takes a second, deliberate tap. The first tap
  /// only asks; a lifter brushing the button with a chalky thumb loses nothing.
  @State private var isConfirmingFinish = false
  /// Set by a request to finish, and consumed once the expanded confirmation has been laid out,
  /// so it is scrolled into view with its real height rather than the collapsed one.
  @State private var revealsFinish = false
  @State private var isConfirmingDiscard = false
  @State private var removal: RemovalRequest?
  /// "Continue workout" on the stale notice: the lifter has read it and kept the workout open.
  @State private var isStaleAcknowledged = false

  /// The field the keypad is on. `nil` closes it.
  @State private var keypad: KeypadTarget?
  /// The last target, kept so the keypad still names its set while it slides away.
  @State private var shownKeypad: KeypadTarget?
  /// What is being typed, in the display unit. Written back to the targeted draft on every key.
  @State private var keypadBuffer = NumericEntryBuffer()
  /// The keypad's measured height, so the sheet is exactly as tall as its keys. Seeded with a
  /// close estimate so the first presentation does not visibly resize.
  @State private var padHeight: CGFloat = 500
  /// The bottom inset the screen already has from the tab bar, measured, so the room reserved for
  /// the keypad is only what the keypad covers beyond it.
  @State private var outerBottomInset: CGFloat = 0
  /// Run once the keypad has finished dismissing: another sheet or a dialog, which would otherwise
  /// be refused or queued while the keypad is still presented.
  @State private var afterKeypadCloses: (() -> Void)?
  @State private var scrollRequest: ScrollRequest?
  /// Counts taps on the rest controls, so each is felt. Kept here rather than in the rest bar,
  /// which leaves the hierarchy the moment a −15 or Skip ends the rest.
  @State private var restControlTaps = 0
  /// The finish question takes VoiceOver focus when it opens, so it is read rather than skipped.
  @AccessibilityFocusState private var isFinishQuestionFocused: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  /// Where the reach check measures, and its one request: show the pad. Absent in the daily app.
  @Environment(\.reachTargets) private var reachTargets

  /// - Parameter title: Draws a screen header when present. The live session passes "Workout";
  ///   previews and embedded uses can leave it out.
  /// - Parameter gymName: The gym the workout is at. `nil` says no gym is recorded. With no machine
  ///   picker to offer and a way to set the gym (`onChangeGym`), each card's machine chip stays,
  ///   says no machine is recorded and that a gym comes first, and leads to choosing one.
  /// - Parameter startedAt: When the workout began, shown in the header, with the day when it was
  ///   not today: a workout reopened from days ago says so.
  /// - Parameter lastLoggedAt: When the newest logged set was completed; the honest end of a
  ///   workout that was left open.
  /// - Parameter isStale: The workout has been open longer than any real session. The caller
  ///   decides by its rule; this view states the fact and offers the choices.
  /// - Parameter errorEvent: Changes on every failed command, including a retry that fails with
  ///   the same message. The message alone cannot signal that: a retry clears it and sets the same
  ///   words in one update, so the error haptic and announcement stayed silent the second time.
  /// - Parameter restEndsSilently: No system alarm will mark the end of a rest, so the screen
  ///   does: a haptic and an announcement when the deadline, not the lifter, ends it.
  /// - Parameter records: Records from the set just logged, named after `recordsExerciseName`.
  /// - Parameter onExplainRecords: Opens the working behind the records on the notice: what each beat,
  ///   by how much, the formula behind an estimate and every set left out. With it the notice draws
  ///   a "Worked from" control; without it, as in the tour's staged phone, it draws none.
  /// - Parameter recordsWorkingError: Says why the working could not be opened, under that control.
  /// - Parameter lastRest: The rest the lifter last chose per movement, keyed by exercise-state id.
  /// - Parameter restExerciseID: The exercise-state id the running rest follows, so the rest bar can
  ///   offer the length of that movement's next rest.
  /// - Parameter onChooseNextRest: Offers the next rest's length on the rest bar and is called with
  ///   the movement and the length the lifter picks.
  /// - Parameter onShowSettings: Puts a settings button in the header.
  /// - Parameter onChangeGym: Makes the header's gym a chip that sets or changes it.
  /// - Parameter onUndoSet: Returns a logged set to unlogged. `true` when it was undone.
  /// - Parameter onCorrectSet: Writes a corrected weight and reps to a saved set, and is `true` when
  ///   it was saved. With it, a saved figure opens the keypad, and what is typed is written when the
  ///   keypad leaves that figure; without it saved figures are plain text.
  /// - Parameter showsCorrectionHint: Offers the one-time line saying a saved weight can be tapped to
  ///   correct it. Drawn only once a set is saved, only where `onCorrectSet` can write a correction,
  ///   and never over the keypad, an error or a new record; the host decides whether it is still
  ///   owed. See `onCorrectionHintShown`.
  /// - Parameter onCorrectionHintShown: Called each time the hint is drawn, so the host can note it
  ///   as seen. The host should keep `showsCorrectionHint` true for the rest of this screen's life,
  ///   so the line does not vanish the moment it is noted.
  /// - Parameter onDismissCorrectionHint: Called when the lifter dismisses the hint, and when they
  ///   open a saved figure to correct it, which is the thing the hint was about.
  /// - Parameter onFinishAt: Finishes at a given instant; offered with the last set's time when
  ///   the workout is stale.
  /// - Parameter onDiscard: Deletes the workout. Always behind a confirmation.
  public init(
    exercises: Binding<[ExerciseLogState]>,
    unit: WeightUnit,
    title: String? = nil,
    gymName: String? = nil,
    startedAt: Date? = nil,
    lastLoggedAt: Date? = nil,
    isStale: Bool = false,
    restState: RestTimerState = .idle,
    restMetadata: RestMetadata? = nil,
    errorMessage: String? = nil,
    errorEvent: Int = 0,
    restEndsSilently: Bool = false,
    records: [PersonalRecord] = [],
    recordsExerciseName: String? = nil,
    lastRest: [UUID: Duration] = [:],
    restExerciseID: UUID? = nil,
    onChooseNextRest: ((UUID, Duration) -> Void)? = nil,
    onLogSet: @escaping (UUID, SetSlot) -> Void,
    onStartRest: ((UUID, Duration) -> Void)? = nil,
    onAdjustRest: @escaping (Duration) -> Void = { _ in },
    onPauseResumeRest: @escaping () -> Void = {},
    onSkipRest: @escaping () -> Void = {},
    onAddExercise: (() -> Void)? = nil,
    onSelectMachine: ((UUID) -> Void)? = nil,
    onShowHistory: ((UUID) -> Void)? = nil,
    onShowSettings: (() -> Void)? = nil,
    onChangeGym: (() -> Void)? = nil,
    onUndoSet: ((UUID, SetSlot) -> Bool)? = nil,
    onCorrectSet: ((UUID, SetSlot, SetEntryDraft) -> Bool)? = nil,
    onRemoveSet: ((UUID, SetSlot) -> Void)? = nil,
    onRemoveExercise: ((UUID) -> Void)? = nil,
    onMoveExercise: ((UUID, Int) -> Void)? = nil,
    onDismissError: (() -> Void)? = nil,
    onDismissRecords: (() -> Void)? = nil,
    onExplainRecords: (() -> Void)? = nil,
    recordsWorkingError: String? = nil,
    showsCorrectionHint: Bool = false,
    onCorrectionHintShown: (() -> Void)? = nil,
    onDismissCorrectionHint: (() -> Void)? = nil,
    onFinish: @escaping () -> Void = {},
    onFinishAt: ((Date) -> Void)? = nil,
    onDiscard: (() -> Void)? = nil
  ) {
    self._exercises = exercises
    self.unit = unit
    self.title = title
    self.gymName = gymName
    self.startedAt = startedAt
    self.lastLoggedAt = lastLoggedAt
    self.isStale = isStale
    self.restState = restState
    self.restMetadata = restMetadata
    self.errorMessage = errorMessage
    self.errorEvent = errorEvent
    self.restEndsSilently = restEndsSilently
    self.records = records
    self.recordsExerciseName = recordsExerciseName
    self.lastRest = lastRest
    self.restExerciseID = restExerciseID
    self.onChooseNextRest = onChooseNextRest
    self.onLogSet = onLogSet
    self.onStartRest = onStartRest
    self.onAdjustRest = onAdjustRest
    self.onPauseResumeRest = onPauseResumeRest
    self.onSkipRest = onSkipRest
    self.onAddExercise = onAddExercise
    self.onSelectMachine = onSelectMachine
    self.onShowHistory = onShowHistory
    self.onShowSettings = onShowSettings
    self.onChangeGym = onChangeGym
    self.onUndoSet = onUndoSet
    self.onCorrectSet = onCorrectSet
    self.onRemoveSet = onRemoveSet
    self.onRemoveExercise = onRemoveExercise
    self.onMoveExercise = onMoveExercise
    self.onDismissError = onDismissError
    self.onDismissRecords = onDismissRecords
    self.onExplainRecords = onExplainRecords
    self.recordsWorkingError = recordsWorkingError
    self.showsCorrectionHint = showsCorrectionHint
    self.onCorrectionHintShown = onCorrectionHintShown
    self.onDismissCorrectionHint = onDismissCorrectionHint
    self.onFinish = onFinish
    self.onFinishAt = onFinishAt
    self.onDiscard = onDiscard
  }

  public var body: some View {
    sessionFeedback(
      sessionKeypadObservers(
        sessionDialogs(
          sessionScroll,
          isConfirmingRemoval: isConfirmingRemoval,
          removal: removal,
          onRemoveExercise: onRemoveExercise,
          isConfirmingDiscard: $isConfirmingDiscard,
          discardMessage: discardMessage,
          onDiscard: onDiscard
        )
        .keypadSheetPresentation(
          isPresented: isKeypadPresented, onDismiss: keypadDidDismiss,
          inlineHeight: reachTargets == nil ? nil : padHeight
        ) {
          keypadSheet
        }
      )
    )
  }

  // MARK: - Body in pieces
  //
  // The body is four expressions, not one. Held in one, the rows, both confirmation dialogs and ten
  // observer modifiers overflowed the result builder's inference budget, and the compiler gave up
  // naming a leaf with exactly one overload — `Text(String)` in the removal dialog. The boundaries
  // below are the ones the screen already had; splitting there costs nothing at runtime and gives
  // the type checker four small problems instead of one large one. Behaviour is unchanged.

  /// The rows: no container around a movement, so the page margin is the only inset and movements
  /// are separated by space. Each owns the space above it, so the gap is one rule in one place.
  private var movementRows: some View {
    LazyVStack(alignment: .leading, spacing: 0) {
      if let title {
        header(title: title)
          .padding(.bottom, Tokens.Spacing.snug)
      }

      // Above the movements on purpose, unlike every other message: it is there when the
      // screen opens, so it moves nothing under a thumb, and it is the first thing to read.
      if showsStaleNotice {
        staleNotice
          .padding(.horizontal, Tokens.Spacing.loose)
          .padding(.top, Tokens.Spacing.regular)
          .hardsetArrival()
      }

      ForEach($exercises) { $exercise in
        card(for: $exercise)
          .padding(.horizontal, Tokens.Spacing.loose)
          .padding(.top, Tokens.Spacing.block)
      }

      // An empty workout says so, and says what to do about it, rather than rendering a bare
      // "Finish" button under nothing. When it is empty, the empty state carries the add
      // action, so the add row below is not drawn twice.
      if exercises.isEmpty {
        HardsetEmptyState(
          title: "Nothing added yet",
          detail: "Add a movement to start logging sets.",
          systemImage: "dumbbell",
          actionTitle: onAddExercise == nil ? nil : "Add movement",
          action: onAddExercise.map { add in { closeKeypad(then: add) } }
        )
        .padding(.top, Tokens.Spacing.block)
      } else if let onAddExercise {
        addMovementSlot { closeKeypad(then: onAddExercise) }
          .padding(.horizontal, Tokens.Spacing.loose)
          .padding(.top, Tokens.Spacing.section)
      }

      summary
        .padding(.horizontal, Tokens.Spacing.loose)
        .padding(.top, Tokens.Spacing.block)
        .id(Self.finishAnchor)
    }
  }

  /// The scroll, the background, the inset that measures the bar, and the proxy's one job.
  private var sessionScroll: some View {
    ScrollViewReader { proxy in
      ScrollView {
        movementRows
          .padding(.bottom, Tokens.Spacing.section)
      }
      .background(Tokens.Color.canvas)
      // The inset measures what it holds and reserves exactly its height, so the last row is never
      // trapped underneath it. A guessed 72 pt allowance used to sit on top of this and was wrong as
      // soon as the bar wrapped onto two lines.
      .safeAreaInset(edge: .bottom, spacing: 0) {
        bottomInset
      }
      .onGeometryChange(for: CGFloat.self) { geometry in
        geometry.safeAreaInsets.bottom
      } action: { inset in
        outerBottomInset = inset
      }
      .onChange(of: scrollRequest) { _, request in
        guard let request else { return }
        withAnimation(Tokens.Motion.adaptive(Tokens.Motion.state, reduceMotion: reduceMotion)) {
          switch request.target {
          case .view(let id): proxy.scrollTo(id, anchor: request.anchor)
          case .finish: proxy.scrollTo(Self.finishAnchor, anchor: .bottom)
          }
        }
      }
    }
  }

  /// The two dialogs this screen can raise. They are presentation modifiers, so they sit outside the
  /// scroll instead of inside the builder that draws its rows.
  private func sessionDialogs<Content: View>(
    _ content: Content,
    isConfirmingRemoval: Binding<Bool>,
    removal: RemovalRequest?,
    onRemoveExercise: ((UUID) -> Void)?,
    isConfirmingDiscard: Binding<Bool>,
    discardMessage: String,
    onDiscard: (() -> Void)?
  ) -> some View {
    content
      .confirmationDialog(
        "Remove this movement?",
        isPresented: isConfirmingRemoval,
        titleVisibility: .visible,
        presenting: removal
      ) { request in
        Button("Remove \(request.name)", role: .destructive) {
          onRemoveExercise?(request.exerciseID)
        }
        Button("Keep it", role: .cancel) {}
      } message: { request in
        Text(Self.removalMessage(for: request))
      }
      .confirmationDialog(
        "Discard this workout?",
        isPresented: isConfirmingDiscard,
        titleVisibility: .visible
      ) {
        Button("Discard workout", role: .destructive) { onDiscard?() }
        Button("Keep workout", role: .cancel) {}
      } message: {
        Text(discardMessage)
      }
  }

  /// The row a keypad is on can change underneath it, so these three observers end or reseed it.
  private func sessionKeypadObservers<Content: View>(_ content: Content) -> some View {
    content
      // The reach check opens the keypad on the first set still to log so it can measure the pad.
      .onChange(of: reachTargets?.opensKeypad, initial: true) { _, opens in
        // `opensKeypad` is optional because the environment value is: no reach targets at all and
        // no reach check is asking for the pad.
        if opens == true {
          guard keypad == nil, let next = firstUnloggedSlot else { return }
          beginEditing(exerciseID: next.exerciseID, slotID: next.slotID, field: .weight)
        } else if keypad != nil {
          keypad = nil
        }
      }
      // A row the keypad is on can change underneath it: logged from its own check, removed, moved
      // to another machine, or stepped with the −/+ buttons. Logged or gone closes the keypad; a
      // new value reseeds it, so the keypad never shows a number the row does not hold.
      .onChange(of: targetedSlot) { _, slot in
        guard let target = keypad else { return }
        // A saved figure's keystrokes live in the keypad's buffer until they are written, so the
        // row is not reseeded from under them. Only the row going away, or being undone, ends it.
        if target.isCorrection {
          if slot?.isLogged != true { keypad = nil }
          return
        }
        guard let slot, !slot.isLogged else {
          keypad = nil
          return
        }
        if !Self.buffer(keypadBuffer, agreesWith: slot.draft, field: target.field, unit: unit) {
          keypadBuffer = Self.buffer(for: slot.draft, field: target.field, unit: unit)
        }
      }
      // The buffer is in the display unit; a unit change mid-entry would write pounds as kilograms.
      .onChange(of: unit) { keypad = nil }
  }

  /// What the phone says and feels: the clank engine, and every announcement a lifter cannot see.
  private func sessionFeedback<Content: View>(_ content: Content) -> some View {
    content
      // The clank is the anchor of the log moment, so its engine is running before the first set is
      // logged and the first one is not the one that pays for starting it.
      .onAppear { ClankPlayer.shared.prepare() }
      // A failed save is felt as well as read: the check simply not stamping was easy to miss.
      // Keyed on the failure as an event, so a retry that fails the same way is felt again.
      .sensoryFeedback(Tokens.Haptic.error, trigger: errorSignal) { _, new in new.message != nil }
      .onChange(of: errorSignal) { _, signal in
        if let message = signal.message {
          AccessibilityNotification.Announcement(message).post()
        }
      }
      // Each rest control is felt, because the lifter pressing −15 or Skip is looking at the bar,
      // not the phone, between sets. A selection tick, light like the row's machine step.
      .sensoryFeedback(Tokens.Haptic.selection, trigger: restControlTaps)
      // A rest ended by its deadline, with no alarm to say so, is felt and announced. Skip, −15 to
      // zero and a dismissed alarm end it too, but the lifter did those and needs no telling.
      .sensoryFeedback(trigger: restState) { [restEndsSilently] old, new in
        Self.restEndedByDeadline(from: old, to: new, alarmless: restEndsSilently) ? Tokens.Haptic.warning : nil
      }
      .onChange(of: restState) { old, new in
        if let announcement = Self.restAnnouncement(from: old, to: new, alarmless: restEndsSilently) {
          AccessibilityNotification.Announcement(announcement).post()
        }
      }
      .onChange(of: records) { _, records in
        guard !records.isEmpty else { return }
        let spoken = records.map { "\($0.kind.label), \(Self.describe($0, unit: unit))" }
        let announcement: String = "New record. " + spoken.joined(separator: ". ")
        AccessibilityNotification.Announcement(announcement).post()
      }
  }

  /// The removal dialog's message, built outside the `ViewBuilder` so the message closure stays a
  /// single non-generic call.
  private static func removalMessage(for request: RemovalRequest) -> String {
    "The \(Self.setCount(request.loggedSets)) logged for \(request.name) in this workout "
      + "will be deleted. This cannot be undone."
  }

  // MARK: - Header

  private func header(title: String) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      ScreenHeader(title, subtitle: headerSubtitle) {
        HStack(spacing: Tokens.Spacing.snug) {
          if onDiscard != nil || onChangeGym != nil {
            workoutMenu
          }
          if let onShowSettings {
            HeaderIconButton(systemImage: "gearshape", accessibilityLabel: "Settings", style: .bare) {
              closeKeypad(then: onShowSettings)
            }
          }
        }
      }
      if let onChangeGym {
        gymChip { closeKeypad(then: onChangeGym) }
          .padding(.horizontal, Tokens.Spacing.loose)
      }
    }
  }

  /// When the workout began, and where when the gym is not shown as its own chip.
  private var headerSubtitle: String {
    var parts: [String] = []
    if onChangeGym == nil {
      parts.append(gymName ?? "No gym recorded")
    }
    if let startedAt {
      parts.append(
        Calendar.current.isDateInToday(startedAt)
          ? "Started \(startedAt.formatted(date: .omitted, time: .shortened))"
          : "Started \(Self.moment(startedAt))"
      )
    }
    return parts.joined(separator: " · ")
  }

  /// The things done to the workout as a whole. Finish is here as well as at the end of the list,
  /// so a long workout can be ended without scrolling past every card.
  private var workoutMenu: some View {
    HeaderIconMenu(accessibilityLabel: "Workout options", style: .bare) {
      if let onChangeGym {
        Button {
          closeKeypad(then: onChangeGym)
        } label: {
          Label(gymName == nil ? "Set gym" : "Change gym", systemImage: "mappin.and.ellipse")
        }
      }
      Button {
        requestFinish()
      } label: {
        Label("Finish workout", systemImage: "flag.checkered")
      }
      if onDiscard != nil {
        Divider()
        Button(role: .destructive) {
          requestDiscard()
        } label: {
          Label("Discard workout", systemImage: "trash")
        }
      }
    }
  }

  /// The workout's gym, as the machine line on each card shows its machine: a line of type with a
  /// chevron, and no capsule. Unset it reads "Set gym" in full chalk, an invitation to say where
  /// the lifter is; set, it reads the name in `chalkDim` with the pin that says what the name is.
  /// Setting it is what makes the machine lines appear.
  private func gymChip(action: @escaping () -> Void) -> some View {
    let isSet = gymName != nil
    return Button(action: action) {
      HStack(spacing: Tokens.Spacing.snug) {
        Image(systemName: isSet ? "mappin.and.ellipse" : "plus")
          .font(Tokens.Text.provenance.weight(.medium))
          .accessibilityHidden(true)
        Text(gymName ?? "Set gym")
          .font(Tokens.Text.provenance.weight(.medium))
          .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
          .multilineTextAlignment(.leading)
        if isSet {
          Image(systemName: "chevron.down")
            .font(Tokens.Text.caption.weight(.semibold))
            .accessibilityHidden(true)
        }
      }
      .foregroundStyle(isSet ? Tokens.Color.chalkDim : Tokens.Color.chalk)
    }
    .buttonStyle(InlineControlStyle(minHeight: Tokens.minimumTapTarget, alignment: .leading))
    // Begins with the words on the chip, so a Voice Control user can say what they see.
    .accessibilityLabel(
      gymName.map { "\($0). Change gym." }
        ?? "Set gym. No gym recorded; machines are tracked per gym."
    )
    .accessibilityInputLabels(gymName.map { [$0, "Change gym", "Gym"] } ?? ["Set gym", "Gym"])
  }

  // MARK: - Stale workout

  private var showsStaleNotice: Bool {
    isStale && !isStaleAcknowledged && startedAt != nil
  }

  /// A workout left open from another day, stated plainly with the three honest ways forward:
  /// end it when its last set ended, throw it away, or carry on with it. Nothing is chosen for the
  /// lifter, and the app never closes a workout by itself.
  private var staleNotice: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
      HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.regular) {
        // The one mark of the caveat: a small `warning` glyph. The headline is chalk and the card
        // is neutral, so nothing but the glyph is coloured.
        Image(systemName: "clock.badge.exclamationmark")
          .font(Tokens.Text.headline)
          .foregroundStyle(Tokens.Color.warning)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
          Text(startedAt.map { "Started \(Self.moment($0))" } ?? "Started earlier")
            .font(Tokens.Text.headline)
            .foregroundStyle(Tokens.Color.chalk)
          Text(staleDetail)
            .font(Tokens.Text.provenance)
            .foregroundStyle(Tokens.Color.chalk)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .accessibilityElement(children: .combine)

      if let lastLoggedAt, let onFinishAt {
        Button {
          closeKeypad { onFinishAt(lastLoggedAt) }
        } label: {
          Label("Finish at last set", systemImage: "flag.checkered")
        }
        .buttonStyle(HardsetButtonStyle(.primary, size: .logger))
        .accessibilityLabel("Finish at the last set, \(Self.moment(lastLoggedAt))")
      }
      HStack(spacing: Tokens.Spacing.snug) {
        if onDiscard != nil {
          Button("Discard…") { requestDiscard() }
            .buttonStyle(HardsetButtonStyle(.destructive, size: .logger))
            .accessibilityLabel("Discard workout")
        }
        Button("Continue workout") {
          // Leaves at once, and the cards below take its place at once: layout never animates.
          isStaleAcknowledged = true
        }
        .buttonStyle(HardsetButtonStyle(.secondary, size: .logger))
      }
    }
    .padding(Tokens.Spacing.regular)
    .hardsetCard()
  }

  private var staleDetail: String {
    if let lastLoggedAt {
      return "This workout is still open. Its last set was logged \(Self.moment(lastLoggedAt)). "
        + "Finishing there keeps its real length."
    }
    return "This workout is still open, and nothing has been logged in it."
  }

  // MARK: - Cards

  /// The workout has no gym, no machine picker is on offer, and a gym can be set from here. Then a
  /// card's machine chip has a real next step, choosing a gym, and no gym is the reason it says so.
  private var machineChipNeedsGym: Bool {
    onSelectMachine == nil && gymName == nil && onChangeGym != nil
  }

  /// What a card's machine chip does: open the machine picker, or with no gym, the choice of one.
  /// `nil` when neither is possible, which hides the chip.
  private func machineChipAction(for id: UUID) -> (() -> Void)? {
    if let select = onSelectMachine {
      return { closeKeypad { select(id) } }
    }
    if machineChipNeedsGym, let changeGym = onChangeGym {
      return { closeKeypad(then: changeGym) }
    }
    return nil
  }

  private func card(for exercise: Binding<ExerciseLogState>) -> some View {
    let id = exercise.wrappedValue.id
    let index = exercises.firstIndex { $0.id == id }
    let isFirst = index == exercises.indices.first
    let isLast = index == exercises.indices.last
    let editsThisCard = keypad?.exerciseID == id
    return ExerciseSectionView(
      state: exercise,
      unit: unit,
      onLogSet: { slot in onLogSet(id, slot) },
      onStartRest: onStartRest.map { start in { duration in start(id, duration) } },
      onSelectMachine: machineChipAction(for: id),
      machineNeedsGym: machineChipNeedsGym,
      onShowHistory: onShowHistory.map { show in
        { closeKeypad { show(id) } }
      },
      lastRest: lastRest[id],
      // The one accent on the screen is the workout's primary action; every other row is drawn
      // as ready, in chalk.
      decidesAccent: true,
      accentedSlotID: accentSlotID,
      allowsCorrection: onCorrectSet != nil,
      editingSlotID: editsThisCard ? keypad?.slotID : nil,
      editingField: editsThisCard ? keypad?.field : nil,
      editingText: editsThisCard ? keypadBuffer.displayText : nil,
      onBeginEditing: { slot, field in
        beginEditing(exerciseID: id, slotID: slot.id, field: field)
      },
      onUndoSet: onUndoSet.map { undo in
        { slot in _ = undo(id, slot) }
      },
      onEditSet: onUndoSet == nil ? nil : { slot in editSet(slot, inExercise: id) },
      onRemoveSet: onRemoveSet.map { remove in
        { slot in remove(id, slot) }
      },
      onMoveUp: onMoveExercise == nil || isFirst ? nil : { move(id, by: -1) },
      onMoveDown: onMoveExercise == nil || isLast ? nil : { move(id, by: 1) },
      onRemove: onRemoveExercise == nil ? nil : { requestRemoval(of: id) }
    )
  }

  /// "Edit set" on a saved row. Where the screen can write a correction the keypad opens on the
  /// weight and the set stays saved while it is corrected. Where it cannot, editing is the older
  /// path: the set is undone, the numbers stay in the row, the keypad opens on them, and the set is
  /// saved anew only when the lifter logs it.
  private func editSet(_ slot: SetSlot, inExercise id: UUID) {
    if onCorrectSet != nil {
      beginEditing(exerciseID: id, slotID: slot.id, field: .weight)
      return
    }
    guard let onUndoSet, onUndoSet(id, slot) else { return }
    beginEditing(exerciseID: id, slotID: slot.id, field: .weight)
  }

  private func move(_ id: UUID, by offset: Int) {
    onMoveExercise?(id, offset)
    // Follows the card, so a move never leaves the lifter looking at a different movement.
    scrollRequest = ScrollRequest(target: .view(id), anchor: nil)
  }

  /// A movement with nothing logged is removed at once: it holds no saved sets. One with logged
  /// sets asks first, naming what will be deleted.
  private func requestRemoval(of id: UUID) {
    guard let exercise = exercises.first(where: { $0.id == id }), let onRemoveExercise else {
      return
    }
    let logged = exercise.loggedCount
    guard logged > 0 else {
      onRemoveExercise(id)
      return
    }
    closeKeypad {
      removal = RemovalRequest(exerciseID: id, name: exercise.exerciseName, loggedSets: logged)
    }
  }

  private var isConfirmingRemoval: Binding<Bool> {
    Binding(get: { removal != nil }, set: { if !$0 { removal = nil } })
  }

  /// The place the next movement goes: a line of type with a plus, across the width of the list,
  /// with no dashed outline. It is a 56 pt row because it is a logger control.
  private func addMovementSlot(action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Label("Add movement", systemImage: "plus")
        .font(Tokens.Text.headline)
        .foregroundStyle(Tokens.Color.chalk)
    }
    .buttonStyle(
      InlineControlStyle(minHeight: Tokens.loggerTapTarget, alignment: .leading, fullWidth: true)
    )
  }

  // MARK: - Feedback beside the thumb

  /// What sits at the bottom of the screen: a failed save, the records just set, and the rest bar.
  ///
  /// Here rather than at the top of the list. Inserted above the cards, a record or an error was
  /// off screen whenever the lifter was logging a lower movement, and its arrival pushed every row
  /// down by its height, under the thumb that was about to log the next set. A growing inset moves
  /// nothing already on screen.
  ///
  /// While the keypad is up it covers this area, so the inset becomes room to scroll the edited row
  /// clear of the keypad instead; the keypad repeats any error and the rest countdown itself.
  ///
  /// The stack is capped at accessibility sizes, where the type that is meant to be readable would
  /// otherwise cover most of the screen and leave no window to log in: the record notice collapses to
  /// one line that opens its detail, the rest bar keeps its countdown and controls, and the one-time
  /// correction hint waits for the rest to end. `SingleThumbReachTests` measures what is left.
  @ViewBuilder private var bottomInset: some View {
    if keypad != nil {
      Color.clear
        .frame(height: max(0, padHeight + Self.homeIndicatorAllowance - outerBottomInset))
        .accessibilityHidden(true)
    } else {
      VStack(spacing: Tokens.Spacing.snug) {
        if let errorMessage {
          // A failed write is stated, not swallowed. The row it belongs to is still unlogged,
          // so the user can retry rather than discovering the gap days later.
          HardsetBanner(.error, message: errorMessage, onDismiss: onDismissError)
            .padding(.horizontal, Tokens.Spacing.regular)
            .hardsetArrival()
        }
        if !records.isEmpty {
          recordsNotice
            .reachTarget(.recordNotice)
            .padding(.horizontal, Tokens.Spacing.regular)
            .hardsetArrival(beat: .follow)
        }
        if isShowingCorrectionHint {
          correctionHint
            .padding(.horizontal, Tokens.Spacing.regular)
            .hardsetArrival(beat: .follow)
        }
        // The log moment's follow beat: the bar is inserted when a rest begins, and fades in just
        // after the stamp lands instead of cutting in at full strength on a clock of its own.
        // Idle draws nothing, so it is not in the hierarchy then, which is also what lets its
        // arrival be an insertion. It leaves at once, as every message does.
        if !isRestIdle {
          RestBarView(
            state: restState,
            metadata: restMetadata,
            nextRest: restExerciseID.flatMap { lastRest[$0] },
            restChoices: ExerciseSectionView.restChoices,
            onChooseNextRest: restChooser,
            onAdjust: { delta in
              restControlTaps += 1
              onAdjustRest(delta)
            },
            onPauseResume: {
              restControlTaps += 1
              onPauseResumeRest()
            },
            onSkip: {
              restControlTaps += 1
              onSkipRest()
            }
          )
          .reachTarget(.restBar)
          .hardsetArrival(beat: .follow)
        }
      }
      .padding(.bottom, isRestIdle && (hasFeedback || isShowingCorrectionHint) ? Tokens.Spacing.snug : 0)
    }
  }

  /// The rest bar's chooser, when the caller offers one and a movement's rest is running.
  private var restChooser: ((Duration) -> Void)? {
    guard let onChooseNextRest, let restExerciseID else { return nil }
    return { duration in onChooseNextRest(restExerciseID, duration) }
  }

  /// How a message arrives is `hardsetArrival()`, the one insertion-only reveal in the kit, so the
  /// session cannot drift from the pickers and the name sheet.

  /// The failure being shown, and which failure it is.
  private var errorSignal: ErrorSignal {
    ErrorSignal(message: errorMessage, event: errorEvent)
  }

  /// A running rest that reached its deadline and went idle, on a phone with no alarm to mark it.
  /// A second's grace covers the reconciliation that ends it slightly after the deadline passes.
  nonisolated static func restEndedByDeadline(
    from old: RestTimerState, to new: RestTimerState, alarmless: Bool, now: Date = Date()
  ) -> Bool {
    guard alarmless, case .running(let end) = old, case .idle = new else { return false }
    return end <= now.addingTimeInterval(1)
  }

  /// What VoiceOver is told when a rest starts or runs out on its own. The bar's countdown is not
  /// focused when it appears, so without this a rest began and ended in silence.
  static func restAnnouncement(
    from old: RestTimerState, to new: RestTimerState, alarmless: Bool, now: Date = Date()
  ) -> String? {
    if case .idle = old, case .running(let end) = new {
      let seconds = max(0, end.timeIntervalSince(now)).rounded()
      return "Resting, \(ExerciseSectionView.spoken(.seconds(seconds)))"
    }
    if restEndedByDeadline(from: old, to: new, alarmless: alarmless, now: now) {
      return "Rest over"
    }
    return nil
  }

  private var hasFeedback: Bool { errorMessage != nil || !records.isEmpty }

  /// The correction hint is owed, and this is a moment to draw it: something is saved to correct,
  /// the screen can write a correction, and nothing more urgent is on the bottom edge. A failure or
  /// a new record has the line to itself, so the hint waits and is drawn, and counted as seen, only
  /// when it is actually in front of the lifter. At accessibility sizes it also waits while a rest
  /// runs, because it would stack on the rest bar and cover the set being logged; it is spent when it
  /// is drawn, so it is still owed when the rest ends.
  private var isShowingCorrectionHint: Bool {
    showsCorrectionHint && onCorrectSet != nil && !hasFeedback
      && !(dynamicTypeSize.isAccessibilitySize && !isRestIdle)
      && exercises.contains { $0.loggedCount > 0 }
  }

  /// One quiet line in `provenance` and `chalkDim`, with an inline "Got it" to put it away. It is
  /// not a modal and not a banner, takes no colour and no motion of its own beyond the standard
  /// insertion reveal, and wraps at any Dynamic Type size, where the dismissal drops below it.
  private var correctionHint: some View {
    let layout: AnyLayout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tokens.Spacing.tight))
      : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Tokens.Spacing.regular))
    return layout {
      Text("Tap a saved weight or reps to correct it.")
        .hardsetText(.provenance)
        .foregroundStyle(Tokens.Color.chalkDim)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
      if let onDismissCorrectionHint {
        Button(action: onDismissCorrectionHint) {
          Text("Got it")
            .font(Tokens.Text.provenance)
            .foregroundStyle(Tokens.Color.chalk)
        }
        .buttonStyle(InlineControlStyle(minHeight: Tokens.minimumTapTarget, alignment: .trailing))
      }
    }
    // With the outer inset this lines the words up with the movement cards' own margin.
    .padding(.horizontal, Tokens.Spacing.tight)
    .onAppear { onCorrectionHintShown?() }
  }

  private var isRestIdle: Bool {
    if case .idle = restState { return true }
    return false
  }

  private var runningRestEnd: Date? {
    if case .running(let endsAt) = restState { return endsAt }
    return nil
  }

  /// Whether the notice is one line. At accessibility sizes the full card, a title and a sentence per
  /// record with the certainty phrase under the estimate, was about half the screen on its own and
  /// stacked on the rest bar covered about eighty percent of it. So the notice collapses to a count
  /// that opens its detail, "Worked from", where every record, what it beat and the sets behind it
  /// are written out and can be read at the lifter's own pace. Only where there is a way to open that
  /// detail: without one, collapsing would hide the records, so the card stays whole.
  private var collapsesRecords: Bool {
    dynamicTypeSize.isAccessibilitySize && onExplainRecords != nil
  }

  @ViewBuilder private var recordsNotice: some View {
    if collapsesRecords {
      recordsLine
    } else {
      recordsCard
    }
  }

  /// A count with no sentence: the figures and what each beat are in the detail the line opens. The
  /// whole line is a 56 pt control, the logger's own floor, so a missed tap costs nothing; the trophy
  /// is the record's one mark, and a close mark puts the notice away.
  private var recordsLine: some View {
    HStack(alignment: .center, spacing: Tokens.Spacing.regular) {
      Button {
        onExplainRecords?()
      } label: {
        HStack(alignment: .center, spacing: Tokens.Spacing.regular) {
          Image(systemName: "trophy.fill")
            .font(Tokens.Text.headline)
            .foregroundStyle(Tokens.Color.plateYellow)
            .accessibilityHidden(true)
          Text(recordsCountTitle)
            .font(Tokens.Text.headline)
            .foregroundStyle(Tokens.Color.chalk)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(
        InlineControlStyle(minHeight: Tokens.loggerTapTarget, alignment: .leading, fullWidth: true)
      )
      // Begins with the words the line shows, so a Voice Control user can say what they see; the
      // record is new, and says which movement earned it, which the line itself does not.
      .accessibilityLabel(
        [recordsCountTitle, "new", recordsExerciseName].compactMap { $0 }.joined(separator: ", "))
      .accessibilityHint("Shows what each record beat and the sets behind it")
      if let onDismissRecords {
        DismissGlyphButton(action: onDismissRecords)
      }
    }
    .padding(Tokens.Spacing.regular)
    .hardsetPanel()
  }

  /// "1 record" or "2 records": short enough to stay on one line beside the trophy and the close mark
  /// at the largest size, which a sentence, or even "2 new records", is not.
  private var recordsCountTitle: String {
    records.count == 1 ? "1 record" : "\(records.count) records"
  }

  /// Records from the set just logged, under the movement's name. Each one names what it beat, so
  /// the claim is checkable rather than a bare "PR!", and an estimated maximum carries its
  /// certainty beside it. One line per record, because it shares the bottom with the rest bar.
  ///
  /// A record is marked by the trophy in `plateYellow` and nothing else: the panel is the same
  /// neutral raised tone as the rest bar, the title is chalk, and no yellow fills or outlines it.
  private var recordsCard: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.regular) {
        Image(systemName: "trophy.fill")
          .font(Tokens.Text.headline)
          .foregroundStyle(Tokens.Color.plateYellow)
          .accessibilityHidden(true)
        Text(recordsTitle)
          .font(Tokens.Text.headline)
          .foregroundStyle(Tokens.Color.chalk)
          .frame(maxWidth: .infinity, alignment: .leading)
        if let onDismissRecords {
          DismissGlyphButton(action: onDismissRecords)
            .accessibilityHidden(true)
        }
      }
      .accessibilityElement(children: .combine)
      .accessibilityActions {
        if let onDismissRecords {
          Button("Dismiss", action: onDismissRecords)
        }
      }
      ForEach(records) { record in
        VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
          Text("\(record.kind.label): \(Self.describe(record, unit: unit))")
            .font(Tokens.Text.provenance)
            .foregroundStyle(Tokens.Color.chalk)
            .fixedSize(horizontal: false, vertical: true)
          if record.kind == .estimatedOneRepMax {
            // Graded by the estimate itself, by rep range, as the receipt and the load chart
            // grade it, rather than one fixed level for every estimate.
            CertaintyBadge(
              level: Self.estimateCertainty(record),
              methodology: ProgressionAnalyzer.source.methodology,
              citation: ProgressionAnalyzer.source.validRange,
              style: .language
            )
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Deliberately not combined: the certainty badge inside is a button that opens the
        // methodology disclosure, and combining the row would make it unreachable by VoiceOver.
      }
      // An estimated max is a formula's figure, so the notice can say how it was made: the set, what
      // it beat, the formula, and every set left out. A compact control, so it never outweighs the
      // record it explains.
      if let onExplainRecords {
        WorkedFromButton("Worked from", style: .compact, action: onExplainRecords)
          // Begins with the words the control shows, so a Voice Control user can say what they see.
          .accessibilityLabel("Worked from, \(recordsTitle)")
          .accessibilityHint("Shows the sets this record was worked from")
        if let recordsWorkingError {
          Text(recordsWorkingError)
            .font(Tokens.Text.provenance)
            .foregroundStyle(Tokens.Color.chalkDim)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .padding(Tokens.Spacing.regular)
    .hardsetPanel()
  }

  private var recordsTitle: String {
    let noun = records.count == 1 ? "New record" : "New records"
    return recordsExerciseName.map { "\($0) · \(noun)" } ?? noun
  }

  /// Spells out the comparison. An estimated-1RM record says it is an estimate, because
  /// guideline 1.4.1 is about not presenting an estimate as a measurement.
  ///
  /// Written in the unit the lifter reads everything else in. Hard-coding "kg" here told a lifter
  /// training in pounds that they had set a record of 102 kg, a number they never saw anywhere.
  static func describe(_ record: PersonalRecord, unit: WeightUnit = .kilograms) -> String {
    let weight = "\(Self.trim(unit.fromKilograms(record.weightKg))) \(unit.abbreviation)"
    switch record.kind {
    case .heaviestLoad:
      if let previous = record.previousWeightKg {
        return "\(weight), up from \(Self.trim(unit.fromKilograms(previous))) \(unit.abbreviation)"
      }
      return weight
    case .repsAtLoad:
      if let previousReps = record.previousReps {
        return "\(record.reps) reps at \(weight), up from \(previousReps)"
      }
      return "\(record.reps) reps at \(weight)"
    case .loadAtReps:
      if let previous = record.previousWeightKg {
        return "\(weight) for \(record.reps) reps, up from \(Self.trim(unit.fromKilograms(previous))) \(unit.abbreviation)"
      }
      return "\(weight) for \(record.reps) reps"
    case .estimatedOneRepMax:
      // States the new estimate as well as the old one, so the claim can be checked, and rounds
      // both as every other estimate in the app is rounded: to 0.5 kg or 1 lb, never to the
      // two decimals of a typed load, which would read as a measurement.
      let estimate = StrengthMath.estimatedOneRepMax(weightKg: record.weightKg, reps: record.reps)
      let estimateText = estimate.value.map {
        "About \(LoadText.estimate($0, in: unit)) \(unit.abbreviation)"
      }
      let previousText = record.previousWeightKg.map {
        "about \(LoadText.estimate($0, in: unit)) \(unit.abbreviation)"
      }
      switch (estimateText, previousText) {
      case let (estimate?, previous?): return "\(estimate), up from \(previous)"
      case let (estimate?, nil): return estimate
      case let (nil, previous?): return "Estimated, up from \(previous)"
      case (nil, nil): return "Estimated"
      }
    }
  }

  /// The certainty of the estimate behind an estimated-1RM record, from the set that earned it.
  static func estimateCertainty(_ record: PersonalRecord) -> CertaintyLevel {
    switch StrengthMath.estimatedOneRepMax(weightKg: record.weightKg, reps: record.reps).certainty {
    case .high: .high
    case .moderate: .moderate
    case .low: .low
    case .unevaluated: .unevaluated
    }
  }

  /// The logger's one load figure, so a record reads the same number as the field it was typed in.
  static func trim(_ value: Double) -> String {
    LoadFigure.text(value)
  }

  // MARK: - Finishing

  /// The session's totals, then the way out of it.
  private var summary: some View {
    let volume = SessionVolume(exercises: exercises)
    return VStack(alignment: .leading, spacing: Tokens.Spacing.loose) {
      VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
        // The one hairline on the screen that is not between two set rows: it separates the
        // workout's totals from the movements above them.
        Rectangle()
          .fill(Tokens.Color.hairline)
          .frame(height: Tokens.Stroke.hairline)
          .accessibilityHidden(true)
        SectionLabel("This workout")
        if volume.isEmpty {
          Text("No sets logged yet")
            .font(Tokens.Text.label)
            .foregroundStyle(Tokens.Color.chalkDim)
        } else {
          StatLedger(ledgerItems(volume))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)
      .accessibilityLabel(volumeDescription)

      finishControls
    }
    // Scrolls the confirmation into view once it has its expanded height. Scrolling in the same
    // update as the expansion used the collapsed layout, and the answer buttons stayed under the
    // tab bar, below the fold.
    .onGeometryChange(for: CGFloat.self) { geometry in
      geometry.size.height
    } action: { _ in
      guard revealsFinish, isConfirmingFinish else { return }
      revealsFinish = false
      scrollRequest = ScrollRequest(target: .finish, anchor: .bottom)
    }
  }

  @ViewBuilder private var finishControls: some View {
    if isConfirmingFinish {
      VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
        Text("Finish this workout? Sets you have not logged are not saved.")
          .font(Tokens.Text.provenance)
          .foregroundStyle(Tokens.Color.chalk)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityFocused($isFinishQuestionFocused)
        if let lastLoggedAt, let onFinishAt, offersFinishAtLastSet(lastLoggedAt) {
          // A workout left open: "now" is not when it ended. Both ends are explicit choices.
          Button {
            setConfirming(false)
            onFinishAt(lastLoggedAt)
          } label: {
            Text("Finish at last set, \(Self.moment(lastLoggedAt))")
          }
          .buttonStyle(HardsetButtonStyle(.primary, size: .logger))
          HStack(spacing: Tokens.Spacing.snug) {
            Button("Keep training") {
              setConfirming(false)
            }
            .buttonStyle(HardsetButtonStyle(.secondary, size: .logger))
            Button("Finish now") {
              setConfirming(false)
              onFinish()
            }
            .buttonStyle(HardsetButtonStyle(.secondary, size: .logger))
          }
        } else {
          HStack(spacing: Tokens.Spacing.snug) {
            Button("Keep training") {
              setConfirming(false)
            }
            .buttonStyle(HardsetButtonStyle(.secondary, size: .logger))
            Button("Finish") {
              setConfirming(false)
              onFinish()
            }
            .buttonStyle(HardsetButtonStyle(.primary, size: .logger))
          }
        }
      }
      .hardsetArrival()
    } else {
      Button {
        requestFinish()
      } label: {
        Label("Finish workout", systemImage: "flag.checkered")
      }
      .buttonStyle(HardsetButtonStyle(.secondary, size: .logger))
      .hardsetArrival()
    }
  }

  /// How long after the last logged set "now" stops being an honest end for the workout.
  ///
  /// Not a rule the app applies: past it, the confirmation only offers the last set's time beside
  /// "now", and the lifter chooses. Longer than any rest the app offers, so a lifter finishing
  /// straight after their last set is asked the plain question.
  static let lastSetFinishOffer: TimeInterval = 30 * 60

  /// Offers "Finish at last set" for a workout left open, by the stale rule or because the last
  /// set was logged long enough ago that finishing now would add the idle time to its length.
  private func offersFinishAtLastSet(_ lastLoggedAt: Date) -> Bool {
    isStale || Date().timeIntervalSince(lastLoggedAt) >= Self.lastSetFinishOffer
  }

  /// Opens the finish confirmation and brings it on screen, wherever it was asked from.
  private func requestFinish() {
    closeKeypad {
      setConfirming(true)
      revealsFinish = true
      scrollRequest = ScrollRequest(target: .finish, anchor: .bottom)
      // The menu or button that asked has gone; VoiceOver lands on the question it opened.
      isFinishQuestionFocused = true
    }
  }

  private func requestDiscard() {
    closeKeypad { isConfirmingDiscard = true }
  }

  private var discardMessage: String {
    let logged = exercises.reduce(0) { $0 + $1.loggedCount }
    if logged == 0 {
      return "Nothing has been logged in it, so nothing is lost. It will not appear in History."
    }
    return "The \(Self.setCount(logged)) logged in it will be deleted, and it will not appear in "
      + "History. This cannot be undone."
  }

  /// No animated transaction: the confirmation fades in through its own transition while the
  /// summary takes its new height at once.
  private func setConfirming(_ value: Bool) {
    isConfirmingFinish = value
  }

  private func ledgerItems(_ volume: SessionVolume) -> [StatLedger.Item] {
    var items = [
      StatLedger.Item(label: "Working sets", value: String(volume.workingSets)),
      StatLedger.Item(label: "Reps", value: String(volume.reps)),
    ]
    if volume.volumeKg > 0 {
      let displayed = Int(unit.fromKilograms(volume.volumeKg).rounded())
      items.append(
        StatLedger.Item(
          label: "Volume", value: displayed.formatted(.number), unit: unit.abbreviation
        )
      )
    }
    if volume.warmupSets > 0 {
      items.append(StatLedger.Item(label: "Warm-ups", value: String(volume.warmupSets)))
    }
    return items
  }

  /// Counted by `SessionVolume`, which is tested. The rules that matter — unlogged rows and
  /// warm-ups excluded — live there rather than here, so this screen cannot disagree with the
  /// history screen about what the session contained.
  private var volumeDescription: String {
    let volume = SessionVolume(exercises: exercises)
    guard !volume.isEmpty else { return "No sets logged yet" }
    let displayed = unit.fromKilograms(volume.volumeKg)
    var parts = [
      volume.workingSets == 1 ? "1 set" : "\(volume.workingSets) sets",
      volume.reps == 1 ? "1 rep" : "\(volume.reps) reps",
    ]
    if volume.volumeKg > 0 {
      parts.append("\(Int(displayed.rounded())) \(unit.abbreviation) volume")
    }
    if volume.warmupSets > 0 {
      parts.append(volume.warmupSets == 1 ? "1 warm-up" : "\(volume.warmupSets) warm-ups")
    }
    return parts.joined(separator: ", ")
  }

  // MARK: - Keypad

  private var isKeypadPresented: Binding<Bool> {
    Binding(get: { keypad != nil }, set: { if !$0 { dismissKeypad() } })
  }

  private var targetedSlot: SetSlot? {
    guard let keypad else { return nil }
    return slot(exerciseID: keypad.exerciseID, slotID: keypad.slotID)
  }

  /// The first set, in workout order, that is not logged: where the reach check's keypad opens.
  private var firstUnloggedSlot: (exerciseID: UUID, slotID: UUID)? {
    for exercise in exercises {
      if let slot = exercise.slots.first(where: { !$0.isLogged }) {
        return (exercise.id, slot.id)
      }
    }
    return nil
  }

  /// The row whose log control wears the screen's one accent: the workout's primary action, the
  /// first row that is not logged and can be (`ExerciseLogState.primarySlotID`). While the keypad is
  /// up its own primary action, Next or Log set, is the accent, and no row has it.
  private var accentSlotID: UUID? {
    keypad == nil ? ExerciseLogState.primarySlotID(in: exercises) : nil
  }

  private func slot(exerciseID: UUID, slotID: UUID) -> SetSlot? {
    exercises.first { $0.id == exerciseID }?.slots.first { $0.id == slotID }
  }

  /// Puts the keypad on a field, or moves it there if it is already up. A field that already
  /// holds a value is armed to be replaced by the first digit typed, so retyping a prefilled
  /// weight does not mean deleting it first.
  ///
  /// A saved row's field opens the keypad as a correction, where the screen can write one. Leaving a
  /// field that has a correction typed into it writes that correction first, and stays put if the
  /// write fails, so the lifter sees why before anything else moves.
  private func beginEditing(exerciseID: UUID, slotID: UUID, field: SetRowField) {
    guard let opened = slot(exerciseID: exerciseID, slotID: slotID) else { return }
    let isCorrection = opened.isLogged
    guard !isCorrection || onCorrectSet != nil else { return }
    // Opening a saved figure is what the hint teaches, so there is nothing left to teach.
    if isCorrection { onDismissCorrectionHint?() }
    let target = KeypadTarget(
      exerciseID: exerciseID, slotID: slotID, field: field, isCorrection: isCorrection)
    if keypad != target {
      guard commitCorrection() else { return }
      // Read again: writing the correction changed the row it came from.
      guard let current = slot(exerciseID: exerciseID, slotID: slotID) else { return }
      keypadBuffer = Self.buffer(for: current.draft, field: field, unit: unit)
    }
    keypadBuffer.replaceOnFirstEntry = !keypadBuffer.isEmpty
    keypad = target
    shownKeypad = target
  }

  /// Writes the correction typed into a saved figure, if one was typed. `true` when there was
  /// nothing to write or it was saved; `false` when the write failed, with the error on screen.
  ///
  /// There is nothing to write for an unsaved row, whose keystrokes already go to its draft, for a
  /// field left empty or typed back to what it held, or for figures that are not a complete set.
  /// Those leave the saved figures as they were. The typed text never touches the row's draft:
  /// the figure on screen is the saved one until the write has succeeded.
  @discardableResult
  private func commitCorrection() -> Bool {
    guard let target = keypad, target.isCorrection, let onCorrectSet,
      let saved = slot(exerciseID: target.exerciseID, slotID: target.slotID), saved.isLogged,
      !Self.buffer(keypadBuffer, agreesWith: saved.draft, field: target.field, unit: unit)
    else { return true }
    var corrected = saved.draft
    switch target.field {
    case .weight:
      guard let typed = keypadBuffer.value else { return true }
      corrected.weightKg = unit.toKilograms(typed)
    case .reps:
      guard let typed = keypadBuffer.value.flatMap({ Int(exactly: $0) }) else { return true }
      corrected.reps = typed
    }
    guard corrected.isLoggable else { return true }
    return onCorrectSet(target.exerciseID, saved, corrected)
  }

  /// Closes the keypad, writing a correction typed into a saved figure first. A failed write still
  /// closes it: the row reads what it was saved with and the banner says the correction was not.
  private func dismissKeypad() {
    commitCorrection()
    keypad = nil
  }

  /// "Next" on the weight field: the same keypad, retargeted in place. Dismissing and presenting
  /// it again between the two numbers of every set cost half a second of sliding keys, and a digit
  /// typed during it was lost.
  private func advanceToReps() {
    guard let target = keypad else { return }
    beginEditing(exerciseID: target.exerciseID, slotID: target.slotID, field: .reps)
  }

  /// "Log set" on the keypad logs the row it names. The keypad closes when, and only when, the
  /// row is marked logged, which happens after the write succeeds.
  private func logFromKeypad() {
    guard let target = keypad, let slot = targetedSlot else { return }
    onLogSet(target.exerciseID, slot)
  }

  private var keypadBinding: Binding<NumericEntryBuffer> {
    Binding(
      get: { keypadBuffer },
      set: { buffer in
        keypadBuffer = buffer
        writeKeypadValue()
      }
    )
  }

  /// Writes only the field being edited. Editing reps must never round-trip an untouched
  /// canonical load through a rounded pounds display. There is no `?? 0` here: an empty
  /// buffer stays nil and cannot make a row loggable.
  private func writeKeypadValue() {
    guard let target = keypad, !target.isCorrection,
      let exerciseIndex = exercises.firstIndex(where: { $0.id == target.exerciseID }),
      let slotIndex = exercises[exerciseIndex].slots.firstIndex(where: { $0.id == target.slotID }),
      !exercises[exerciseIndex].slots[slotIndex].isLogged
    else { return }
    switch target.field {
    case .weight:
      exercises[exerciseIndex].slots[slotIndex].draft.weightKg = keypadBuffer.value.map(unit.toKilograms)
    case .reps:
      exercises[exerciseIndex].slots[slotIndex].draft.reps = keypadBuffer.value.flatMap { Int(exactly: $0) }
    }
  }

  /// Closes the keypad, then runs `action` once it has gone. Runs it at once when no keypad is up.
  private func closeKeypad(then action: @escaping () -> Void) {
    guard keypad != nil else {
      action()
      return
    }
    afterKeypadCloses = action
    dismissKeypad()
  }

  private func keypadDidDismiss() {
    let action = afterKeypadCloses
    afterKeypadCloses = nil
    action?()
  }

  /// "Leg Press · Set 2": which set the keypad is writing to, since the row may be under it.
  private func keypadContext(for target: KeypadTarget) -> String? {
    guard let exercise = exercises.first(where: { $0.id == target.exerciseID }),
      let index = exercise.slots.firstIndex(where: { $0.id == target.slotID })
    else { return nil }
    let slot = exercise.slots[index]
    let set = slot.isWarmup ? "Warm-up" : "Set \(exercise.slots[..<index].count { !$0.isWarmup } + 1)"
    // A saved set says so, so the lifter knows the digits correct something already written.
    return "\(exercise.exerciseName) · \(set)" + (target.isCorrection ? " · Correcting" : "")
  }

  private var keypadSheet: some View {
    let target = keypad ?? shownKeypad
    let field = target?.field ?? .weight
    // The weight steps are the machine's real increment where one is recorded, the same number the
    // row's −/+ use, so the pad never steps to a load the equipment cannot hold.
    let machineIncrementKg = target.flatMap { target in
      exercises.first(where: { $0.id == target.exerciseID })?.machineIncrementKg
    }
    return ScrollView {
      VStack(spacing: 0) {
        // The keypad covers the bottom of the screen where errors are shown, so a set that fails
        // to log from here says so here.
        if let errorMessage {
          HardsetBanner(.error, message: errorMessage)
            .padding(.horizontal, Tokens.Spacing.regular)
            .padding(.top, Tokens.Spacing.loose)
        }
        NumericPad(
          buffer: keypadBinding,
          title: field == .weight ? "Weight" : "Reps",
          context: target.flatMap { keypadContext(for: $0) },
          unit: field == .weight ? unit.abbreviation : "reps",
          restEndsAt: runningRestEnd,
          onDone: { dismissKeypad() },
          onNext: field == .weight ? { advanceToReps() } : nil,
          // A correction has no "Log set": the set is already logged, and Done writes the change.
          onLog: field == .reps && target?.isCorrection != true ? { logFromKeypad() } : nil,
          canLog: targetedSlot?.draft.isLoggable ?? false,
          weightSteps: QuickSteps.weight(machineIncrementKg: machineIncrementKg, unit: unit)
        )
        .reachTarget(.keypad)
      }
      // Measured rather than fixed. A hard-coded 370 pt detent was shorter than the pad's own
      // minimum (380 pt before any larger text), so the bottom row could clip; the scroll view
      // keeps every key reachable when the measured height exceeds what the screen offers.
      .onGeometryChange(for: CGFloat.self) { geometry in
        geometry.size.height
      } action: { height in
        padHeight = height
      }
    }
    .scrollBounceBehavior(.basedOnSize)
    .background(Tokens.Color.steel)
    // A fresh keypad scrolls its row clear of itself, by the least amount, and only if the row
    // would be covered. Retargeting does not scroll: a row tapped while the keypad is up was
    // already in view.
    .onAppear {
      if let target {
        scrollRequest = ScrollRequest(target: .view(target.slotID), anchor: nil)
      }
    }
    .presentationDetents([.height(padHeight)])
    .presentationBackground(Tokens.Color.steel)
    .presentationDragIndicator(.hidden)
    // The rows stay visible and tappable behind the pad, so this reads as a keyboard replacement
    // rather than a modal that interrupts the set: another row's field retargets it, and the
    // row's own check logs.
    #if os(iOS)
      .presentationBackgroundInteraction(.enabled(upThrough: .height(padHeight)))
      .presentationCornerRadius(Tokens.Radius.card)
    #endif
  }

  static func buffer(
    for draft: SetEntryDraft, field: SetRowField, unit: WeightUnit
  ) -> NumericEntryBuffer {
    switch field {
    case .weight:
      // The draft is canonical kilograms; the buffer is what the lifter reads.
      return NumericEntryBuffer(
        value: draft.weightKg.map(unit.fromKilograms),
        maximumIntegerDigits: 4,
        maximumFractionDigits: 2
      )
    case .reps:
      return NumericEntryBuffer(
        value: draft.reps.map(Double.init),
        allowsDecimal: false,
        maximumIntegerDigits: 3,
        maximumFractionDigits: 0
      )
    }
  }

  /// Whether the keypad's text already says what the draft holds. The keypad's own writes always
  /// agree; a disagreement means the draft was changed by something else.
  static func buffer(
    _ buffer: NumericEntryBuffer, agreesWith draft: SetEntryDraft, field: SetRowField,
    unit: WeightUnit
  ) -> Bool {
    switch field {
    case .weight:
      let typed = buffer.value.map(unit.toKilograms)
      if let saved = draft.weightKg, let typed {
        return abs(saved - typed) <= unit.toKilograms(0.005) + 1e-10
      }
      return draft.weightKg == typed
    case .reps:
      return buffer.value.flatMap { Int(exactly: $0) } == draft.reps
    }
  }

  // MARK: - Shared

  static let finishAnchor = "session.finish"

  /// The home indicator's height on current iPhones. The keypad sheet sits above it, and the
  /// measured inset already contains it, so it is added back when reserving the keypad's room.
  /// On a phone without one this reserves a little more than needed, which only scrolls a row
  /// slightly higher.
  static let homeIndicatorAllowance: CGFloat = 34

  /// "today at 18:04", "yesterday at 18:04", "Monday 3 November at 18:04", with the year only when
  /// it is not this year, so an old workout is never read as a recent one.
  static func moment(_ date: Date, now: Date = Date()) -> String {
    let time = date.formatted(date: .omitted, time: .shortened)
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return "today at \(time)" }
    if calendar.isDateInYesterday(date) { return "yesterday at \(time)" }
    var style: Date.FormatStyle = .dateTime.weekday(.wide).day().month(.wide)
    if !calendar.isDate(date, equalTo: now, toGranularity: .year) {
      style = style.year()
    }
    return "\(date.formatted(style)) at \(time)"
  }

  static func setCount(_ count: Int) -> String {
    count == 1 ? "1 set" : "\(count) sets"
  }
}

/// The set and field the session's keypad is on.
private struct KeypadTarget: Hashable {
  let exerciseID: UUID
  let slotID: UUID
  let field: SetRowField
  /// The keypad is on a saved set's figure, correcting it, and not on an unsaved row's draft.
  var isCorrection = false
}

/// Presents the keypad from inside its own modifier body, so the screen's already large view
/// builder is not asked to solve the sheet's generic presentation alongside everything else.
/// Behaviour is the same as a `sheet(isPresented:onDismiss:content:)` on the screen itself.
///
/// `inlineHeight` is for the reach check only: with a height, the pad is drawn as a bottom panel
/// inside the screen so its frame can be measured in the window. With `nil` — every shipped path —
/// it is the real sheet.
private struct KeypadSheetPresentation<Sheet: View>: ViewModifier {
  @Binding var isPresented: Bool
  let onDismiss: () -> Void
  let inlineHeight: CGFloat?
  let sheet: () -> Sheet

  init(
    isPresented: Binding<Bool>, onDismiss: @escaping () -> Void, inlineHeight: CGFloat?,
    @ViewBuilder sheet: @escaping () -> Sheet
  ) {
    _isPresented = isPresented
    self.onDismiss = onDismiss
    self.inlineHeight = inlineHeight
    self.sheet = sheet
  }

  func body(content: Content) -> some View {
    if let inlineHeight {
      content
        .overlay(alignment: .bottom) {
          if isPresented {
            InlineKeypadSurface(height: inlineHeight, content: sheet)
              .transition(.move(edge: .bottom).combined(with: .opacity))
          }
        }
        .onChange(of: isPresented) { old, new in
          if old && !new { onDismiss() }
        }
    } else {
      content.sheet(isPresented: $isPresented, onDismiss: onDismiss, content: sheet)
    }
  }
}

/// The panel the keypad is measured on in the reach check: steel, with the card radius on its top
/// corners and a hairline rim, at the same height the real sheet would take. It never ships.
private struct InlineKeypadSurface<Content: View>: View {
  let height: CGFloat
  @ViewBuilder let content: () -> Content

  var body: some View {
    let shape = UnevenRoundedRectangle(
      topLeadingRadius: Tokens.Radius.card, bottomLeadingRadius: 0, bottomTrailingRadius: 0,
      topTrailingRadius: Tokens.Radius.card)
    content()
      .hardsetControlSurface(.steel)
      .frame(maxWidth: .infinity)
      .frame(height: height)
      .background(Tokens.Color.steel, in: shape)
      .overlay { shape.strokeBorder(Tokens.Color.hairline, lineWidth: Tokens.Stroke.hairline) }
      .clipShape(shape)
  }
}

extension View {
  fileprivate func keypadSheetPresentation<Sheet: View>(
    isPresented: Binding<Bool>, onDismiss: @escaping () -> Void, inlineHeight: CGFloat?,
    @ViewBuilder sheet: @escaping () -> Sheet
  ) -> some View {
    modifier(
      KeypadSheetPresentation(
        isPresented: isPresented, onDismiss: onDismiss, inlineHeight: inlineHeight, sheet: sheet))
  }
}

/// A failure message together with the event that produced it, so two failures with the same
/// words are still two changes.
private struct ErrorSignal: Equatable {
  let message: String?
  let event: Int
}

/// A movement waiting on the lifter's confirmation before its logged sets are deleted.
private struct RemovalRequest {
  let exerciseID: UUID
  let name: String
  let loggedSets: Int
}

/// One scroll, asked for by a state change and performed by the reader that owns the proxy. The
/// token makes two requests for the same place distinct, so both are performed.
private struct ScrollRequest: Equatable {
  enum Target: Equatable {
    case view(UUID)
    case finish
  }

  let target: Target
  let anchor: UnitPoint?
  let token = UUID()
}

#if DEBUG
  #Preview("Live session") {
    struct Harness: View {
      @State private var exercises: [ExerciseLogState]

      init() {
        let press = ExerciseID()
        let machine = MachineID()
        let key = ProgressionKey(exerciseID: press, machineID: machine)
        let records = [
          PriorSetRecord(weightKg: 100, reps: 10, completedAt: .distantPast),
          PriorSetRecord(weightKg: 105, reps: 8, completedAt: .distantPast),
        ]
        let snapshot = PriorPerformanceSnapshot(
          entries: [key: PriorPerformance(key: key, lastSets: records, heaviestSet: records.last)],
          capturedAt: .distantPast
        )
        _exercises = State(
          initialValue: [
            .build(
              exerciseID: press, machineID: machine, exerciseName: "Leg Press",
              machineName: "Hammer Strength", snapshot: snapshot
            ),
            // No history: one empty row, nothing loggable, no invented numbers.
            .build(
              exerciseID: ExerciseID(), exerciseName: "Standing Calf Raise",
              snapshot: .empty(capturedAt: .distantPast)
            ),
          ]
        )
      }

      var body: some View {
        SessionView(
          exercises: $exercises,
          unit: .kilograms,
          title: "Workout",
          gymName: "Metroflex Gym",
          startedAt: Date().addingTimeInterval(-26 * 60 * 60),
          lastLoggedAt: Date().addingTimeInterval(-25 * 60 * 60),
          isStale: true,
          restState: .running(endsAt: Date().addingTimeInterval(96)),
          restMetadata: RestMetadata(
            exerciseName: "Leg Press", setOrdinal: 1, plannedSets: 2,
            machineName: "Hammer Strength"
          ),
          onLogSet: { stateID, slot in
            guard let index = exercises.firstIndex(where: { $0.id == stateID }) else { return }
            exercises[index].markLogged(slotID: slot.id, setID: SetID())
          },
          onStartRest: { _, _ in },
          onAddExercise: {},
          onSelectMachine: { _ in },
          onShowHistory: { _ in },
          onShowSettings: {},
          onChangeGym: {},
          onRemoveExercise: { id in exercises.removeAll { $0.id == id } },
          onMoveExercise: { id, offset in
            guard let from = exercises.firstIndex(where: { $0.id == id }) else { return }
            let to = from + offset
            guard exercises.indices.contains(to) else { return }
            exercises.swapAt(from, to)
          },
          onFinishAt: { _ in },
          onDiscard: {}
        )
      }
    }
    return Harness()
  }
#endif
