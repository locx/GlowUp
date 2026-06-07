import Foundation

public enum BaseRoot: String, Codable, CaseIterable, Sendable {
  case home, appSupport, caches, logs, xcode

  public func url(home: URL) -> URL {
    switch self {
    case .home:       return home
    case .appSupport: return home.appending(path: "Library/Application Support")
    case .caches:     return home.appending(path: "Library/Caches")
    case .logs:       return home.appending(path: "Library/Logs")
    case .xcode:      return home.appending(path: "Library/Developer/Xcode")
    }
  }
}
