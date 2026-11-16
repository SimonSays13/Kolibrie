import SwiftUI

enum AppInfo {
    static let name = "Kolibrie"
    static let version = "0.1.0 (development)"
    static let colibriRepository = URL(string: "https://github.com/JustVugg/colibri")!
    static let apacheLicence = URL(string: "https://www.apache.org/licenses/LICENSE-2.0")!
}

/// Branding images bundled with the app.
enum Branding {
    static func image(named name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Resources")
        else { return nil }
        return NSImage(contentsOf: url)
    }

    /// The logo with wordmark, shown at the top of the About window. Its colours work in light and dark mode.
    static var logo: NSImage? { image(named: "about-logo") }

    /// The app icon, used for the Dock and the application switcher.
    static var icon: NSImage? { image(named: "app-icon") }
}

struct AboutView: View {
    let app: AppModel

    var body: some View {
        VStack(spacing: 14) {
            if let logo = Branding.logo {
                Image(nsImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 80)
                    .accessibilityLabel("Logo")
            } else {
                Image(systemName: "cpu.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
            }
            VStack(spacing: 2) {
                Text("Version \(AppInfo.version)").font(.callout).foregroundStyle(.secondary)
            }
            Text(
                "A native macOS menu bar app for installing, configuring and running Colibri, and for pointing coding tools at its models."
            )
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(spacing: 6) {
                Text("Built for Colibri").font(.headline)
                Text(
                    "Colibri is a C inference engine for very large mixture-of-experts models, created by Vincenzo Fornaro and released under the Apache 2.0 licence."
                )
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                Link("github.com/JustVugg/colibri", destination: AppInfo.colibriRepository)
                if let version = app.colibriVersion {
                    Text("Colibri on this Mac: \(version)").font(.callout).foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(spacing: 4) {
                Text(
                    "Kolibrie is an independent project. It runs Colibri's own launcher and does not include or change Colibri."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    Text("Licensed under the")
                    Link("Apache License 2.0", destination: AppInfo.apacheLicence)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}
