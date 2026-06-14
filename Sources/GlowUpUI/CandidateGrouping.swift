import GlowKit

// One ring/legend slice; bytes for a single category of the current selection.
public struct CategorySlice: Identifiable, Equatable, Sendable {
  public let category: String
  public let bytes: Int64
  public var id: String { category }
}

// A review-list section: candidates grouped under one app or category.
public struct ReviewGroup: Identifiable {
  public let key: String       // app name, else the display category
  public let category: String  // drives the row glyph
  public let candidates: [Candidate]
  public let total: Int64
  public var id: String { key }
}

public enum CandidateGrouping {
  // All candidates by app/category, largest first — the review list.
  public static func groups(_ candidates: [Candidate], sizes: [String: Int64]) -> [ReviewGroup] {
    var buckets: [String: [Candidate]] = [:]
    for c in candidates { buckets[c.app ?? categoryName(c.category), default: []].append(c) }
    return buckets.map { key, cands in
      ReviewGroup(key: key, category: cands.first?.category ?? "",
                  candidates: cands, total: cands.reduce(0) { $0 + (sizes[$1.id] ?? 0) })
    }.sorted { $0.total > $1.total }
  }

  // Selected bytes per category, largest first — the ring and its legend.
  public static func slices(_ candidates: [Candidate], selected: Set<String>,
                            sizes: [String: Int64]) -> [CategorySlice] {
    var acc: [String: Int64] = [:]
    for c in candidates where selected.contains(c.id) {
      acc[c.category, default: 0] += sizes[c.id] ?? 0
    }
    return acc.sorted { $0.value > $1.value }.map { CategorySlice(category: $0.key, bytes: $0.value) }
  }

  // Folds slices under 3% into one "other" bucket; both ring and legend render this same list.
  public static func forDisplay(_ slices: [CategorySlice]) -> [CategorySlice] {
    let total = Double(slices.reduce(0) { $0 + $1.bytes })
    guard total > 0 else { return slices }
    let threshold = total * 0.03
    var major = slices.filter { Double($0.bytes) >= threshold }
    let other = slices.filter { Double($0.bytes) < threshold }.reduce(0) { $0 + $1.bytes }
    if other > 0 { major.append(CategorySlice(category: "other", bytes: other)) }
    return major
  }
}
