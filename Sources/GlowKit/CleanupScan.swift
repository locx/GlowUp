import Foundation

// One scan pipeline shared by the app and the CLI so both surface identical candidates.
// Sources only propose candidates; Vetter is the single gate that enforces safety, so a new
// scanner can never bypass the deny-list or data-store protections.
public enum CleanupScan {
  public static func candidates(home: URL, catalog: Catalog, inventory: AppInventory,
                                includeRisks: Set<Risk>, advanced: Bool) -> [Candidate] {
    let catalogHits = Scanner(catalog: catalog, inventory: inventory)
      .scan(home: home, includeRisks: includeRisks)
    var swept = GenericCacheScanner.scan(home: home)
    swept += DuplicateExtensionScanner.scan(home: home)
    // These sweeps emit rebuildable-only candidates — skip their walks (and the app-inventory
    // build) when that tier can't pass the filter below anyway.
    if includeRisks.contains(.rebuildable) {
      swept += OrphanScanner.scan(home: home, known: inventory.knownSet())
      swept += WorkspaceStorageScanner.scan(home: home)
      // `advanced` gates the deep project-artifact walk on its own, so widening tiers
      // never silently switches on that expensive scan.
      if advanced { swept += AdvancedScan.run(home: home, catalog: catalog) }  // project artifacts
    }
    swept = swept.filter { includeRisks.contains($0.risk) }
    // A vetted catalog rule is authoritative: drop any swept hit that nests with one so the generic
    // sweep can't relabel or re-tier it, which would make a category appear/vanish between modes.
    // Sort catalog paths once so each swept hit's overlap check is a binary search, not an O(catalog)
    // scan; the filter preserves swept's input order so dedupe's protectionRank tie-break is unaffected.
    let catalogPaths = catalogHits.map { $0.url.resolvingSymlinksInPath().path }.sorted()
    swept = swept.filter { !overlapsCatalog($0.url.resolvingSymlinksInPath().path, catalogPaths) }
    return Candidate.dedupe(Vetter.vet(catalog: catalogHits, swept: swept, home: home))
  }

  // True when a sorted catalog path equals, is an ancestor of, or is a descendant of `sp` — the
  // same bidirectional nesting the previous linear filter caught, but via binary search.
  private static func overlapsCatalog(_ sp: String, _ sortedCatalog: [String]) -> Bool {
    // Catalog ancestor-or-equal of sp: an exact match, or sp lies under a catalog dir.
    var ancestor = sp
    while true {
      if binaryContains(sortedCatalog, ancestor) { return true }
      guard let slash = ancestor.lastIndex(of: "/"), slash != ancestor.startIndex else { break }
      ancestor = String(ancestor[ancestor.startIndex..<slash])
    }
    // Catalog strict descendant of sp: first path >= "sp/" must start with "sp/".
    let prefix = sp + "/"
    let i = lowerBound(sortedCatalog, prefix)
    return i < sortedCatalog.count && sortedCatalog[i].hasPrefix(prefix)
  }

  private static func binaryContains(_ a: [String], _ target: String) -> Bool {
    let i = lowerBound(a, target)
    return i < a.count && a[i] == target
  }

  // First index whose element is >= target.
  private static func lowerBound(_ a: [String], _ target: String) -> Int {
    var lo = 0, hi = a.count
    while lo < hi {
      let mid = (lo + hi) / 2
      if a[mid] < target { lo = mid + 1 } else { hi = mid }
    }
    return lo
  }
}
