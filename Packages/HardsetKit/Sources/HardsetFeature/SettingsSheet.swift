import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// The app's settings, currently one decision that genuinely cannot be inferred reliably.
///
/// Kept deliberately small. Anything the app can work out from behaviour — which gym, which
/// machine, how many sets a movement usually gets — is learned rather than asked, so it does not
/// belong here. The unit is different: it is a display preference with no behavioural signal, and
/// getting it wrong makes every number on screen wrong.
@MainActor
public struct SettingsSheet: View {
  @Binding private var useImperial: Bool
  @Binding private var restSeconds: Int
  @Binding private var tracksRPE: Bool
  /// `nil` hides the bodyweight row entirely, the same rule the rest of the app follows: an
  /// affordance that opens a screen with no store behind it is worse than no affordance.
  private let bodyweight: BodyweightStore?
  private let unit: WeightUnit
  /// Produces the CSV a lifter takes their history away in. `nil` hides the row, the same rule
  /// the bodyweight row follows.
  private let export: ExportStore?
  /// Deletes every user-created row locally and through CloudKit tombstones.
  private let dataDeletion: DataDeletionStore?
  /// Gyms and their machines, for the equipment library. `nil` hides the row, same rule again.
  private let gyms: GymStore?
  /// Where the public privacy policy, terms and support pages live. The bundled privacy policy is
  /// always present; optional web/legal rows render only when their real URLs are configured.
  private let links: LegalLinks
  /// Whether AlarmKit has refused permission to alert.
  ///
  /// Shown here because this is where the promise is made: the footer below says the timer keeps
  /// running if you leave the app, and without permission it cannot alert at all.
  private let restAlertsDenied: Bool
  /// False during a workout. Deleting rows under a live `SessionCoordinator` would leave it
  /// holding references to a workout that no longer exists.
  private let canDeleteData: Bool
  /// Resets non-database state, including the active AlarmKit alarm and AppStorage preferences.
  private let onDataDeleted: () -> Void
  private let onDone: () -> Void

  /// Rest options the user can pick from. **Off is first and is the default**, because the app has
  /// no basis for prescribing a rest length: the literature does not give one, and inventing 90
  /// seconds would be exactly the kind of unearned prescription this app refuses elsewhere. What it
  /// can do is honour a choice the lifter makes, which is a different thing from making it for them.
  static let restOptions: [Int] = [0, 60, 90, 120, 180, 240]

  public init(
    useImperial: Binding<Bool>,
    restSeconds: Binding<Int>,
    tracksRPE: Binding<Bool>,
    bodyweight: BodyweightStore? = nil,
    export: ExportStore? = nil,
    dataDeletion: DataDeletionStore? = nil,
    gyms: GymStore? = nil,
    links: LegalLinks = .live,
    unit: WeightUnit = .kilograms,
    restAlertsDenied: Bool = false,
    canDeleteData: Bool = true,
    onDataDeleted: @escaping () -> Void = {},
    onDone: @escaping () -> Void
  ) {
    self._useImperial = useImperial
    self._restSeconds = restSeconds
    self._tracksRPE = tracksRPE
    self.bodyweight = bodyweight
    self.export = export
    self.dataDeletion = dataDeletion
    self.gyms = gyms
    self.links = links
    self.unit = unit
    self.restAlertsDenied = restAlertsDenied
    self.canDeleteData = canDeleteData
    self.onDataDeleted = onDataDeleted
    self.onDone = onDone
  }

  /// `URL` is not `Identifiable`, and `sheet(item:)` needs it to be. Wrapped rather than made so
  /// by an extension on `URL`: conforming a Foundation type app-wide to satisfy one sheet is how
  /// two modules end up disagreeing about what a URL's identity is.
  private struct ExportedFile: Identifiable {
    let url: URL
    var id: String { url.path }
  }

