import Foundation
import HardydoNotesCore

func runGroupChecks() {
    let notes = (0..<5).map { Note(body: "n\($0)") }
    func layout(_ groups: NoteGroups, _ list: [Note] = notes) -> [String] {
        groups.entries(for: list).map { entry in
            switch entry {
            case .note(let note): note.body
            case .group(let group, let members): "\(group.name)[\(members.map(\.body).joined(separator: ","))]"
            }
        }
    }

    var groups = NoteGroups()
    checkEqual(layout(groups), ["n0", "n1", "n2", "n3", "n4"], "without groups every note is listed on its own")

    var placing = NoteGroups()
    let trip = placing.create(name: "", with: notes[0].id)
    checkEqual(placing.group(trip)?.displayName, "Group", "a group without a name shows as Group")
    check(placing.insertionIndex(joining: trip, for: notes[0].id, in: notes) == nil, "the only note of a group stays put")
    placing.add(notes[2].id, to: trip)
    let move = placing.insertionIndex(joining: trip, for: notes[4].id, in: notes)
    checkEqual(move.map { [$0.from, $0.toOffset] }, [4, 3], "a note joining a group moves to just after its last note")

    let work = groups.create(name: "Work", with: notes[1].id)
    groups.add(notes[3].id, to: work)
    checkEqual(layout(groups), ["n0", "Work[n1,n3]", "n2", "n4"], "a group sits at its first note and gathers its notes in list order")
    checkEqual(groups.group(of: notes[3].id)?.name, "Work", "a note knows its group")

    let home = groups.create(name: "Home", with: notes[4].id)
    check(groups.group(home)?.color != groups.group(work)?.color, "a new group takes an unused colour")

    groups.update(work) { $0.isCollapsed = true }
    checkEqual(groups.visibleNotes(notes).map(\.body), ["n0", "n2", "n4"], "notes in a collapsed group are skipped by keyboard navigation")
    checkEqual(groups.orderedNotes(notes).map(\.body), ["n0", "n1", "n3", "n2", "n4"], "the full order still places notes of a collapsed group")

    groups.add(notes[4].id, to: work)
    check(groups.group(home) == nil, "moving the last note out of a group removes the empty group")

    groups.remove(notes[1].id)
    checkEqual(layout(groups), ["n0", "n1", "n2", "Work[n3,n4]"], "a note taken out of a group is listed on its own again")

    groups.prune(keeping: Set(notes.prefix(4).map(\.id)))
    checkEqual(layout(groups, Array(notes.prefix(4))), ["n0", "n1", "n2", "Work[n3]"], "deleted notes are forgotten")

    groups.ungroup(work)
    checkEqual(layout(groups), ["n0", "n1", "n2", "n3", "n4"], "ungrouping keeps every note")
    check(groups.groups.isEmpty, "ungrouping removes the group")

    var pins = NoteGroups()
    let pinned = pins.create(name: "Pinned", with: notes[3].id)
    pins.update(pinned) { $0.isPinned = true }
    checkEqual(layout(pins), ["Pinned[n3]", "n0", "n1", "n2", "n4"], "a pinned group moves to the top")
    var listed = notes
    listed[4].isPinned = true
    listed.insert(listed.remove(at: 4), at: 0)
    checkEqual(layout(pins, listed), ["n4", "Pinned[n3]", "n0", "n1", "n2"], "pinned notes and pinned groups share the top, in list order")
    var unpinnedGroup = NoteGroups()
    unpinnedGroup.create(name: "Plain", with: listed[0].id)
    unpinnedGroup.add(notes[1].id, to: unpinnedGroup.groups[0].id)
    checkEqual(layout(unpinnedGroup, listed), ["n0", "Plain[n4,n1]", "n2", "n3"], "a pinned note inside an unpinned group no longer lifts the group")
    var full = NoteGroups()
    let pair = full.create(name: "Pair", with: notes[0].id)
    full.add(notes[1].id, to: pair)
    var pinnedNotes = notes
    pinnedNotes[0].isPinned = true
    full.pinIfAllPinned(groupOf: notes[0].id, in: pinnedNotes)
    check(full.group(pair)?.isPinned == false, "a group with an unpinned note stays unpinned")
    pinnedNotes[1].isPinned = true
    full.pinIfAllPinned(groupOf: notes[1].id, in: pinnedNotes)
    check(full.group(pair)?.isPinned == true, "pinning the last unpinned note pins its group")
    let legacy = #"{"groups":[{"id":"6B1C1E44-8F4B-4D3A-9E58-1F7E2A3C9D10","name":"Old","color":"teal","isCollapsed":false}],"membership":[]}"#
    checkEqual((try? JSONDecoder().decode(NoteGroups.self, from: Data(legacy.utf8)))?.groups.first?.isPinned, false, "groups saved before pinning still load")

    var saved = NoteGroups()
    saved.create(name: "Saved", with: notes[0].id)
    let decoded = (try? JSONEncoder().encode(saved)).flatMap { try? JSONDecoder().decode(NoteGroups.self, from: $0) }
    checkEqual(decoded, saved, "groups survive saving and loading")
}
