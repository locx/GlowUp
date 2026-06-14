import Foundation
import GlowKit

@MainActor
public final class AppModel: ObservableObject {
  public enum Phase: Equatable { case idle, scanning, results, cleaning, done }

  /// Summarises a restore attempt so the UI can display the outcome.
  public struct RestoreResult: Equatable {
    public let restored: Int
    public let failed: Int
    public init(restored: Int, failed: Int) {
      self.restored = restored; self.failed = failed
    }
  }

  @Published public private(set) var phase: Phase = .idle
  @Published public private(set) var candidates: [Candidate] = []
  @Published public private(set) var sizes: [String: Int64] = [:]
  // Recomputing the selection totals here, not per render, keeps unrelated published
  // changes (phase, trash count, history) from re-walking the candidate list.
  @Published public var selected: Set<String> = [] {
    didSet { recomputeSelectionTotals() }
  }
  /// Selected bytes per category for the ring and its legend.
  @Published public private(set) var categoryBytes: [CategorySlice] = []
  @Published public private(set) var selectedBytes: Int64 = 0
  @Published public private(set) var lastFreed: Int64 = 0
  @Published public private(set) var lastCleanFailures: Int = 0
  /// Set when restore history couldn't be saved, so the UI can warn the cleanup isn't undoable.
  @Published public private(set) var lastCleanWarning: String? = nil
  /// When true, scan merges advanced scanner results; callers widen tiers via Risk.scanTiers.
  @Published public var advanced = false
  /// Large-file report items surfaced alongside scan results (never cleaned automatically).
  @Published public private(set) var reports: [Report] = []
  /// Outcome of the most recent restore(_:) or restoreLast() call; nil until one has been made.
  @Published public private(set) var lastRestore: RestoreResult? = nil
  /// True while a restore's file moves are in flight; blocks overlapping history-store writers.
  @Published public private(set) var restoring = false
  /// True while the menu-bar quick action runs; serializes it against scans, cleans, and itself.
  @Published public private(set) var quickCleanBusy = false
  /// Items in the user's Trash; drives the Empty Trash button's enabled state.
  @Published public private(set) var trashCount: Int = 0
  /// Cleanup batches newest-first, cached so views don't re-read the store on every render.
  @Published public private(set) var batches: [CleanupBatch] = []
  /// True when the bundled catalog failed to load, so empty results aren't mistaken for a clean Mac.
  @Published public private(set) var catalogLoadFailed: Bool = false
  /// True when Full Disk Access is off; an empty scan then means "limited", not "already clean".
  @Published public private(set) var limitedAccess: Bool = false
  /// Size of system `/Library/Caches`; the advanced, root-only, NON-recoverable clean.
  @Published public private(set) var systemCacheBytes: Int64 = 0
  /// Candidates grouped for the review list; recomputed on scan, not per render.
  @Published public private(set) var reviewGroups: [ReviewGroup] = []
  /// Default pre-checked ids; computed once per scan so views don't rebuild the set per render.
  @Published public private(set) var defaultSelection: Set<String> = []

  private func recomputeSelectionTotals() {
    selectedBytes = candidates.filter { selected.contains($0.id) }
                              .reduce(0) { $0 + (sizes[$1.id] ?? 0) }
    categoryBytes = CandidateGrouping.slices(candidates, selected: selected, sizes: sizes)
  }

  private let catalog: Catalog
  private let inventory: AppInventory
  private let home: URL
  private let mover: ItemMover
  private let storeURL: URL
  // Runners for the two non-reversible permanent ops; injectable so a test can prove the default
  // clean path never fires them. Defaults are the real runners, so production behavior is unchanged.
  private let rootRunner: RootCommandRunner
  private let shellRunner: ShellRunner

  public init(catalog: Catalog, inventory: AppInventory, home: URL,
              mover: ItemMover, storeURL: URL, catalogLoadFailed: Bool = false,
              rootRunner: RootCommandRunner = AdminRunner(),
              shellRunner: ShellRunner = ProcessRunner()) {
    self.catalog = catalog; self.inventory = inventory; self.home = home
    self.mover = mover; self.storeURL = storeURL
    self.catalogLoadFailed = catalogLoadFailed
    self.rootRunner = rootRunner; self.shellRunner = shellRunner
    refreshHistory()
    refreshTrash()
  }

