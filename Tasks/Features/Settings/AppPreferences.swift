import Foundation
import ImageIO
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class AppPreferences {
    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: Self { self }
        var titleKey: String {
            switch self {
            case .system: "Seguir sistema"
            case .light: "Claro"
            case .dark: "Escuro"
            }
        }
        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: "settings.appearance") }
    }
    var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: AppLanguage.defaultsKey) }
    }
    var displayName: String {
        didSet { defaults.set(displayName, forKey: "profile.displayName") }
    }
    private(set) var avatarData: Data?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let avatarURL: URL?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = Appearance(rawValue: defaults.string(forKey: "settings.appearance") ?? "") ?? .system
        language = AppLanguage(rawValue: defaults.string(forKey: AppLanguage.defaultsKey) ?? "") ?? .system
        displayName = defaults.string(forKey: "profile.displayName") ?? ""
        avatarURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Profile", isDirectory: true).appendingPathComponent("avatar.png")
        avatarData = avatarURL.flatMap { try? Data(contentsOf: $0) }
    }

    func setAvatar(_ data: Data) throws {
        guard let avatarURL,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 512
              ] as CFDictionary),
              let normalized = UIImage(cgImage: image).pngData() else { throw AvatarError.invalidImage }
        try FileManager.default.createDirectory(at: avatarURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try normalized.write(to: avatarURL, options: .atomic)
        avatarData = normalized
    }

    func removeAvatar() throws {
        if let avatarURL, FileManager.default.fileExists(atPath: avatarURL.path) {
            try FileManager.default.removeItem(at: avatarURL)
        }
        avatarData = nil
    }

    private enum AvatarError: Error { case invalidImage }
}
