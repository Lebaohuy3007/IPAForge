import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct DeviceProfileView: View {
    @EnvironmentObject private var store: DeviceProfileStore
    @State private var draft = DeviceProfile.defaultProfile
    @State private var capabilityInventoryKnown = false
    @State private var architectureInventoryKnown = false
    @State private var saveMessage: String?
    @State private var isShowingIPAImporter = false
    @State private var isInspectingIPA = false
    @State private var inspection: IPAInspection?
    @State private var inspectionError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Runtime", value: runtimeTitle)
                    LabeledContent("Model reported by iOS", value: UIDevice.current.model)
                    LabeledContent("OS version", value: UIDevice.current.systemVersion)
                } header: {
                    Text("This device")
                } footer: {
                    Text("These are values from the device running IPAForge. They are separate from the compatibility profile below.")
                }

                Section {
                    Picker("Profile", selection: Binding(
                        get: { store.selectedProfileID },
                        set: { profileID in
                            store.select(profileID: profileID)
                            loadSelectedProfile()
                        }
                    )) {
                        ForEach(store.profiles) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }

                    TextField("Profile name", text: $draft.name)

                    Picker("Device model", selection: Binding(
                        get: { draft.model },
                        set: selectModel
                    )) {
                        ForEach(modelOptions, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }

                    Picker("Device family", selection: Binding(
                        get: { draft.family },
                        set: selectFamily
                    )) {
                        ForEach(DeviceProfileFamily.allCases) { family in
                            Text(family.title).tag(family)
                        }
                    }

                    TextField("iOS version", text: $draft.osVersion)
                        .keyboardType(.decimalPad)

                    Toggle("Capability inventory is verified", isOn: $capabilityInventoryKnown)
                        .onChange(of: capabilityInventoryKnown) { known in
                            draft.availableCapabilities = known ? (draft.availableCapabilities ?? []) : nil
                        }
                    if capabilityInventoryKnown {
                        TextField("Capabilities, comma-separated", text: capabilitiesText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    Toggle("Architectures are verified", isOn: $architectureInventoryKnown)
                        .onChange(of: architectureInventoryKnown) { known in
                            draft.supportedArchitectures = known ? (draft.supportedArchitectures ?? []) : nil
                        }
                    if architectureInventoryKnown {
                        TextField("Architectures, e.g. arm64 or arm64e.x1", text: architecturesText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    HStack {
                        Label("SIMULATED DEVICE PROFILE", systemImage: "iphone.gen3")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                        Spacer()
                        Text("iOS \(draft.osVersion)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    Text("This profile is only input to compatibility checks. It does not create an Xcode Simulator, change the real device, or provide an Apple Device Identity.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let validationError = draft.validationError() {
                        Text(validationError.localizedDescription)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    } else if let saveMessage {
                        Text(saveMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Button("Add profile") {
                            draft = store.createProfile()
                            loadInventoryFlags()
                            saveMessage = nil
                        }
                        Button("Save profile") { saveProfile() }
                            .disabled(draft.validationError() != nil)
                        if store.profiles.count > 1 {
                            Button("Delete", role: .destructive) { deleteSelectedProfile() }
                        }
                    }
                } header: {
                    Text("Compatibility profile")
                } footer: {
                    Text("Manually entered capabilities and architectures remain Unknown because this app cannot verify a simulated profile's hardware.")
                }

                Section {
                    Button {
                        isShowingIPAImporter = true
                    } label: {
                        Label("Choose IPA file", systemImage: "doc.zipper")
                    }
                    .disabled(isInspectingIPA)

                    if isInspectingIPA {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Checking archive integrity and app metadata…")
                        }
                    }

                    if let inspectionError {
                        Text(inspectionError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if let inspection {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("Bundle ID", value: inspection.bundleIdentifier)
                            LabeledContent("Version", value: inspection.version ?? "Unknown")
                            LabeledContent("Build", value: inspection.buildNumber ?? "Unknown")
                            LabeledContent("Minimum iOS", value: inspection.minimumOSVersion ?? "Unknown")
                            LabeledContent("IPA size", value: ByteCountFormatter.string(fromByteCount: inspection.fileSizeBytes, countStyle: .file))
                            CompatibilityReportView(report: CompatibilityChecker().evaluate(
                                requirements: inspection.compatibilityRequirements,
                                profile: store.selectedProfile
                            ), minimumOSVersion: inspection.minimumOSVersion)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Check an IPA")
                } footer: {
                    Text("The checker reads the IPA Info.plist, executable architecture, and ZIP CRCs. It does not install or decrypt the app.")
                }
            }
            .navigationTitle("Device Profile")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { loadSelectedProfile() }
            .onChange(of: store.selectedProfileID) { _ in loadSelectedProfile() }
            .fileImporter(
                isPresented: $isShowingIPAImporter,
                allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .zip],
                allowsMultipleSelection: false,
                onCompletion: inspectSelectedFile
            )
        }
    }

    private var runtimeTitle: String {
        #if targetEnvironment(simulator)
        return "Xcode Simulator"
        #else
        return "Physical device"
        #endif
    }

    private var modelOptions: [String] {
        let options = DeviceProfile.modelOptions(for: draft.family)
        return options.contains(draft.model) ? options : [draft.model] + options
    }

    private var capabilitiesText: Binding<String> {
        Binding(
            get: { draft.availableCapabilities?.sorted().joined(separator: ", ") ?? "" },
            set: { draft.availableCapabilities = Set(parseList($0)) }
        )
    }

    private var architecturesText: Binding<String> {
        Binding(
            get: { draft.supportedArchitectures?.sorted().joined(separator: ", ") ?? "" },
            set: { draft.supportedArchitectures = Set(parseList($0).map { $0.lowercased() }) }
        )
    }

    private func parseList(_ value: String) -> [String] {
        value.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func loadSelectedProfile() {
        draft = store.selectedProfile
        loadInventoryFlags()
        saveMessage = nil
    }

    private func loadInventoryFlags() {
        capabilityInventoryKnown = draft.availableCapabilities != nil
        architectureInventoryKnown = draft.supportedArchitectures != nil
    }

    private func selectModel(_ model: String) {
        guard draft.model != model else { return }
        draft.model = model
        clearHardwareInventory()
    }

    private func selectFamily(_ family: DeviceProfileFamily) {
        guard draft.family != family else { return }
        draft.family = family
        let options = DeviceProfile.modelOptions(for: family)
        if !options.contains(draft.model) {
            draft.model = options[0]
        }
        clearHardwareInventory()
    }

    private func clearHardwareInventory() {
        capabilityInventoryKnown = false
        architectureInventoryKnown = false
        draft.availableCapabilities = nil
        draft.supportedArchitectures = nil
    }

    private func saveProfile() {
        do {
            try store.save(draft)
            saveMessage = "Profile saved on this device."
            inspectionError = nil
        } catch {
            saveMessage = error.localizedDescription
        }
    }

    private func deleteSelectedProfile() {
        store.delete(profileID: draft.id)
        loadSelectedProfile()
    }

    private func inspectSelectedFile(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            inspectionError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            isInspectingIPA = true
            inspectionError = nil
            inspection = nil
            Task {
                let hasScopedAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if hasScopedAccess { url.stopAccessingSecurityScopedResource() }
                }
                do {
                    let result = try await Task.detached(priority: .userInitiated) {
                        try IPAInspector().inspect(url)
                    }.value
                    inspection = result
                } catch {
                    inspectionError = error.localizedDescription
                }
                isInspectingIPA = false
            }
        }
    }
}

struct CompatibilityReportView: View {
    let report: CompatibilityReport
    var minimumOSVersion: String? = nil

    private var minimumOSFinding: CompatibilityFinding? {
        report.findings.first { $0.criterion == .minimumOS }
    }

    private var status: CompatibilityStatus {
        minimumOSFinding?.status ?? .unknown
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "\(report.model) • iOS \(report.osVersion)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color(for: status))

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: symbol(for: status))
                    .foregroundStyle(color(for: status))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Minimum OS")
                        .font(.caption.weight(.semibold))
                    minimumOSDescription
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("This simulated profile checks only Minimum OS. It does not verify real-device compatibility or enable IPA downloads.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var minimumOSDescription: some View {
        if let minimumOSVersion,
           let requiredVersion = SemanticOSVersion(minimumOSVersion),
           let profileVersion = SemanticOSVersion(report.osVersion) {
            if profileVersion >= requiredVersion {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Minimum OS requirement is met.")
                    requiredVersionLabel(minimumOSVersion)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Minimum OS requirement is not met.")
                    requiredVersionLabel(minimumOSVersion)
                }
            }
        } else {
            Text("Minimum iOS version is unavailable.")
        }
    }

    private func requiredVersionLabel(_ version: String) -> some View {
        HStack(spacing: 4) {
            Text("Required iOS version:")
            Text(verbatim: version)
        }
        .foregroundStyle(.secondary)
    }

    private func color(for status: CompatibilityStatus) -> Color {
        switch status {
        case .compatible: return .green
        case .incompatible: return .red
        case .unknown: return .orange
        }
    }

    private func symbol(for status: CompatibilityStatus) -> String {
        switch status {
        case .compatible: return "checkmark.circle.fill"
        case .incompatible: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}
