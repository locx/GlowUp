import Foundation

public enum WorkspaceStorageScanner {
  // VSCode workspaceStorage entries whose referenced folder no longer exists.
  public static func scan(home: URL) -> [Candidate] {
    let fm = FileManager.default
    let storage = BaseRoot.appSupport.url(home: home)
      .appending(path: "Code/User/workspaceStorage")
    guard let ids = try? fm.contentsOfDirectory(atPath: storage.path) else { return [] }

    var out: [Candidate] = []
    for id in ids where !id.hasPrefix(".") {
      let dir = storage.appending(path: id)
      let meta = dir.appending(path: "workspace.json")
      guard let data = try? Data(contentsOf: meta),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let folder = obj["folder"] as? String,
            let folderURL = URL(string: folder), folderURL.isFileURL
      else { continue }
      if !fm.fileExists(atPath: folderURL.path), !DenyList.vetoes(dir, home: home) {
        out.append(Candidate(ruleID: "workspace.\(id)", app: "Visual Studio Code",
                             category: "workspaceOrphans", risk: .rebuildable,
                             why: "Workspace folder no longer exists.", url: dir))
      }
    }
    return out.sorted { $0.url.path < $1.url.path }
  }
}
