import Foundation

public enum GroupColor: String, Codable, CaseIterable, Sendable {
    case blue, pink, orchid, lavender, steel, teal, orange, gold, grey
}

public struct NoteGroup: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var color: GroupColor
    public var isCollapsed: Bool
    public var isPinned = false

    public var displayName: String { name.isEmpty ? "Group" : name }
}

extension NoteGroup {
    private enum CodingKeys: String, CodingKey {
        case id, name, color, isCollapsed, isPinned
    }

    // Groups saved before pinning existed have no isPinned.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        color = try values.decode(GroupColor.self, forKey: .color)
        isCollapsed = try values.decode(Bool.self, forKey: .isCollapsed)
        isPinned = try values.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }
}

enum EntryPlace {
    case note(Int)
    case group(NoteGroup, [Int])
}

public enum SidebarEntry: Identifiable {
    case note(Note)
    case group(NoteGroup, [Note])

    var isPinned: Bool {
        switch self {
        case .note(let note): note.isPinned
        case .group(let group, _): group.isPinned
        }
    }

    public var id: UUID {
        switch self {
        case .note(let note): note.id
        case .group(let group, _): group.id
        }
    }
}

/// Groups only change how the sidebar lists notes; the notes themselves and their files are untouched.
public struct NoteGroups: Codable, Equatable, Sendable {
    public private(set) var groups: [NoteGroup] = []
    private var membership: [Note.ID: NoteGroup.ID] = [:]

    public init() {}

    public func group(_ id: NoteGroup.ID) -> NoteGroup? {
        groups.first { $0.id == id }
    }

    public func group(of note: Note.ID) -> NoteGroup? {
        membership[note].flatMap { group($0) }
    }

    /// A new group takes the first colour no other group uses.
    @discardableResult
    public mutating func create(name: String, with note: Note.ID) -> NoteGroup.ID {
        let used = Set(groups.map(\.color))
        let color = GroupColor.allCases.first { !used.contains($0) } ?? GroupColor.allCases[groups.count % GroupColor.allCases.count]
        let group = NoteGroup(id: UUID(), name: name, color: color, isCollapsed: false)
        groups.append(group)
        add(note, to: group.id)
        return group.id
    }

    public mutating func add(_ note: Note.ID, to group: NoteGroup.ID) {
        guard self.group(group) != nil else { return }
        membership[note] = group
        dropEmptyGroups()
    }

    public mutating func remove(_ note: Note.ID) {
        membership[note] = nil
        dropEmptyGroups()
    }

    public mutating func ungroup(_ group: NoteGroup.ID) {
        groups.removeAll { $0.id == group }
        membership = membership.filter { $0.value != group }
    }

    public mutating func update(_ id: NoteGroup.ID, _ change: (inout NoteGroup) -> Void) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        change(&groups[index])
    }

    /// Pins the group of this note once every note in it is pinned.
    public mutating func pinIfAllPinned(groupOf note: Note.ID, in notes: [Note]) {
        guard let group = group(of: note), !group.isPinned else { return }
        let members = notes.filter { membership[$0.id] == group.id }
        if members.allSatisfy(\.isPinned) { update(group.id) { $0.isPinned = true } }
    }

    public mutating func prune(keeping notes: Set<Note.ID>) {
        membership = membership.filter { notes.contains($0.key) }
        dropEmptyGroups()
    }

    /*
     A group shows where its first note is, so a note joining it moves next to the others instead of dragging the
     group along. Returns the list move for that, or nil when the group has no other note.
     */
    public func insertionIndex(joining group: NoteGroup.ID, for note: Note.ID, in notes: [Note]) -> (from: Int, toOffset: Int)? {
        guard let last = notes.lastIndex(where: { $0.id != note && membership[$0.id] == group }),
              let from = notes.firstIndex(where: { $0.id == note })
        else { return nil }
        return (from, last + 1)
    }

    private mutating func dropEmptyGroups() {
        let used = Set(membership.values)
        groups.removeAll { !used.contains($0.id) }
    }

    /// A group sits where its first note is in the list and gathers all its notes there, in list order; pinned groups and notes come first.
    public func entries(for notes: [Note]) -> [SidebarEntry] {
        entryPlaces(count: notes.count, id: { notes[$0].id }, isPinned: { notes[$0].isPinned }).map { place in
            switch place {
            case .note(let index): .note(notes[index])
            case .group(let group, let members): .group(group, members.map { notes[$0] })
            }
        }
    }

    /// The entries by place in the list, so a caller holding only ids lists them by the same rules.
    func entryPlaces(count: Int, id: (Int) -> Note.ID, isPinned: (Int) -> Bool) -> [EntryPlace] {
        var members: [NoteGroup.ID: [Int]] = [:]
        for index in 0..<count {
            if let group = membership[id(index)] { members[group, default: []].append(index) }
        }
        // Pinned notes are listed first, so a group that is not pinned itself sits at its first unpinned note.
        let anchors = Set(members.compactMap { group, places in
            self.group(group)?.isPinned == true ? places.first : (places.first { !isPinned($0) } ?? places.first)
        })
        var pinned: [EntryPlace] = []
        var unpinned: [EntryPlace] = []
        for index in 0..<count {
            guard let groupID = membership[id(index)], let group = group(groupID) else {
                if isPinned(index) { pinned.append(.note(index)) } else { unpinned.append(.note(index)) }
                continue
            }
            guard anchors.contains(index) else { continue }
            let entry = EntryPlace.group(group, members[groupID] ?? [])
            if group.isPinned { pinned.append(entry) } else { unpinned.append(entry) }
        }
        return pinned + unpinned
    }

    /// Notes in sidebar order, including those inside collapsed groups.
    public func orderedNotes(_ notes: [Note]) -> [Note] {
        entries(for: notes).flatMap { entry -> [Note] in
            switch entry {
            case .note(let note): [note]
            case .group(_, let members): members
            }
        }
    }

    public func visibleNotes(_ notes: [Note]) -> [Note] {
        entries(for: notes).flatMap { entry -> [Note] in
            switch entry {
            case .note(let note): [note]
            case .group(let group, let members): group.isCollapsed ? [] : members
            }
        }
    }
}
