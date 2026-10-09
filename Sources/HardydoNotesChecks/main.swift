import Foundation

let suites: [(name: String, run: @MainActor () async -> Void)] = [
    ("Naming", { runNamingChecks() }),
    ("Styler", { runStylerChecks() }),
    ("Formatting", { runFormattingChecks() }),
    ("JSONFormatter", { runJSONFormatterChecks() }),
    ("HTML", { runHTMLChecks() }),
    ("ExportPage", { runExportPageChecks() }),
    ("Tab", { runTabChecks() }),
    ("TabPin", { runTabPinChecks() }),
    ("LineEditing", { runLineEditingChecks() }),
    ("Summary", { runSummaryChecks() }),
    ("FuzzyMatch", { runFuzzyMatchChecks() }),
    ("Language", { runLanguageChecks() }),
    ("Highlighter", { runHighlighterChecks() }),
    ("Folding", { runFoldingChecks() }),
    ("FoldingEdge", { runFoldingEdgeChecks() }),
    ("FoldShift", { runFoldShiftChecks() }),
    ("Outline", { runOutlineChecks() }),
    ("Store", { await runStoreChecks() }),
    ("Revision", { runRevisionChecks() }),
    ("NoteSummary", { runNoteSummaryChecks() }),
    ("Rename", { runRenameChecks() }),
    ("Lock", { await runLockChecks() }),
    ("OrderAndFile", { await runOrderAndFileChecks() }),
    ("FileSafety", { await runFileSafetyChecks() }),
    ("Search", { await runSearchChecks() }),
    ("SearchAll", { await runSearchAllChecks() }),
    ("Pin", { await runPinChecks() }),
    ("CacheCompatibility", { runCacheCompatibilityChecks() }),
    ("NotesFile", { await runNotesFileChecks() }),
    ("SaveSkipping", { runSaveSkippingChecks() }),
    ("UnreadableInPlace", { runUnreadableInPlaceChecks() }),
    ("JSONFile", { await runJSONFileChecks() }),
    ("TrashPath", { runTrashPathChecks() }),
    ("AppPaths", { runAppPathsChecks() }),
    ("Group", { runGroupChecks() }),
    ("SidebarReorder", { runSidebarReorderChecks() }),
    ("ReorderGeometry", { runReorderGeometryChecks() }),
    ("LineIndex", { runLineIndexChecks() }),
    ("TokenDiff", { runTokenDiffChecks() }),
    ("ZoomLevel", { runZoomLevelChecks() }),
    ("Preferences", { runPreferencesChecks() }),
    ("SidebarNavigation", { runSidebarNavigationChecks() }),
]

for suite in suites {
    let before = failures
    await suite.run()
    if failures > before { print("\(suite.name): \(failures - before) failed") }
}

removeChecksFolder()
print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
