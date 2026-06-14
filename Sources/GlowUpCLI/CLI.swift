import Foundation
import GlowKit

public enum CLI {
  // Renders results to a string + exit code; never prints (so it's testable).
  public static func run(args: [String], catalog: Catalog, inventory: AppInventory,
                         home: URL, mover: ItemMover, storeURL: URL) async -> (String, Int32) {
    let o = CLIOptions.parse(args)

    if !o.unknown.isEmpty {
      return ("Unknown option(s): \(o.unknown.joined(separator: " "))\n", 2)
    }

    if o.mode == .restore {
      let store = RestoreStore(storeURL: storeURL)
      guard let last = store.batches().first else {
        return o.json ? (restoreJSON(restored: 0, failed: 0), 0) : ("Nothing to restore.\n", 0)
      }
      let r = store.restore(last)
      let code: Int32 = r.failed.isEmpty ? 0 : 1
      if o.json { return (restoreJSON(restored: r.restored, failed: r.failed.count), code) }
      return ("Restored \(r.restored); \(r.failed.count) could not be restored.\n", code)
    }

    let scanned = CleanupScan.candidates(
      home: home, catalog: catalog, inventory: inventory,
      includeRisks: Risk.scanTiers(advanced: o.advanced), advanced: o.advanced)

    let sizes = await SizeMeasurer.measure(scanned.map(\.url))
    // Drop empty candidates — nothing to reclaim, just noise in the list.
    let candidates = scanned.filter { (sizes[$0.url] ?? 0) > 0 }
    let total = candidates.reduce(Int64(0)) { $0 + (sizes[$1.url] ?? 0) }

    // LargeFileReporter is report-only — never included in actionable/clean set.
    let reports = AdvancedScan.reports(home: home)

    // Perform the clean before any output so --json --clean trashes instead of silently listing.
    var cleanResult: (movedBytes: Int64, failures: Int)? = nil
    var historyWarning: String? = nil
    if o.mode == .clean {
      // Only trash safe (default) or safe+rebuildable (--advanced); never privacy/stateful.
      let cleanTiers = Risk.cleanTiers(advanced: o.advanced)
      let actionable = candidates.filter { cleanTiers.contains($0.risk) }
      let result = Trasher(mover: mover).trash(actionable.map { ($0.url, sizes[$0.url] ?? 0) })
      if !result.trashed.isEmpty {
        do {
          try RestoreStore(storeURL: storeURL)
            .record(CleanupBatch(id: UUID().uuidString, date: Date(), items: result.trashed))
        } catch {
          // Losing the undo silently would betray the restore promise — warn loudly.
          historyWarning = "Warning: restore history could not be saved; this cleanup cannot be undone from GlowUp."
        }
      }
      // Report only what actually moved, so failures don't over-claim reclaimed space.
      let movedBytes = result.trashed.reduce(Int64(0)) { $0 + $1.bytes }
      cleanResult = (movedBytes, result.failures.count)
    }
    let exitCode: Int32 = (cleanResult?.failures ?? 0) > 0 ? 1 : 0

    if o.json {
      let (out, code) = jsonOutput(candidates, sizes, total, reports,
                                   movedBytes: cleanResult?.movedBytes, warning: historyWarning)
      return (out, code != 0 ? code : exitCode)
    }

    var lines = candidates.map {
      "  \(paint($0.risk, o.noColor)) \(byte(sizes[$0.url] ?? 0))  \($0.url.path)"
    }

    switch o.mode {
    case .clean:
      lines.append("Moved \(byte(cleanResult?.movedBytes ?? 0)) to the Trash — empty Trash to reclaim.")
      if let f = cleanResult?.failures, f > 0 { lines.append("\(f) could not be moved.") }
      if let w = historyWarning { lines.append(w) }
    case .list:
      lines.insert("\(candidates.count) item(s), \(byte(total)):", at: 0)
      appendReports(to: &lines, reports: reports, noColor: o.noColor)
    default: // dryRun
      lines.insert("Would free \(byte(total)) (dry run — nothing was moved):", at: 0)
      appendReports(to: &lines, reports: reports, noColor: o.noColor)
    }
    return (lines.joined(separator: "\n") + "\n", exitCode)
  }

  // Appends the large-file report section (report-only, never cleaned).
  private static func appendReports(to lines: inout [String], reports: [Report], noColor: Bool) {
    guard !reports.isEmpty else { return }
    lines.append("Reports (not cleaned):")
    for r in reports {
      lines.append("  \(byte(r.bytes))  \(r.url.path)")
    }
  }

  private static func byte(_ b: Int64) -> String { ByteFormat.string(b) }

  // --restore must honour --json so scripted callers never receive plain text.
  private static func restoreJSON(restored: Int, failed: Int) -> String {
    struct Out: Encodable { let restored, failed: Int }
    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = (try? enc.encode(Out(restored: restored, failed: failed))) ?? Data("{}".utf8)
    return String(decoding: data, as: UTF8.self) + "\n"
  }

  private static func paint(_ risk: Risk, _ noColor: Bool) -> String {
    let tag = risk.displayName
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

  // Returns (output, exitCode); non-zero exit on encode failure.
  private static func jsonOutput(_ candidates: [Candidate], _ sizes: [URL: Int64],
                                 _ total: Int64, _ reports: [Report],
                                 movedBytes: Int64? = nil, warning: String? = nil) -> (String, Int32) {
    struct Item: Encodable { let ruleID, category, risk, path: String; let app: String?; let bytes: Int64 }
    struct ReportItem: Encodable { let path: String; let bytes: Int64 }
    struct Out: Encodable {
      let totalBytes: Int64; let movedBytes: Int64?; let warning: String?
      let candidates: [Item]; let reports: [ReportItem]
    }

    let items = candidates.map {
      Item(ruleID: $0.ruleID, category: $0.category,
           risk: String(describing: $0.risk), path: $0.url.path,
           app: $0.app, bytes: sizes[$0.url] ?? 0)
    }
    let reportItems = reports.map { ReportItem(path: $0.url.path, bytes: $0.bytes) }

    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
      let data = try enc.encode(Out(totalBytes: total, movedBytes: movedBytes, warning: warning,
                                    candidates: items, reports: reportItems))
      return (String(decoding: data, as: UTF8.self) + "\n", 0)
    } catch {
      return ("JSON encoding failed: \(error)\n", 1)
    }
  }
}
