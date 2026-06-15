import Foundation

public enum OrphanScanner {
  // System/vendor-owned stems that must survive even when their app isn't installed, so leftover
  // data isn't flagged the moment they're uninstalled (dynamic SystemInventory tokens cover the rest).
  private static let keepPrefixes: [String] = [
    "com.apple.", "com.crashlytics", "group.com.apple.", "Apple", "CrashReporter",
    "CloudKit", "MobileSync", "Mobile Documents", "iTunes", "iCloud", "Music", "TV",
    "Safari", "FaceTime", "Knowledge", "Mail", "Messages", "Calendar", "Contacts",
    "Reminders", "Notes", "Photos", "PhotoBooth", "Maps", "News", "Stocks",
    "Voice Memos", "QuickLook", "Spotlight", "Assistant", "Siri", "FileProvider",
    "PreferencePanes", "CallHistory", "DifferentialPrivacy", "ByHost",
    "AddressBook", "HomeKit", "Biome", "ContainerManager", "icdd",
    "livefsd", "BTServer", "ProApps", "iLifeMediaBrowser", "DiagnosticReports",
    "MCXTools", "Desktop Pictures", "ColorSync", "SystemConfiguration", "Audio",
    "OpenDirectory", "Logging", "Xsan", "DirectoryService", "org.cups", "Mozilla",
    "Adobe", "Microsoft", "Logic", "JetBrains", "Slack", "Spotify", "Zoom",
  ]

  // Persistent app-data roots only. Caches/Logs are owned by GenericCacheScanner, so listing
  // them here too would emit each throwaway dir twice under conflicting category/risk.
  private static let libDirs = [
    "Library/Application Support",
    "Library/Preferences",
    "Library/Containers",
    "Library/Group Containers",
    "Library/Saved Application State",
    "Library/HTTPStorages",
    "Library/WebKit",
    "Library/Application Scripts",
  ]

  // LaunchAgent/Daemon directories to probe for active labels (file-based only).
  private static func launchPlistDirs(home: URL) -> [URL] {
    [
      home.appending(path: "Library/LaunchAgents"),
      URL(fileURLWithPath: "/Library/LaunchAgents"),
      URL(fileURLWithPath: "/Library/LaunchDaemons"),
    ]
  }

  /// Vendor/system-owned stems must never become orphan candidates.
  private static func isKeep(_ stem: String) -> Bool {
    let lc = stem.lowercased()
    return keepPrefixes.contains { lc.hasPrefix($0.lowercased()) }
  }

  /// Tiered (exact, dot-component, long-token substring) so partial bundle-id
  /// overlaps still attribute an entry to an installed app instead of flagging it.
  private static func knownMatch(_ stemLC: String, _ known: Set<String>) -> Bool {
    if known.contains(stemLC) { return true }
    let parts = stemLC.components(separatedBy: ".")
    for part in parts where !part.isEmpty {
      if known.contains(part) { return true }
    }
    // Short tokens substring-match too promiscuously to be safe.
    for token in known where token.count >= 6 {
      if stemLC.contains(token) { return true }
    }
    return false
  }

  /// File-based label harvest — no launchctl call, so no elevated privileges needed.
  private static func activeLaunchdLabels(home: URL) -> Set<String> {
    let fm = FileManager.default
    var labels = Set<String>()
    for dir in launchPlistDirs(home: home) {
      guard let entries = try? fm.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
      ) else { continue }
      for plist in entries where plist.pathExtension == "plist" {
        // Filename sans extension is itself a valid label reference.
        labels.insert(plist.deletingPathExtension().lastPathComponent.lowercased())
        if let dict = NSDictionary(contentsOf: plist),
           let label = dict["Label"] as? String {
          labels.insert(label.lowercased())
        }
      }
    }
    return labels
  }

  /// Scans home Library subdirs for entries not attributable to any installed app.
  public static func scan(home: URL, known: Set<String>,
                          diagnostics: ScanDiagnostics? = nil) -> [Candidate] {
    let fm = FileManager.default
    let launchdLabels = activeLaunchdLabels(home: home)
    var out: [Candidate] = []

    let isContainer: (URL) -> Bool = { url in
      let p = url.deletingLastPathComponent().path
      return p.hasSuffix("Library/Containers")
        || p.hasSuffix("Library/Group Containers")
    }

    for rel in libDirs {
      let root = home.appending(path: rel)
      guard let entries = try? fm.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: [.isSymbolicLinkKey],
        options: []
      ) else {
        diagnostics?.recordFailure(root)
        continue
      }

      for url in entries {
        let name = url.lastPathComponent

        // Hidden entries are metadata, never orphaned app data.
        guard !name.hasPrefix(".") else { continue }

        // Skip symlinks so a flagged entry can't point outside the scanned root.
        if let res = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
           res.isSymbolicLink == true { continue }

        // Preferences are keyed by bundle id; the .plist suffix isn't part of it.
        let stem = name.hasSuffix(".plist") ? String(name.dropLast(6)) : name

        guard !isKeep(stem) else { continue }
        guard !knownMatch(stem.lowercased(), known) else { continue }

        // Demote Containers / Group Containers still referenced by a launchd label.
        if isContainer(url) {
          let idLC = stem.lowercased()
          let stripped = idLC.hasPrefix("group.") ? String(idLC.dropFirst(6)) : idLC
          if launchdLabels.contains(idLC) || launchdLabels.contains(stripped) { continue }
        }

        out.append(Candidate(
          ruleID: "orphan.\(name)",
          app: name,
          category: "libraryOrphans",
          // Persistent app data, not cache: heuristic orphans must never be one default click from the Trash.
          risk: .rebuildable,
          why: "Possible leftover — owning app not found.",
          url: url
        ))
      }
    }

    return out.sortedByPath()
  }
}
