import Foundation
import GlowKit

@MainActor
public final class AppModel: ObservableObject {
  public enum Phase: Equatable { case idle, scanning, results, cleaning, done }

  @Published public private(set) var phase: Phase = .idle
  @Published public private(set) var candidates: [Candidate] = []
  @Published public private(set) var sizes: [String: Int64] = [:]
  @Published public var selected: Set<String> = []
  @Published public private(set) var lastFreed: Int64 = 0
  @Published public private(set) var lastCleanFailures: Int = 0

  private let catalog: Catalog
  private let inventory: AppInventory
  private let home: URL
  private let mover: ItemMover
  private let storeURL: URL

  public init(catalog: Catalog, inventory: AppInventory, home: URL,
              mover: ItemMover, storeURL: URL) {
    self.catalog = catalog; self.inventory = inventory; self.home = home
    self.mover = mover; self.storeURL = storeURL
  }

  // Convenience for the real app: bundled catalog, system services, real $HOME.
  public static func live() -> AppModel {
    let emptyJSON = Data(#"{"schemaVersion":1,"rules":[],"projectRoots":[],"projectArtifacts":[]}"#.utf8)
    let catalog = (try? CatalogLoader.loadBundled())
      ?? (try! JSONDecoder().decode(Catalog.self, from: emptyJSON))
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return AppModel(catalog: catalog, inventory: SystemInventory(),
                    home: FileManager.default.homeDirectoryForCurrentUser,
                    mover: SystemMover(),
                    storeURL: support.appending(path: "GlowUp/history.json"))
  }

  public var selectedBytes: Int64 {
    candidates.filter { selected.contains($0.id) }
              .reduce(0) { $0 + (sizes[$1.id] ?? 0) }
  }

  public func scan(includeRisks: Set<Risk> = Set(Risk.allCases)) async {
    guard phase != .scanning, phase != .cleaning else { return }
    phase = .scanning
    let found = Scanner(catalog: catalog, inventory: inventory)
      .scan(home: home, includeRisks: includeRisks)
    let measured = await SizeMeasurer.measure(found.map(\.url))
    candidates = found
    sizes = Dictionary(found.map { ($0.id, measured[$0.url] ?? 0) },
                       uniquingKeysWith: { a, _ in a })
    selected = Selection.defaultSelected(found)
    phase = .results
  }

  public func cleanSelected() async {
    guard phase == .results else { return }
    phase = .cleaning
    let toClean = candidates.filter { selected.contains($0.id) }
    let urls = toClean.map(\.url)
    let result = Trasher(mover: mover).trash(urls)
    lastCleanFailures = result.failures.count
    if !result.trashed.isEmpty {
      let batch = CleanupBatch(id: UUID().uuidString, date: Date(), items: result.trashed)
      try? RestoreStore(storeURL: storeURL).record(batch)
    }
    // Sum sizes for candidates whose URL was successfully trashed.
    let trashedPaths = Set(result.trashed.map(\.originalPath))
    lastFreed = toClean.reduce(0) { acc, cand in
      trashedPaths.contains(cand.url.path) ? acc + (sizes[cand.id] ?? 0) : acc
    }
    phase = .done
  }

  public func restoreLast() async -> (restored: Int, failed: Int) {
    let store = RestoreStore(storeURL: storeURL)
    guard let last = store.batches().first else { return (0, 0) }
    let r = store.restore(last)
    return (r.restored, r.failed.count)
  }
}
