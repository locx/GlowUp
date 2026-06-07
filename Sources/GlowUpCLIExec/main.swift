import Foundation
import GlowKit
import GlowUpCLI

let args = Array(CommandLine.arguments.dropFirst())
// Catalog memberwise init is internal; decode from JSON as a safe fallback.
let emptyCatalogJSON = Data(#"{"schemaVersion":1,"rules":[],"projectRoots":[],"projectArtifacts":[]}"#.utf8)
let catalog = (try? CatalogLoader.loadBundled())
  ?? (try! CatalogLoader.load(data: emptyCatalogJSON))
let support = FileManager.default
  .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
let storeURL = support.appending(path: "GlowUp/history.json")

let (output, code) = await CLI.run(
  args: args, catalog: catalog, inventory: SystemInventory(),
  home: FileManager.default.homeDirectoryForCurrentUser,
  mover: SystemMover(), storeURL: storeURL)

FileHandle.standardOutput.write(Data(output.utf8))
exit(code)
