import Foundation

// The single authoritative safety gate: nothing reaches the Trash without passing it.
// Catalog hits name specific vetted paths, so they face only the deny-list; swept hits are
// inferred by shape, so they must also not hold a live data store (PWA/app state).
public enum Vetter {
  public static func vet(catalog: [Candidate], swept: [Candidate], home: URL) -> [Candidate] {
    // Catalog hits are pre-filtered by Resolver; re-checking keeps this the one gate of record.
    catalog.filter { !DenyList.vetoes($0.url, home: home) }
      + swept.filter {
        !DenyList.vetoes($0.url, home: home) && !DataStoreGuard.holdsDataStore($0.url)
      }
  }
}