  /// The CSV, written when the sheet opens so the row can be a real `ShareLink`.
  ///
  /// A file rather than a string, because sharing a string offers "Copy" and "Message" but not
  /// "Save to Files" — and saving it is the entire point.
  ///
  /// Prepared up front rather than on tap, because `ShareLink` needs its item at init. The
  /// alternative — a button that writes the file and then presents a sheet — was tried and is
  /// worse twice over: nested inside the Section the sheet dismissed Settings instead of
  /// presenting, and once hoisted it presented a sheet containing a single "Share…" link rather
  /// than the system share sheet. A `ShareLink` in the row is one tap and the real thing.
  @State private var exportedFile: ExportedFile?
  @State private var exportFailed = false
  /// How many sets an export would contain, read **once** when the sheet appears.
  ///
  /// Hoisted out of `body` deliberately. It was `try? export.loggedSetCount()` inline in the
  /// section, which is a `COUNT(*)` over `loggedSets` on every body evaluation -- so flipping the
  /// RPE toggle re-queried the whole table. Settings is not the logger, but it is the same mistake
  /// invariant #3 exists to forbid, and the fix is the same one: read it once into a value.
  ///
  /// `nil` means not yet read, which renders as absence rather than as zero.
  @State private var exportableSetCount: Int?
  @State private var confirmsDataDeletion = false
  @State private var isDeletingData = false
  @State private var dataDeletionFailed = false
  @State private var didDeleteData = false

