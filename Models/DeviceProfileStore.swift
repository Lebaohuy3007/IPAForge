import Combine
import Foundation

@MainActor
final class DeviceProfileStore: ObservableObject {
    @Published private(set) var profiles: [DeviceProfile]
    @Published private(set) var selectedProfileID: UUID

    private let defaults: UserDefaults
    private let profilesKey = "deviceProfiles.v1"
    private let selectedProfileKey = "selectedDeviceProfile.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: profilesKey),
           let decoded = try? JSONDecoder().decode([DeviceProfile].self, from: data),
           !decoded.isEmpty,
           decoded.allSatisfy({ $0.validationError() == nil }),
           Set(decoded.map(\.id)).count == decoded.count {
            profiles = decoded
        } else {
            profiles = [.defaultProfile]
        }

        let savedID = defaults.string(forKey: selectedProfileKey).flatMap(UUID.init(uuidString:))
        selectedProfileID = savedID.flatMap { id in
            profiles.contains(where: { $0.id == id }) ? id : nil
        } ?? profiles[0].id
        persist()
    }

    var selectedProfile: DeviceProfile {
        profiles.first(where: { $0.id == selectedProfileID }) ?? profiles[0]
    }

    @discardableResult
    func createProfile() -> DeviceProfile {
        let selected = selectedProfile
        let copy = DeviceProfile(
            id: UUID(),
            name: "Device Profile \(profiles.count + 1)",
            model: selected.model,
            family: selected.family,
            osVersion: selected.osVersion,
            availableCapabilities: selected.availableCapabilities,
            supportedArchitectures: selected.supportedArchitectures
        )
        profiles.append(copy)
        selectedProfileID = copy.id
        persist()
        return copy
    }

    func select(profileID: UUID) {
        guard profiles.contains(where: { $0.id == profileID }) else { return }
        selectedProfileID = profileID
        persist()
    }

    func save(_ profile: DeviceProfile) throws {
        if let error = profile.validationError() { throw error }
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
        persist()
    }

    func delete(profileID: UUID) {
        guard profiles.count > 1, profiles.contains(where: { $0.id == profileID }) else { return }
        profiles.removeAll { $0.id == profileID }
        if selectedProfileID == profileID {
            selectedProfileID = profiles[0].id
        }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: profilesKey)
        }
        defaults.set(selectedProfileID.uuidString, forKey: selectedProfileKey)
    }
}
