import SwiftUI

// Single source of the in-app brand glyph so the logo is consistent everywhere.
struct BrandMark: View {
  var size: CGFloat = 48
  var body: some View {
    Image(systemName: "sparkles").font(.system(size: size)).foregroundStyle(Color.brand)
  }
}