  // Convenience for the real app: bundled catalog, system services, real $HOME.
  public static func live() -> AppModel {
    let loaded = try? CatalogLoader.loadBundled()
    let catalog = loaded ?? .empty
    return AppModel(catalog: catalog, inventory: SystemInventory(),
                    home: FileManager.default.homeDirectoryForCurrentUser,
                    mover: SystemMover(),
                    storeURL: RestoreStore.defaultStoreURL,
                    catalogLoadFailed: loaded == nil)
  }

  public func scan(includeRisks: Set<Risk>) async {
    guard phase != .scanning, phase != .cleaning else { return }
    phase = .scanning

    // Tier policy stays with the caller (Risk.scanTiers/cleanTiers); advanced only adds scanners.
    // The large-file report walk shares no data with the candidate walk — overlap them.
    async let reportsResult = Task.detached(priority: .userInitiated) { [home] in
      AdvancedScan.reports(home: home)
    }.value
    // Filesystem walks run off the main actor so the UI doesn't stall for the whole scan.
    let deduped = await Task.detached(priority: .userInitiated) { [catalog, home, inventory, advanced] in
      CleanupScan.candidates(home: home, catalog: catalog, inventory: inventory,
                             includeRisks: includeRisks, advanced: advanced)
    }.value
    let measured = await SizeMeasurer.measure(deduped.map(\.url))
    // Drop empty candidates — nothing to reclaim, just noise in the list.
    let kept = deduped.filter { (measured[$0.url] ?? 0) > 0 }
    candidates = kept
    sizes = Dictionary(kept.map { ($0.id, measured[$0.url] ?? 0) },
                       uniquingKeysWith: { a, _ in a })
    reviewGroups = CandidateGrouping.groups(kept, sizes: sizes)
    defaultSelection = Selection.defaultSelected(kept)
    selected = defaultSelection
    reports = await reportsResult
    limitedAccess = !Self.hasFullDiskAccess(home: home)
    refreshTrash()
    phase = .results
  }

  public func cleanSelected() async {
    // A restore or quick clean in flight shares the history file; overlapping writers would lose-update it.
    guard phase == .results, !restoring, !quickCleanBusy else { return }
    lastRestore = nil
    lastCleanWarning = nil
    phase = .cleaning
    // Privacy/stateful must never be trashed even if selected — enforce the tier policy at the boundary.
    let tiers = Risk.cleanTiers(advanced: advanced)
    let toClean = candidates.filter { selected.contains($0.id) && tiers.contains($0.risk) }
    let items = toClean.map { ($0.url, sizes[$0.id] ?? 0) }
    let result = Trasher(mover: mover).trash(items)
    lastCleanFailures = result.failures.count
    recordHistory(result.trashed)
    // Sum sizes once per unique path that was successfully trashed (dedupe guarantees no duplicates).
    let trashedPaths = Set(result.trashed.map(\.originalPath))
    lastFreed = toClean.reduce(0) { acc, cand in
      trashedPaths.contains(cand.url.path) ? acc + (sizes[cand.id] ?? 0) : acc
    }
    refreshTrash()
    phase = .done
  }

  private func recordHistory(_ trashed: [TrashedItem]) {
    guard !trashed.isEmpty else { return }
    let batch = CleanupBatch(id: UUID().uuidString, date: Date(), items: trashed)
    do {
      try RestoreStore(storeURL: storeURL).record(batch)
    } catch {
      // Losing the undo silently would betray the restore promise — warn loudly.
      lastCleanWarning = "Restore history couldn't be saved — this cleanup can't be undone from GlowUp."
    }
    refreshHistory()
  }

  /// Safe-tier scan for the menu-bar quick action; review state (candidates, phase) stays untouched
  /// so an open Advanced result set isn't clobbered.
  public func quickScanSafe() async -> [(url: URL, bytes: Int64, risk: Risk)] {
    guard !quickCleanBusy, phase != .scanning, phase != .cleaning, !restoring else { return [] }
    quickCleanBusy = true
    defer { quickCleanBusy = false }
    let tiers = Risk.cleanTiers(advanced: false)
    let found = await Task.detached(priority: .userInitiated) { [catalog, home, inventory] in
      CleanupScan.candidates(home: home, catalog: catalog, inventory: inventory,
                             includeRisks: tiers, advanced: false)
    }.value
    let sizes = await SizeMeasurer.measure(found.map(\.url))
    return found.compactMap { c -> (url: URL, bytes: Int64, risk: Risk)? in
      let bytes = sizes[c.url] ?? 0
      return bytes > 0 ? (c.url, bytes, c.risk) : nil
    }
  }

