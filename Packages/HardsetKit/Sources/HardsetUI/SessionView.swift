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
  private let records: [PersonalRecord]
  private let recordsExerciseName: String?
  private let lastRest: [UUID: Duration]
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
  private let onRemoveSet: ((UUID, SetSlot) -> Void)?
  private let onRemoveExercise: ((UUID) -> Void)?
  private let onMoveExercise: ((UUID, Int) -> Void)?
  private let onDismissError: (() -> Void)?
  private let onDismissRecords: (() -> Void)?
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

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// - Parameter title: Draws a screen header when present. The live session passes "Workout";
  ///   previews and embedded uses can leave it out.
  /// - Parameter gymName: The gym the workout is at. `nil` says no gym is recorded, which is also
  ///   why the machine chips are absent.
  /// - Parameter startedAt: When the workout began, shown in the header, with the day when it was
  ///   not today: a workout reopened from days ago says so.
  /// - Parameter lastLoggedAt: When the newest logged set was completed; the honest end of a
  ///   workout that was left open.
  /// - Parameter isStale: The workout has been open longer than any real session. The caller
  ///   decides by its rule; this view states the fact and offers the choices.
  /// - Parameter records: Records from the set just logged, named after `recordsExerciseName`.
  /// - Parameter lastRest: The rest the lifter last chose per movement, keyed by exercise-state id.
  /// - Parameter onShowSettings: Puts a settings button in the header.
  /// - Parameter onChangeGym: Makes the header's gym a chip that sets or changes it.
  /// - Parameter onUndoSet: Returns a logged set to unlogged. `true` when it was undone.
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
    records: [PersonalRecord] = [],
    recordsExerciseName: String? = nil,
    lastRest: [UUID: Duration] = [:],
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
    onRemoveSet: ((UUID, SetSlot) -> Void)? = nil,
    onRemoveExercise: ((UUID) -> Void)? = nil,
    onMoveExercise: ((UUID, Int) -> Void)? = nil,
    onDismissError: (() -> Void)? = nil,
    onDismissRecords: (() -> Void)? = nil,
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
    self.records = records
    self.recordsExerciseName = recordsExerciseName
    self.lastRest = lastRest
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
    self.onRemoveSet = onRemoveSet
    self.onRemoveExercise = onRemoveExercise
    self.onMoveExercise = onMoveExercise
    self.onDismissError = onDismissError
    self.onDismissRecords = onDismissRecords
    self.onFinish = onFinish
    self.onFinishAt = onFinishAt
    self.onDiscard = onDiscard
  }

  public var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
          if let title {
            header(title: title)
              .padding(.bottom, Tokens.Spacing.snug)
          }

          // Above the movements on purpose, unlike every other message: it is there when the
          // screen opens, so it moves nothing under a thumb, and it is the first thing to read.
          if showsStaleNotice {
            staleNotice
              .padding(.horizontal, Tokens.Spacing.regular)
              .transition(.opacity)
          }

          ForEach($exercises) { $exercise in
            card(for: $exercise)
              .padding(.horizontal, Tokens.Spacing.regular)
          }

          // An empty workout says so, and says what to do about it, rather than rendering a bare
          // "Finish" button under nothing. When it is empty, the empty state carries the add
          // action, so the dashed slot below is not drawn twice.
          if exercises.isEmpty {
            HardsetEmptyState(
              title: "Nothing added yet",
              detail: "Add a movement to start logging sets.",
              systemImage: "dumbbell",
              actionTitle: onAddExercise == nil ? nil : "Add movement",
              action: onAddExercise.map { add in { closeKeypad(then: add) } }
            )
          } else if let onAddExercise {
            addMovementSlot { closeKeypad(then: onAddExercise) }
              .padding(.horizontal, Tokens.Spacing.regular)
          }

          summary
            .padding(.horizontal, Tokens.Spacing.regular)
            .padding(.top, Tokens.Spacing.section)
            .id(Self.finishAnchor)
        }
        .padding(.bottom, Tokens.Spacing.section)
        .animation(
          Tokens.Motion.adaptive(Tokens.Motion.reveal, reduceMotion: reduceMotion),
          value: showsStaleNotice
        )
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
          Text(
            "\(request.name) and its \(Self.setCount(request.loggedSets, adjective: "logged")) "
              + "are deleted from this workout. This cannot be undone."
          )
        }
      }
      .background(Tokens.Color.background)
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
      .confirmationDialog(
        "Discard this workout?",
        isPresented: $isConfirmingDiscard,
        titleVisibility: .visible
      ) {
        Button("Discard workout", role: .destructive) { onDiscard?() }
        Button("Keep workout", role: .cancel) {}
      } message: {
        Text(discardMessage)
      }
    }
    .sheet(isPresented: isKeypadPresented, onDismiss: keypadDidDismiss) {
      keypadSheet
    }
    // A row the keypad is on can change underneath it: logged from its own check, removed, moved
    // to another machine, or stepped with the −/+ buttons. Logged or gone closes the keypad; a
    // new value reseeds it, so the keypad never shows a number the row does not hold.
    .onChange(of: targetedSlot) { _, slot in
      guard let target = keypad else { return }
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
    // A failed save is felt as well as read: the check simply not stamping was easy to miss.
    .sensoryFeedback(.error, trigger: errorMessage) { _, new in new != nil }
    .onChange(of: errorMessage) { _, message in
      if let message {
        AccessibilityNotification.Announcement(message).post()
      }
    }
    .onChange(of: records) { _, records in
      guard !records.isEmpty else { return }
      let spoken = records.map { "\($0.kind.label), \(Self.describe($0, unit: unit))" }
      AccessibilityNotification.Announcement(
        "New record. \(spoken.joined(separator: ". "))"
      ).post()
    }
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
            HeaderIconButton(systemImage: "gearshape", accessibilityLabel: "Settings") {
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
    HeaderIconMenu(accessibilityLabel: "Workout options") {
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

  /// The workout's gym, as the machine chip on each card shows its machine: an invitation in the
  /// accent when none is set, the name with a chevron when one is. Setting it is what makes the
  /// machine chips appear.
  private func gymChip(action: @escaping () -> Void) -> some View {
    let isSet = gymName != nil
    return Button(action: action) {
      HStack(spacing: Tokens.Spacing.snug) {
        Image(systemName: isSet ? "mappin.and.ellipse" : "plus")
          .font(Tokens.Text.caption.weight(.semibold))
        Text(gymName ?? "Set gym")
          .font(Tokens.Text.caption.weight(.semibold))
          .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        if isSet {
          Image(systemName: "chevron.down")
            .font(Tokens.Text.caption.weight(.semibold))
            .foregroundStyle(Tokens.Color.textSecondary)
        }
      }
      .foregroundStyle(isSet ? Tokens.Color.textPrimary : Tokens.Color.accent)
      .padding(.horizontal, Tokens.Spacing.regular)
      .padding(.vertical, Tokens.Spacing.snug)
      .background(isSet ? Tokens.Color.surfaceRaised : Tokens.Color.accentSurface, in: Capsule())
      .overlay(
        Capsule().strokeBorder(
          isSet ? Tokens.Color.controlBorder : Tokens.Color.accent,
          lineWidth: Tokens.Stroke.hairline
        )
      )
      .frame(minHeight: Tokens.minimumTapTarget)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      gymName.map { "Gym: \($0). Change." } ?? "No gym recorded. Set one to track machines."
    )
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
        Image(systemName: "clock.badge.exclamationmark")
          .font(Tokens.Text.headline)
          .foregroundStyle(Tokens.Color.warning)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
          Text(startedAt.map { "Started \(Self.moment($0))" } ?? "Started earlier")
            .font(Tokens.Text.headline)
            .foregroundStyle(Tokens.Color.warning)
          Text(staleDetail)
            .font(Tokens.Text.provenance)
            .foregroundStyle(Tokens.Color.textPrimary)
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
          withAnimation(Tokens.Motion.adaptive(Tokens.Motion.state, reduceMotion: reduceMotion)) {
            isStaleAcknowledged = true
          }
        }
        .buttonStyle(HardsetButtonStyle(.secondary, size: .logger))
      }
    }
    .padding(Tokens.Spacing.regular)
    .background(Tokens.Color.warningSurface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
    .overlay(
      RoundedRectangle(cornerRadius: Tokens.Radius.card)
        .strokeBorder(Tokens.Color.warning.opacity(0.35), lineWidth: Tokens.Stroke.hairline)
    )
  }

  private var staleDetail: String {
    if let lastLoggedAt {
      return "This workout is still open. Its last set was logged \(Self.moment(lastLoggedAt)). "
        + "Finishing there keeps its real length."
    }
    return "This workout is still open, and nothing has been logged in it."
  }

  // MARK: - Cards

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
      onSelectMachine: onSelectMachine.map { select in
        { closeKeypad { select(id) } }
      },
      onShowHistory: onShowHistory.map { show in
        { closeKeypad { show(id) } }
      },
      lastRest: lastRest[id],
      editingSlotID: editsThisCard ? keypad?.slotID : nil,
      editingField: editsThisCard ? keypad?.field : nil,
      editingText: editsThisCard ? keypadBuffer.displayText : nil,
      onBeginEditing: { slot, field in
        beginEditing(exerciseID: id, slotID: slot.id, field: field)
      },
      onUndoSet: onUndoSet.map { undo in
        { slot in _ = undo(id, slot) }
      },
      // Editing a saved set is undoing it and logging it again: the numbers stay in the row, the
      // keypad opens on them, and the set is saved anew only when the lifter logs it.
      onEditSet: onUndoSet.map { undo in
        { slot in
          if undo(id, slot) {
            beginEditing(exerciseID: id, slotID: slot.id, field: .weight)
          }
        }
      },
      onRemoveSet: onRemoveSet.map { remove in
        { slot in remove(id, slot) }
      },
      onMoveUp: onMoveExercise == nil || isFirst ? nil : { move(id, by: -1) },
      onMoveDown: onMoveExercise == nil || isLast ? nil : { move(id, by: 1) },
      onRemove: onRemoveExercise == nil ? nil : { requestRemoval(of: id) }
    )
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

  /// The place the next movement goes. Dashed, like every empty slot in the app.
  private func addMovementSlot(action: @escaping () -> Void) -> some View {
    let shape = RoundedRectangle(cornerRadius: Tokens.Radius.card)
    return Button(action: action) {
      Label("Add movement", systemImage: "plus")
        .font(Tokens.Text.headline)
        .foregroundStyle(Tokens.Color.accent)
        .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
        .contentShape(shape)
        .overlay(
          shape.strokeBorder(
            Tokens.Color.controlBorder,
            style: StrokeStyle(lineWidth: Tokens.Stroke.hairline, dash: [5, 4])
          )
        )
    }
    .buttonStyle(.plain)
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
            .transition(.opacity)
        }
        if !records.isEmpty {
          recordsCard
            .padding(.horizontal, Tokens.Spacing.regular)
            .transition(.opacity)
        }
        RestBarView(
          state: restState,
          metadata: restMetadata,
          onAdjust: onAdjustRest,
          onPauseResume: onPauseResumeRest,
          onSkip: onSkipRest
        )
      }
      .padding(.bottom, isRestIdle && hasFeedback ? Tokens.Spacing.snug : 0)
      .animation(
        Tokens.Motion.adaptive(Tokens.Motion.reveal, reduceMotion: reduceMotion),
        value: errorMessage
      )
      .animation(
        Tokens.Motion.adaptive(Tokens.Motion.reveal, reduceMotion: reduceMotion),
        value: records
      )
    }
  }

  private var hasFeedback: Bool { errorMessage != nil || !records.isEmpty }

  private var isRestIdle: Bool {
    if case .idle = restState { return true }
    return false
  }

  private var runningRestEnd: Date? {
    if case .running(let endsAt) = restState { return endsAt }
    return nil
  }

  /// Records from the set just logged, under the movement's name. Each one names what it beat, so
  /// the claim is checkable rather than a bare "PR!", and an estimated maximum carries its
  /// certainty beside it. One line per record, because it shares the bottom with the rest bar.
  private var recordsCard: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.regular) {
        Image(systemName: "trophy.fill")
          .font(Tokens.Text.headline)
          .foregroundStyle(Tokens.Color.pr)
          .accessibilityHidden(true)
        Text(recordsTitle)
          .font(Tokens.Text.headline)
          .foregroundStyle(Tokens.Color.pr)
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
            .foregroundStyle(Tokens.Color.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
          if record.kind == .estimatedOneRepMax {
            CertaintyBadge(
              level: .moderate,
              methodology: ProgressionAnalyzer.source.methodology,
              citation: ProgressionAnalyzer.source.validRange
            )
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
      }
    }
    .padding(Tokens.Spacing.regular)
    .background(Tokens.Color.prSurface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
    .overlay(
      RoundedRectangle(cornerRadius: Tokens.Radius.card)
        .strokeBorder(Tokens.Color.pr.opacity(0.35), lineWidth: Tokens.Stroke.hairline)
    )
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
    let previousWeight = record.previousWeightKg.map {
      "\(Self.trim(unit.fromKilograms($0))) \(unit.abbreviation)"
    }
    switch record.kind {
    case .heaviestLoad:
      if let previousWeight {
        return "\(weight), up from \(previousWeight)"
      }
      return weight
    case .repsAtLoad:
      if let previousReps = record.previousReps {
        return "\(record.reps) reps at \(weight), up from \(previousReps)"
      }
      return "\(record.reps) reps at \(weight)"
    case .estimatedOneRepMax:
      if let previousWeight {
        return "Estimated, up from about \(previousWeight)"
      }
      return "Estimated"
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
        SectionLabel("This workout")
        if volume.isEmpty {
          Text("No sets logged yet")
            .font(Tokens.Text.label)
            .foregroundStyle(Tokens.Color.textSecondary)
        } else {
          StatLedger(ledgerItems(volume))
        }
      }
      .padding(Tokens.Spacing.regular)
      .frame(maxWidth: .infinity, alignment: .leading)
      .hardsetCard()
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
          .foregroundStyle(Tokens.Color.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
        if isStale, let lastLoggedAt, let onFinishAt {
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
      .transition(.opacity)
    } else {
      Button {
        requestFinish()
      } label: {
        Label("Finish workout", systemImage: "flag.checkered")
      }
      .buttonStyle(HardsetButtonStyle(.secondary, size: .logger))
      .transition(.opacity)
    }
  }

  /// Opens the finish confirmation and brings it on screen, wherever it was asked from.
  private func requestFinish() {
    closeKeypad {
      setConfirming(true)
      revealsFinish = true
      scrollRequest = ScrollRequest(target: .finish, anchor: .bottom)
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
    return "Its \(Self.setCount(logged, adjective: "logged")) will be deleted and it will not "
      + "appear in History. This cannot be undone."
  }

  private func setConfirming(_ value: Bool) {
    withAnimation(Tokens.Motion.adaptive(Tokens.Motion.state, reduceMotion: reduceMotion)) {
      isConfirmingFinish = value
    }
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
    if volume.warmupSets > 0 { parts.append("\(volume.warmupSets) warm-up") }
    return parts.joined(separator: ", ")
  }

  // MARK: - Keypad

  private var isKeypadPresented: Binding<Bool> {
    Binding(get: { keypad != nil }, set: { if !$0 { keypad = nil } })
  }

  private var targetedSlot: SetSlot? {
    guard let keypad else { return nil }
    return slot(exerciseID: keypad.exerciseID, slotID: keypad.slotID)
  }

  private func slot(exerciseID: UUID, slotID: UUID) -> SetSlot? {
    exercises.first { $0.id == exerciseID }?.slots.first { $0.id == slotID }
  }

  /// Puts the keypad on a field, or moves it there if it is already up. A field that already
  /// holds a value is armed to be replaced by the first digit typed, so retyping a prefilled
  /// weight does not mean deleting it first.
  private func beginEditing(exerciseID: UUID, slotID: UUID, field: SetRowField) {
    guard let slot = slot(exerciseID: exerciseID, slotID: slotID), !slot.isLogged else { return }
    let target = KeypadTarget(exerciseID: exerciseID, slotID: slotID, field: field)
    if keypad != target {
      keypadBuffer = Self.buffer(for: slot.draft, field: field, unit: unit)
    }
    keypadBuffer.replaceOnFirstEntry = !keypadBuffer.isEmpty
    keypad = target
    shownKeypad = target
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
    guard let target = keypad,
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
    keypad = nil
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
    return "\(exercise.exerciseName) · \(set)"
  }

  private var keypadSheet: some View {
    let target = keypad ?? shownKeypad
    let field = target?.field ?? .weight
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
          onDone: { keypad = nil },
          onNext: field == .weight ? { advanceToReps() } : nil,
          onLog: field == .reps ? { logFromKeypad() } : nil,
          canLog: targetedSlot?.draft.isLoggable ?? false
        )
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
    .background(Tokens.Color.surface)
    // A fresh keypad scrolls its row clear of itself, by the least amount, and only if the row
    // would be covered. Retargeting does not scroll: a row tapped while the keypad is up was
    // already in view.
    .onAppear {
      if let target {
        scrollRequest = ScrollRequest(target: .view(target.slotID), anchor: nil)
      }
    }
    .presentationDetents([.height(padHeight)])
    .presentationBackground(Tokens.Color.surface)
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

  static func setCount(_ count: Int, adjective: String) -> String {
    count == 1 ? "1 \(adjective) set" : "\(count) \(adjective) sets"
  }
}

/// The set and field the session's keypad is on.
private struct KeypadTarget: Hashable {
  let exerciseID: UUID
  let slotID: UUID
  let field: SetRowField
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
