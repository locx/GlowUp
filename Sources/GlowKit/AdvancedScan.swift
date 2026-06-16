import Foundation

public enum AdvancedScan {
  /// Advanced-only because project build dirs are large, slow to measure, and developer-facing.
  public static func run(home: URL, catalog: Catalog,
                         diagnostics: ScanDiagnostics? = nil) -> [Candidate] {
    let roots = catalog.projectRoots.map { PathUtil.expandingTilde($0, home: home) }
    return ProjectScanner.scan(roots: roots, artifacts: Set(catalog.projectArtifacts),
                               diagnostics: diagnostics)
  }

  // Always-scanned baseline folders; shared with the Reports UI so the shown list can't drift.
  public static let defaultReportFolderNames = ["Downloads", "Movies"]

  /// Report-only large files surfaced alongside results (never auto-cleaned).
  /// `extraDirs` are user-added folders; the baseline folders are always included.
  public static func reports(home: URL, extraDirs: [URL] = []) -> [Report] {
    let roots = defaultReportFolderNames.map { home.appending(path: $0) } + extraDirs
    // Dedupe by resolved path so an added folder overlapping a default isn't listed twice.
    var seen = Set<String>()
    let dirs = roots.filter { seen.insert($0.standardizedFileURL.path).inserted }
    return LargeFileReporter.scan(dirs: dirs, minBytes: 100_000_000)
  }
}
