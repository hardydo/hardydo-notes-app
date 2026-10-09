# Probes

The probes drive the real app, `ContentView` together with `AppModel`, in an invisible window, and print timings or results.

`run-probe.sh` works like this:
- It copies the app sources and one probe `main` into a throwaway package outside the repo, by default in `$TMPDIR/hardydo-notes-probe`; `HARDYDO_PROBE_DIR` overrides the location.
- It builds that package in release and runs it.

Every probe keeps its notes, groups and preferences in its own temporary folder, so your real notes are never read or written.

```bash
zsh Tools/probes/run-probe.sh Tools/probes/<probe>.swift [arguments]
```

| Probe | What it checks | Arguments |
|---|---|---|
| `perf-probe.swift` | Measures the following at 1,000 notes, plus a 25,000-line note:<br>• launch layout<br>• note and tab switches<br>• keystrokes<br>• scrolling<br>• split view<br>• sidebar drag start, frame and drop<br>• autoscroll<br>• global search | Note count (default `1000`); `PROBE_TABLOOP=1` or `PROBE_SEARCHLOOP=1` to loop one part for a profiler |
| `pause-probe.swift` | The stall after a typing pause, on 1-2 MB notes | `md` (default), `json`, `json400` or `vi`; then `split`, `find` or `reads` |
| `drag-probe.swift` | Drags every note through the sidebar and reports any gap, or half of a gap, it cannot reach; `shot` saves pictures of the lifted row | `audit` (default), `top` (a group first), or `shot <folder>` |
| `session-probe.swift` | Per-tab editors: switching, undo, changes made outside the app, closing tabs; tabs, language and sidebar highlight after a relaunch and on every tab switch | - |
| `data-safety-probe.swift` | That notes, groups and tabs survive saves, relaunches and broken files | - |
| `find-probe.swift` | Find, replace, Search All Notes and language detection through the real window | - |
| `editor-shot.swift` | Pictures of a JSON note before typing, right after Return, and once coloured again | `<folder>` |
| `toolbar-shot.swift` | Pictures of the toolbar for a Markdown note, a locked note, a JSON note and split view | `<folder>` |

When a probe ends, `ls ~/Library/Preferences | grep -c '^probe'` should print 0.