  @ViewBuilder private var exportSection: some View {
    if export != nil, (exportableSetCount ?? 0) > 0 || exportFailed {
      Section {
        if let file = exportedFile, let count = exportableSetCount {
          // Pluralised by hand rather than with `^[...](inflect:)`. The markup is only interpreted
          // when it reaches a `LocalizedStringKey`, and this app has shipped it verbatim on screen
          // twice already by routing one through a `String` first. Not worth the risk on a label
          // nobody can see until they open this sheet.
          ShareLink(item: file.url) {
            Label(
              "Export \(count) set\(count == 1 ? "" : "s") as CSV",
              systemImage: "square.and.arrow.up"
            )
          }
        } else if !exportFailed {
          // The file is still being written. Stated rather than shown as a live control that does
          // nothing yet.
          Label("Preparing export…", systemImage: "square.and.arrow.up")
            .foregroundStyle(Tokens.Color.textSecondary)
        }
        if exportFailed {
          // Stated, not swallowed. An export that silently does nothing reads as data loss to the
          // one person most worried about it -- and a row that simply vanishes on a failed read is
          // the same lie told more quietly.
          Text("Your history could not be prepared for export. Close Settings and try again.")
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.certainty(.low))
        }
      } header: {
        Text("Your data")
      } footer: {
        Text(
          "One row per logged set, in kilograms — the unit everything is stored in, so the file "
            + "does not carry a conversion. Nothing is derived: no estimated maxes, no weekly "
            + "totals. Those are worked out from these rows, and the rows are what you actually did."
        )
      }
    }
  }

  /// Reads the whole log and writes it out once, away from the UI actor. A long training history
  /// can be opened from Settings without making the unit or RPE controls hitch while the CSV is
  /// assembled.
  private func prepareExport(_ export: ExportStore) async {
    let result = await readOffMain {
      let count = try export.loggedSetCount()
      guard count > 0 else { return (count, URL?.none) }
      let csv = try export.workoutCSV()
      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(ExportStore.filename(on: Date()))
      try csv.write(to: url, atomically: true, encoding: .utf8)
      return (count, URL?.some(url))
    }
    if Task.isCancelled {
      if case .success((_, let url)) = result, let url {
        try? FileManager.default.removeItem(at: url)
      }
      return
    }
    switch result {
    case .success(let prepared):
      exportableSetCount = prepared.0
      exportedFile = prepared.1.map(ExportedFile.init(url:))
      exportFailed = false
    case .failure:
      exportFailed = true
    }
  }

  @ViewBuilder private var dataDeletionSection: some View {
    if let dataDeletion {
      Section {
        Button(role: .destructive) {
          confirmsDataDeletion = true
        } label: {
          if isDeletingData {
            Label("Deleting…", systemImage: "trash")
          } else {
            Label("Delete all Hardset data", systemImage: "trash")
          }
        }
        .disabled(!canDeleteData || isDeletingData)

        if didDeleteData {
          Label("All Hardset data was deleted", systemImage: "checkmark.circle")
            .foregroundStyle(Tokens.Color.textSecondary)
        } else if dataDeletionFailed {
          Text("Hardset could not delete your data. Nothing was partially reset; try again.")
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.certainty(.low))
        }
      } header: {
        Text("Delete data")
      } footer: {
        Text(
          canDeleteData
            ? "Permanently removes workouts, plans, gyms, custom exercises, bodyweight, and "
              + "preferences. Synchronized records are also deleted from your private iCloud "
              + "database when sync is available. Export first if you want a copy."
            : "Finish or delete the workout in progress before deleting all data."
        )
      }
      .alert("Delete all Hardset data?", isPresented: $confirmsDataDeletion) {
        Button("Cancel", role: .cancel) {}
        Button("Delete Everything", role: .destructive) {
          deleteAllData(using: dataDeletion)
        }
      } message: {
        Text(
          "This cannot be undone. It deletes every workout, plan, gym, custom exercise, "
            + "bodyweight reading, and preference from this device and queues deletion from "
            + "your private iCloud database."
        )
      }
    }
  }

  private func deleteAllData(using store: DataDeletionStore) {
    isDeletingData = true
    dataDeletionFailed = false
    didDeleteData = false
    Task {
      let result = await Task.detached(priority: .userInitiated) {
        Result { try store.deleteAllUserData() }
      }.value
      isDeletingData = false
      switch result {
      case .success:
        deletePreparedExport()
        exportableSetCount = 0
        exportFailed = false
        didDeleteData = true
        onDataDeleted()
      case .failure:
        dataDeletionFailed = true
      }
    }
  }

  /// Removes the private temporary copy created for `ShareLink`. A file the user already copied
  /// to Files or another app belongs to that destination and is intentionally outside our reach.
  private func deletePreparedExport() {
    guard let url = exportedFile?.url else { return }
    try? FileManager.default.removeItem(at: url)
    exportedFile = nil
  }

  /// The machine library.
  ///
  /// Deliberately phrased as review rather than setup. Equipment is learned by naming it at the
  /// rack, because the ancestor app's setup screen went uncompleted and every set after it was
  /// logged against nothing -- so this row must not read as a step anyone has to take.
  @ViewBuilder private var equipmentSection: some View {
    if let gyms {
      Section {
        NavigationLink {
          MachineLibraryScreen(gyms: gyms, unit: unit)
            .navigationTitle("Machines")
        } label: {
          Label("Machines", systemImage: "dumbbell")
        }
      } header: {
        Text("Equipment")
      } footer: {
        Text(
          "What you have named while logging. Fix a name, set a stack step, or put one away "
            + "\u{2014} nothing here needs filling in first."
        )
      }
    }
  }

  @ViewBuilder private var aboutSection: some View {
    Section {
      NavigationLink {
        MethodologyIndexScreen()
      } label: {
        Label("How the numbers work", systemImage: "function")
      }
      // Always present and readable offline. The public URL, once configured, appears inside.
      NavigationLink {
        PrivacyPolicyScreen(onlineURL: links.privacyPolicy)
      } label: {
        Label("Privacy policy", systemImage: "hand.raised")
      }
      if let url = links.termsOfUse {
        Link(destination: url) { Label("Terms of use", systemImage: "doc.text") }
      }
      if let url = links.support {
        Link(destination: url) { Label("Support", systemImage: "questionmark.circle") }
      }
      if let version = AppVersion.current() {
        LabeledContent("Version", value: version.displayString)
          .foregroundStyle(Tokens.Color.textSecondary)
      }
    } header: {
      Text("About")
    }
  }

  static func restLabel(_ seconds: Int) -> String {
    switch seconds {
    case 0: "Off"
    case ..<60: "\(seconds)s"
    default:
      seconds % 60 == 0
        ? "\(seconds / 60) min"
        : "\(seconds / 60) min \(seconds % 60)s"
    }
  }

  private var unitPicker: some View {
    HStack(spacing: Tokens.Spacing.hairline) {
      unitButton(label: WeightUnit.kilograms.abbreviation, selectsImperial: false)
      unitButton(label: WeightUnit.pounds.abbreviation, selectsImperial: true)
    }
    .padding(Tokens.Spacing.hairline)
    .background(
      Tokens.Color.raised,
      in: RoundedRectangle(cornerRadius: Tokens.Radius.control)
    )
    .accessibilityElement(children: .contain)
  }

  private func unitButton(label: String, selectsImperial: Bool) -> some View {
    let selected = useImperial == selectsImperial
    return Button {
      useImperial = selectsImperial
    } label: {
      Text(label)
        .font(Tokens.Text.label)
        .foregroundStyle(selected ? Tokens.Color.ground : Tokens.Color.textPrimary)
        .frame(maxWidth: .infinity, minHeight: Tokens.minimumTapTarget)
        .background(
          selected ? Tokens.Color.accent : Tokens.Color.raised,
          in: RoundedRectangle(cornerRadius: Tokens.Radius.control)
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(selectsImperial ? "Pounds" : "Kilograms")
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  public var body: some View {
    NavigationStack {
      Form {
        Section {
          unitPicker
        } header: {
          Text("Units")
        } footer: {
          // Stated because it is the reason switching never corrupts anything, and because a
          // lifter who has logged in one unit deserves to know the other view is a conversion,
          // not a re-entry.
          Text(
            "Every set is stored in kilograms, whichever you pick. Switching converts what you "
              + "see and changes nothing that was recorded."
          )
        }

        Section {
          Picker("After a working set", selection: $restSeconds) {
            ForEach(Self.restOptions, id: \.self) { seconds in
              Text(Self.restLabel(seconds)).tag(seconds)
            }
          }
        } header: {
          Text("Rest timer")
        } footer: {
          // Says what it does and, more importantly, what it does not decide.
          Text(
            restSeconds == 0
              ? "No timer starts when you log a set. The app does not prescribe a rest length \u{2014} "
                + "pick one and it will hold you to it."
              : "A timer starts when you log a working set, never after a warm-up. It keeps "
                + "running if you leave the app or force-quit it."
          )
          if restSeconds != 0, restAlertsDenied {
            // The claim directly above this is false without permission, so it is corrected in
            // place rather than left standing.
            Text(
              "Hardset cannot alert you: alarm permission was declined. The countdown still runs "
                + "on screen, but nothing will sound when it ends. You can allow alarms for "
                + "Hardset in the Settings app."
            )
            .foregroundStyle(Tokens.Color.certainty(.low))
          }
        }

        Section {
          Toggle("Record RPE", isOn: $tracksRPE)
        } header: {
          Text("Effort")
        } footer: {
          // Says what it does and, as everywhere else, what it refuses to do.
          Text(
            "Adds an optional effort field to every set, on the 1\u{2013}10 scale. Off by default, "
              + "because a field nobody fills is clutter in the one place this app cannot afford "
              + "it. The app records what you enter and nothing more \u{2014} there is no target "
              + "RPE and no warning for being far from failure, because neither is established."
          )
        }
        if let bodyweight {
          Section {
            NavigationLink {
              BodyweightScreen(store: bodyweight, unit: unit)
                .navigationTitle("Bodyweight")
            } label: {
              Label("Bodyweight", systemImage: "scalemass")
            }
          } header: {
            Text("You")
              .font(Tokens.Text.caption)
              .foregroundStyle(Tokens.Color.textSecondary)
          } footer: {
            // The two things a lifter needs before typing a weight in: what it is used for, and
            // where it goes.
            Text(
              "Kept on this device and never uploaded. Shown as a "
                + "\(BodyweightTrend.smoothingDays)-day average, because a single morning is "
                + "mostly food and water."
            )
          }
        }

        equipmentSection
        exportSection
        dataDeletionSection
        aboutSection
      }
      .task {
        guard let export else { return }
        await prepareExport(export)
      }
      .navigationTitle("Settings")
      .onDisappear { deletePreparedExport() }
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done", action: onDone)
        }
      }
    }
  }
}

#if DEBUG
  private struct SettingsHarness: View {
    @State private var useImperial = true
    @State private var restSeconds = 90
    @State private var tracksRPE = true
    var body: some View {
      SettingsSheet(
        useImperial: $useImperial, restSeconds: $restSeconds, tracksRPE: $tracksRPE
      ) {}
    }
  }

  #Preview("Settings") { SettingsHarness() }
#endif
