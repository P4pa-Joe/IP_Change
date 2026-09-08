import Foundation

/// Loads, saves, and manages `NetworkProfile` persistence as JSON under
/// `~/Library/Application Support/IPChange/profiles.json`.
final class ProfileStore {

    static let shared = ProfileStore()

    private(set) var profiles: [NetworkProfile] = []

    private let fileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = appSupport.appendingPathComponent("IPChange", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("profiles.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([NetworkProfile].self, from: data) else {
            profiles = []
            return
        }
        profiles = decoded
    }

    @discardableResult
    func save() -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(profiles) else { return false }
        return (try? data.write(to: fileURL, options: .atomic)) != nil
    }

    func addOrUpdate(_ profile: NetworkProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        save()
    }

    func delete(_ profile: NetworkProfile) {
        profiles.removeAll { $0.id == profile.id }
        save()
    }

    func exportProfiles(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(profiles)
        try data.write(to: url, options: .atomic)
    }

    /// Imports profiles from a JSON file, merging them into the current
    /// list. Profiles whose id already exists are overwritten in place;
    /// new ids are appended.
    func importProfiles(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let imported = try JSONDecoder().decode([NetworkProfile].self, from: data)
        for profile in imported {
            addOrUpdate(profile)
        }
    }
}
