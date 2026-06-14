import Foundation

// The single authoritative safety gate: nothing reaches the Trash without passing it.
// Catalog hits name specific vetted paths, so they face only the deny-list; swept hits are
// inferred by shape, so they must also not hold a live data store (PWA/app state).
public enum Vetter {
  public static func vet(catalog: [Candidate], swept: [Candidate], home: URL) -> [Candidate] {
    // Memoize the data-store probe per unique resolved path so duplicate swept hits scan disk once.
    var storeCache: [String: Bool] = [:]
    func holdsStore(_ url: URL) -> Bool {
      let resolved = PathUtil.canonical(url)
      let key = resolved.path
      if let cached = storeCache[key] { return cached }
      let result = DataStoreGuard.holdsDataStore(resolved)
      storeCache[key] = result
      return result
    }
    // Memoize the deny-list verdict per scan so the same path's credential probe runs disk once,
    // not twice (Resolver already vetted catalog hits) and not per duplicate. Key on the RAW input
    // path: DenyList short-circuits on a literal ".." before it resolves symlinks, so two distinct
    // inputs that resolve alike must not share a verdict.
    var vetoCache: [String: Bool] = [:]
    func vetoes(_ url: URL) -> Bool {
      let key = url.path
      if let cached = vetoCache[key] { return cached }
      let result = DenyList.vetoes(url, home: home)
      vetoCache[key] = result
      return result
    }
    // Catalog hits are pre-filtered by Resolver; re-checking keeps this the one gate of record.
    return catalog.filter { !vetoes($0.url) }
      + swept.filter {
        !vetoes($0.url) && !holdsStore($0.url)
      }
  }
}
