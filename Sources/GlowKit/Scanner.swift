import Foundation

public struct Scanner {
  private let catalog: Catalog
  private let inventory: AppInventory

  public init(catalog: Catalog, inventory: AppInventory) {
    self.catalog = catalog
    self.inventory = inventory
  }

  // Resolve all rules into candidates whose effective risk is requested.
  public func scan(home: URL, includeRisks: Set<Risk> = [.safe],
                   diagnostics: ScanDiagnostics? = nil) -> [Candidate] {
    var out: [Candidate] = []
    for rule in catalog.rules {
      if rule.requiresInstalled == true {
        guard let id = rule.appBundleID, inventory.isInstalled(bundleID: id) else { continue }
      }
      for spec in rule.paths {
        let risk = spec.effectiveRisk(ruleRisk: rule.risk)
        guard includeRisks.contains(risk) else { continue }
        for url in Resolver.resolve(spec, home: home, diagnostics: diagnostics) {
          out.append(Candidate(ruleID: rule.id, app: rule.app,
                               category: rule.category, risk: risk,
                               why: rule.why, url: url))
        }
      }
    }
    return out
  }
}
