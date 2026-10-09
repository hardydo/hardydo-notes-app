import AppKit
import HardydoNotesCore

extension AppModel {
    var findInputs: FindInputs? {
        guard let note = selectedNote else { return nil }
        return FindInputs(note: note.id, revision: store.revision(of: note.id), query: find.query, options: searchOptions)
    }

    /// Brings the matches up to date with the open note; true when they are, false when something newer took over.
    @discardableResult
    func refreshFind() async -> Bool {
        guard find.isShown, let note = selectedNote, let inputs = findInputs else { return false }
        await find.search(inputs, in: note.body)
        return findInputs.map(find.isCurrent) ?? false
    }

    func openFind(replace: Bool = false) {
        editor.commit()
        guard selectedNote != nil else { return }
        leavePreview(to: .split)
        if let selected = editor.selectedText, !selected.contains(where: \.isNewline), selected.count <= 200 {
            find.query = selected
        }
        find.isShown = true
        if replace { find.showsReplace = true }
        find.focusRequest += 1
        selectMatch(atOrAfter: editor.selectedRange?.location ?? 0)
    }

    func closeFind() {
        find.close()
        editor.focus()
    }

    // The field also hands back its unchanged text, on focus for one, which must not move the selection.
    func setFindQuery(_ query: String) {
        guard query != find.query else { return }
        find.query = query
        selectMatch(atOrAfter: editor.selectedRange?.location ?? 0)
    }

    func setSearchOptions(_ options: SearchOptions) {
        searchOptions = options
        if find.isShown { selectMatch(atOrAfter: editor.selectedRange?.location ?? 0) }
    }

    func findNext(forward: Bool = true) {
        editor.commit()
        guard find.isShown else { return openFind() }
        find.perform { [self] in
            guard await refreshFind() else { return }
            let selected = editor.selectedRange ?? NSRange(location: 0, length: 0)
            if let target = TextSearch.nextMatch(in: find.ranges, from: selected, forward: forward) { show(target) }
        }
    }

    private func selectMatch(atOrAfter location: Int) {
        find.perform { [self] in
            guard await refreshFind() else { return }
            guard let target = TextSearch.firstMatch(in: find.ranges, atOrAfter: location) else {
                find.current = nil
                return
            }
            show(target)
        }
    }

    private func show(_ range: NSRange) {
        find.current = range
        editor.reveal(range)
    }

    var canReplace: Bool {
        canEditText && !find.ranges.isEmpty
    }

    func replaceCurrent() {
        editor.commit()
        find.perform { [self] in
            guard await refreshFind(), canReplace, let note = selectedNote,
                  let expression = try? TextSearch.expression(for: find.query, options: searchOptions) else { return }
            guard let range = find.current, find.ranges.contains(range) else { return findNext() }
            guard let replacement = TextSearch.replacement(for: range, in: note.body, expression: expression, template: find.replaceText, options: searchOptions),
                  editor.replace(range, with: replacement) else { return }
            editor.commit()
            selectMatch(atOrAfter: range.location + (replacement as NSString).length)
        }
    }

    func replaceAll() {
        editor.commit()
        find.perform { [self] in
            guard await refreshFind(), canReplace, let note = selectedNote,
                  let expression = try? TextSearch.expression(for: find.query, options: searchOptions) else { return }
            let result = TextSearch.replacingAll(in: note.body, expression: expression, template: find.replaceText, options: searchOptions)
            guard result.count > 0, editor.replaceAll(with: result.text) else { return }
            editor.commit()
            find.current = nil
        }
    }
}
