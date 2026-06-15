import Foundation

public enum WorkspaceStorageScanner {
  // VSCode workspaceStorage entries whose referenced folder no longer exists.
  public static func scan(home: URL, diagnostics: ScanDiagnostics? = nil) -> [Candidate] {
    let fm = FileManager.default
    let storage = BaseRoot.appSupport.url(home: home)
      .appending(path: "Code/User/workspaceStorage")
    guard let ids = try? fm.contentsOfDirectory(atPath: storage.path) else {
      diagnostics?.recordFailure(storage)
      return []
    }

    var out: [Candidate] = []
    for id in ids where !id.hasPrefix(".") {
      let dir = storage.appending(path: id)
      let meta = dir.appending(path: "workspace.json")
      guard let data = try? Data(contentsOf: meta),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let folder = obj["folder"] as? String
      else { continue }
      // Older builds wrote raw POSIX paths, newer ones file:// URIs. Remote URIs stay
      // skipped — a remote workspace's absence can't be verified from this machine.
      let folderPath: String
      if folder.hasPrefix("/") {
        folderPath = folder
      } else if let folderURL = URL(string: folder), folderURL.isFileURL {
        folderPath = folderURL.path
      } else { continue }
      if !fm.fileExists(atPath: folderPath) {
        // Workspace storage holds extension state, not cache — keep it out of the default one-click set.
        out.append(Candidate(ruleID: "workspace.\(id)", app: "Visual Studio Code",
                             category: "workspaceOrphans", risk: .rebuildable,
                             why: "Workspace folder no longer exists.", url: dir))
      }
    }
    return out.sortedByPath()
  }
}
