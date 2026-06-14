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
      if advanced { swept += AdvancedScan.run(home: home, catalog: catalog) }  // project artifacts
    }
    swept = swept.filter { includeRisks.contains($0.risk) }
    // A vetted catalog rule is authoritative: drop any swept hit that nests with one so the generic
    // sweep can't relabel or re-tier it, which would make a category appear/vanish between modes.
    let catalogPaths = catalogHits.map { $0.url.resolvingSymlinksInPath().path }
    swept = swept.filter { s in
      let sp = s.url.resolvingSymlinksInPath().path
      return !catalogPaths.contains { $0 == sp || $0.hasPrefix(sp + "/") || sp.hasPrefix($0 + "/") }
    }
    return Candidate.dedupe(Vetter.vet(catalog: catalogHits, swept: swept, home: home))
  }
}
