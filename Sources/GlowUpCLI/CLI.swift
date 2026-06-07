import Foundation
import GlowKit

public enum CLI {
  // Renders results to a string + exit code; never prints (so it's testable).
  public static func run(args: [String], catalog: Catalog, inventory: AppInventory,
                         home: URL, mover: ItemMover, storeURL: URL) async -> (String, Int32) {
    let o = CLIOptions.parse(args)

    if o.mode == .projects {
      return ("Project scanning is available in the advanced-scanners build.\n", 2)
    }
    if o.mode == .restore {
      let store = RestoreStore(storeURL: storeURL)
      guard let last = store.batches().first else { return ("Nothing to restore.\n", 0) }
      let r = store.restore(last)
      return ("Restored \(r.restored); \(r.failed.count) could not be restored.\n", 0)
    }

    let tiers: Set<Risk> = o.advanced ? Set(Risk.allCases) : [.safe]
    let candidates = Scanner(catalog: catalog, inventory: inventory)
      .scan(home: home, includeRisks: tiers)
    let sizes = await SizeMeasurer.measure(candidates.map(\.url))
    let total = candidates.reduce(Int64(0)) { $0 + (sizes[$1.url] ?? 0) }

    if o.json {
      return (json(candidates, sizes, total), 0)
    }

    var lines = candidates.map {
      "  \(paint($0.risk, o.noColor)) \(byte(sizes[$0.url] ?? 0))  \($0.url.path)"
    }

    switch o.mode {
    case .clean:
      let result = Trasher(mover: mover).trash(candidates.map(\.url))
      if !result.trashed.isEmpty {
        try? RestoreStore(storeURL: storeURL)
          .record(CleanupBatch(id: UUID().uuidString, date: Date(), items: result.trashed))
      }
      lines.append("Moved \(byte(total)) to the Trash — empty Trash to reclaim.")
      if !result.failures.isEmpty { lines.append("\(result.failures.count) could not be moved.") }
    case .list:
      lines.insert("\(candidates.count) item(s), \(byte(total)):", at: 0)
    default: // dryRun
      lines.insert("Would free \(byte(total)) (dry run — nothing was moved):", at: 0)
    }
    return (lines.joined(separator: "\n") + "\n", 0)
  }

  private static func byte(_ b: Int64) -> String {
    let f = ByteCountFormatter(); f.countStyle = .file
    return f.string(fromByteCount: b)
  }

  private static func paint(_ risk: Risk, _ noColor: Bool) -> String {
    let tag = String(describing: risk)
    if noColor { return "[\(tag)]" }
    let code: Int
    switch risk {
    case .safe:        code = 32
    case .rebuildable: code = 36
    case .stateful:    code = 33
    case .privacy:     code = 35
    }
    return "\u{1B}[\(code)m[\(tag)]\u{1B}[0m"
  }

  private static func json(_ candidates: [Candidate], _ sizes: [URL: Int64], _ total: Int64) -> String {
    struct Item: Encodable { let ruleID, category, risk, path: String; let app: String?; let bytes: Int64 }
    struct Out: Encodable { let totalBytes: Int64; let candidates: [Item] }
    let items = candidates.map {
      Item(ruleID: $0.ruleID, category: $0.category,
           risk: String(describing: $0.risk), path: $0.url.path,
           app: $0.app, bytes: sizes[$0.url] ?? 0)
    }
    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = (try? enc.encode(Out(totalBytes: total, candidates: items))) ?? Data("{}".utf8)
    return String(decoding: data, as: UTF8.self) + "\n"
  }
}
