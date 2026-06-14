import Foundation
import GlowKit
import GlowUpCLI

let args = Array(CommandLine.arguments.dropFirst())
let loaded = try? CatalogLoader.loadBundled()
// Sweepers still run with an empty catalog, but silence here would hide a broken install.
if loaded == nil {
  FileHandle.standardError.write(
    Data("Warning: bundled catalog failed to load; catalog rules skipped.\n".utf8))
}
let catalog = loaded ?? .empty
let (output, code) = await CLI.run(
  args: args, catalog: catalog, inventory: SystemInventory(),
  home: FileManager.default.homeDirectoryForCurrentUser,
  mover: SystemMover(), storeURL: RestoreStore.defaultStoreURL)

FileHandle.standardOutput.write(Data(output.utf8))
exit(code)
