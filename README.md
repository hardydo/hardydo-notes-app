# Hardydo Notes

[![CI](https://github.com/hardydo/hardydo-notes-app/actions/workflows/ci.yml/badge.svg)](https://github.com/hardydo/hardydo-notes-app/actions/workflows/ci.yml)

A fast, local-first note app for macOS, built with SwiftUI and AppKit.

- Markdown editor with live styling, a GitHub-style preview and a split view
- Syntax highlighting and code folding for JSON, JavaScript, TypeScript, Python, HTML, CSS, YAML, SQL, Shell and Swift
- VS Code-style tabs: preview tabs, pinned tabs, reopen closed tab, and familiar shortcuts
- Note groups with colours, pinned notes, and Edge-style drag and drop for notes, groups and tabs
- Opens and edits text files from disk; exports a note as its own file type, HTML or PDF
- Your notes stay on your Mac, in `~/Library/Application Support/com.hardydo.drivenotes`

## Requirements

macOS 15 or later and Swift 6.2 or later (the Command Line Tools are enough; Xcode is not needed).

## Build

```bash
./scripts/build-app.sh            # builds dist/Hardydo Notes.app
./scripts/build-app.sh --install  # also moves it to ~/Applications
./scripts/test.sh                 # runs the tests (swift test, plus a fix for the Command Line Tools)
```

[`docs/hardydo-notes-guide.md`](docs/hardydo-notes-guide.md) is the user guide (in Vietnamese): features, shortcuts,
where notes are stored, how to restore a backup, and the source layout. [`Tools/probes`](Tools/probes) drives the
real app in a hidden window to measure speed and check drag and drop, saving and tab sessions.

## License

Hardydo Notes is released under the [MIT License](LICENSE).

It includes [swift-cmark](https://github.com/swiftlang/swift-cmark) (cmark-gfm), which is
BSD-2-Clause licensed; its notice ships inside the app as `swift-cmark-COPYING.txt`. Code in the
preview and HTML/PDF exports is coloured by [highlight.js](https://highlightjs.org) 11.9.0
(BSD-3-Clause), bundled in `Resources/highlight` with its notice, so the app never goes online.
