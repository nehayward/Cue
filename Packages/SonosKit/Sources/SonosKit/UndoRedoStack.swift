import Foundation

/// A minimal undo/redo history. Pushing a new entry clears the redo history; `undo()` moves the
/// most recent entry from the undo stack to the redo stack, and `redo()` moves it back. The entry
/// type is opaque (it typically carries closures that apply/reverse an edit), so this stays a pure
/// value type that's trivial to test.
public struct UndoRedoStack<Entry> {
    public private(set) var undoEntries: [Entry] = []
    public private(set) var redoEntries: [Entry] = []

    public init() {}

    public var canUndo: Bool { !undoEntries.isEmpty }
    public var canRedo: Bool { !redoEntries.isEmpty }

    /// Records a new entry, invalidating any redo history.
    public mutating func push(_ entry: Entry) {
        undoEntries.append(entry)
        redoEntries.removeAll()
    }

    /// Moves the most recent undo entry onto the redo stack and returns it (nil if nothing to undo).
    public mutating func undo() -> Entry? {
        guard let entry = undoEntries.popLast() else { return nil }
        redoEntries.append(entry)
        return entry
    }

    /// Moves the most recent redo entry back onto the undo stack and returns it (nil if nothing to redo).
    public mutating func redo() -> Entry? {
        guard let entry = redoEntries.popLast() else { return nil }
        undoEntries.append(entry)
        return entry
    }

    public mutating func removeAll() {
        undoEntries.removeAll()
        redoEntries.removeAll()
    }
}
