import Foundation

// The single authoritative safety gate: nothing reaches the Trash without passing it.
// Catalog hits name specific vetted paths, so they face only the deny-list; swept hits are
// inferred by shape, so they must also not hold a live data store (PWA/app state).
public enum Vetter {
  public static func vet(catalog: [Candidate], swept: [Candidate], home: URL) -> [Candidate] {
    // Resolve $HOME once per scan; the value is identical to resolving it per candidate.
    let resolvedHomePath = home.standardizedFileURL.resolvingSymlinksInPath().path
    // Keyed on the resolved path (unlike the raw-keyed deny-list cache below): the data-store probe
    // only reads directory contents, so two symlinks to one dir share a probe instead of two walks.
    var storeCache: [String: Bool] = [:]
    func holdsStore(_ url: URL) -> Bool {
      let resolved = url.resolvingSymlinksInPath()
      let key = resolved.path
      if let cached = storeCache[key] { return cached }
      let result = DataStoreGuard.holdsDataStore(resolved)
      storeCache[key] = result
      return result
    }
    // Key on the RAW input path: DenyList short-circuits on a literal ".." before resolving
    // symlinks, so two distinct inputs that resolve alike must not share a cached verdict.
    var vetoCache: [String: Bool] = [:]
    func vetoes(_ url: URL) -> Bool {
      let key = url.path
      if let cached = vetoCache[key] { return cached }
      let result = DenyList.vetoes(url, resolvedHomePath: resolvedHomePath)
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
