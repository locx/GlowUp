import Foundation
import GlowKit
import GlowUpCLI

let args = Array(CommandLine.arguments.dropFirst())
let catalog = (try? CatalogLoader.loadBundled())
  ?? Catalog(schemaVersion: 1, rules: [], projectRoots: [], projectArtifacts: [])
let support = FileManager.default
  .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
let storeURL = support.appending(path: "GlowUp/history.json")

let (output, code) = await CLI.run(
  args: args, catalog: catalog, inventory: SystemInventory(),
  home: FileManager.default.homeDirectoryForCurrentUser,
  mover: SystemMover(), storeURL: storeURL)

FileHandle.standardOutput.write(Data(output.utf8))
exit(code)
