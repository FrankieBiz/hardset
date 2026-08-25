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
  /// Gyms and their machines, for the equipment library. `nil` hides the row, same rule again.
  private let gyms: GymStore?
  /// Where the privacy policy, terms and support pages live. Rows render only for links that are
  /// actually set — see `LegalLinks`, which explains why nothing here invents one.
  private let links: LegalLinks
  /// Whether AlarmKit has refused permission to alert.
  ///
  /// Shown here because this is where the promise is made: the footer below says the timer keeps
  /// running if you leave the app, and without permission it cannot alert at all.
  private let restAlertsDenied: Bool
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
    gyms: GymStore? = nil,
    links: LegalLinks = .live,
    unit: WeightUnit = .kilograms,
    restAlertsDenied: Bool = false,
    onDone: @escaping () -> Void
  ) {
    self._useImperial = useImperial
    self._restSeconds = restSeconds
    self._tracksRPE = tracksRPE
    self.bodyweight = bodyweight
    self.export = export
    self.gyms = gyms
    self.links = links
    self.unit = unit
    self.restAlertsDenied = restAlertsDenied
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

  /// Reads the whole log and writes it out, once, when the sheet appears.
  ///
  /// Synchronous and on the main actor, matching every other store read in this app -- the
  /// invariant that matters here is "no database work *per render*", not "no database work". This
  /// runs once per opening of Settings. A detached task was tried and rejected by strict
  /// concurrency: `ExportStore` reaches this method already main-actor-isolated, so handing it to
  /// `Task.detached` is a `sending`-closure error rather than a free win.
  ///
  /// Scale check: 450 logged sets produced a 70 KB file, so the read is milliseconds. If a log ever
  /// gets large enough to be felt on opening Settings, the fix is to make `ExportStore` `Sendable`
  /// and move this off the actor -- not to write it lazily, which is what `ShareLink` cannot do.
  private func prepareExport(_ export: ExportStore) {
    do {
      let csv = try export.workoutCSV()
      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(ExportStore.filename(on: Date()))
      try csv.write(to: url, atomically: true, encoding: .utf8)
      exportedFile = ExportedFile(url: url)
      exportFailed = false
    } catch {
      exportFailed = true
    }
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
      // Each renders only if it has somewhere real to go. See `LegalLinks`.
      if let url = links.privacyPolicy {
        Link(destination: url) { Label("Privacy policy", systemImage: "hand.raised") }
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

  public var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("Weight", selection: $useImperial) {
            Text(WeightUnit.kilograms.abbreviation).tag(false)
            Text(WeightUnit.pounds.abbreviation).tag(true)
          }
          .pickerStyle(.segmented)
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
        aboutSection
      }
      .task {
        // One read, on appear. An export offered with no sets behind it would hand over a file
        // containing only a header.
        //
        // Not `try?`. A swallowed failure here removes the export row entirely, which tells the
        // one person most worried about their data that the feature does not exist -- see the
        // standing rule against `try?` inside a view.
        guard let export else { return }
        do {
          let count = try export.loggedSetCount()
          exportableSetCount = count
          if count > 0 { prepareExport(export) }
        } catch {
          exportFailed = true
        }
      }
      .navigationTitle("Settings")
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