  /// Trashes a quick-scan result; records history and totals without touching review state.
  public func quickClean(_ items: [(url: URL, bytes: Int64, risk: Risk)]) async {
    guard !quickCleanBusy, phase != .cleaning, !restoring else { return }
    quickCleanBusy = true
    defer { quickCleanBusy = false }
    lastRestore = nil
    lastCleanWarning = nil
    // Quick action is always non-advanced; enforce the tier policy at the boundary so a stale
    // or hand-built input can never trash privacy/stateful data the scan filter alone would miss.
    let tiers = Risk.cleanTiers(advanced: false)
    let toClean = items.filter { tiers.contains($0.risk) }.map { ($0.url, $0.bytes) }
    let mover = self.mover
    let result = await Task.detached(priority: .userInitiated) {
      Trasher(mover: mover).trash(toClean)
    }.value
    lastCleanFailures = result.failures.count
    recordHistory(result.trashed)
    lastFreed = result.trashed.reduce(0) { $0 + $1.bytes }
    refreshTrash()
  }

  /// Whether any cleanup is still restorable; fully-restored batches are dropped from history.
  public var canRestoreLast: Bool { !batches.isEmpty }

  /// Bundled catalog location, exposed so views never touch GlowKit services directly.
  public var catalogURL: URL? { CatalogLoader.bundledURL }

  // Listing the always-present, TCC-gated com.apple.TCC dir succeeds only with Full Disk Access.
  static func hasFullDiskAccess(home: URL) -> Bool {
    let probe = home.appending(path: "Library/Application Support/com.apple.TCC")
    return (try? FileManager.default.contentsOfDirectory(atPath: probe.path)) != nil
  }

  /// Restrict the selection to what a non-advanced clean may trash — the menu-bar quick action's contract.
  public func selectSafeOnly() {
    let tiers = Risk.cleanTiers(advanced: false)
    selected = Set(candidates.filter { tiers.contains($0.risk) }.map(\.id))
  }

  public func refreshTrash() {
    trashCount = EmptyTrash.itemCount()
  }

  public func refreshSystemCaches() async {
    systemCacheBytes = await SystemCacheCleaner.totalBytes()
  }

  // Root, permanent (no Trash) — gated behind an Advanced opt-in + admin prompt in the UI.
  public func cleanSystemCaches() -> Bool {
    let ok = SystemCacheCleaner.cleanAll(runner: rootRunner)
    Task { await refreshSystemCaches() }
    return ok
  }

  // Removes simulator devices macOS marks unavailable; permanent but safe (they're already unusable).
  public func removeUnavailableSimulators() -> Bool {
    SimulatorCleaner.deleteUnavailable(runner: shellRunner)
  }

  public func refreshHistory() {
    batches = RestoreStore(storeURL: storeURL).batches()
  }

  public func emptyTrash() {
    // Disable immediately, then re-stat so a failed Finder empty re-enables the button.
    trashCount = 0
    Task {
      await Task.detached(priority: .userInitiated) { EmptyTrash.empty() }.value
      refreshTrash()
    }
  }

  /// Restores a specific batch and marks it restored so its action disables.
  @discardableResult
  public func restore(_ batch: CleanupBatch) async -> RestoreResult {
    // Double-taps and in-flight cleans would race this restore on the same files and history store.
    guard !restoring, phase != .cleaning, !quickCleanBusy else { return RestoreResult(restored: 0, failed: 0) }
    restoring = true
    defer { restoring = false }
    let storeURL = self.storeURL
    // File moves off the main actor; the store prunes itself to whatever is still in the Trash.
    let r = await Task.detached(priority: .userInitiated) {
      RestoreStore(storeURL: storeURL).restore(batch)
    }.value
    let res = RestoreResult(restored: r.restored, failed: r.failed.count)
    lastRestore = res
    // A failed history prune leaves a stale batch on disk; surface it rather than swallow it.
    if !r.historyPruned {
      lastCleanWarning = "Restore succeeded but history couldn't be updated."
    }
    refreshHistory()
    return res
  }

  /// Bytes freed across all recorded batches.
  public var totalReclaimedAllTime: Int64 {
    batches.reduce(0) { $0 + $1.totalBytes }
  }

  @discardableResult
  public func restoreLast() async -> RestoreResult {
    guard let last = batches.first else {
      let r = RestoreResult(restored: 0, failed: 0)
      lastRestore = r
      return r
    }
    return await restore(last)
  }

}
