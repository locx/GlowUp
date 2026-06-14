import SwiftUI
import GlowKit

// Legend for the hero ring: a proportional color bar + per-category share, sharing the ring's tints.
struct CategoryBar: View {
  let items: [CategorySlice]

  private var total: Int64 { max(items.reduce(0) { $0 + $1.bytes }, 1) }

  private func name(_ category: String) -> String {
    category == "other" ? "Other" : categoryName(category)
  }
  private func percent(_ bytes: Int64) -> Int {
    Int((Double(bytes) / Double(total) * 100).rounded())
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      GeometryReader { geo in
        HStack(spacing: 1.5) {
          ForEach(items, id: \.category) { item in
            categoryTint(item.category)
              .frame(width: max(3, geo.size.width * CGFloat(Double(item.bytes) / Double(total))))
          }
        }
      }
      .frame(height: 12)
      .clipShape(Capsule())

      ForEach(items, id: \.category) { item in
        HStack(spacing: 8) {
          RoundedRectangle(cornerRadius: 3)
            .fill(categoryTint(item.category))
            .frame(width: 10, height: 10)
          Text(name(item.category))
            .font(.caption).foregroundStyle(Color.textPrimary)
          Spacer()
          Text("\(percent(item.bytes))% · \(ReclaimLabel.format(item.bytes))")
            .font(.caption.monospacedDigit()).foregroundStyle(Color.textSecondary)
        }
      }
    }
  }
}
