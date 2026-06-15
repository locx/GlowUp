import Foundation

public enum AdvancedScan {
  /// Advanced-only because project build dirs are large, slow to measure, and developer-facing.
  public static func run(home: URL, catalog: Catalog,
                         diagnostics: ScanDiagnostics? = nil) -> [Candidate] {
    let roots = catalog.projectRoots.map { PathUtil.expandingTilde($0, home: home) }
    return ProjectScanner.scan(roots: roots, artifacts: Set(catalog.projectArtifacts),
                               diagnostics: diagnostics)
  }

  /// Report-only large files surfaced alongside results (never auto-cleaned).
  public static func reports(home: URL) -> [Report] {
    LargeFileReporter.scan(
      dirs: [home.appending(path: "Downloads"), home.appending(path: "Movies")],
      minBytes: 100_000_000
    )
  }
}
