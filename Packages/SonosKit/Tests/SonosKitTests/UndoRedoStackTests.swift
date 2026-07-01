import XCTest
@testable import SonosKit

final class UndoRedoStackTests: XCTestCase {

    func testStartsEmpty() {
        var stack = UndoRedoStack<Int>()
        XCTAssertFalse(stack.canUndo)
        XCTAssertFalse(stack.canRedo)
        XCTAssertNil(stack.undo())
        XCTAssertNil(stack.redo())
    }

    func testPushEnablesUndoAndClearsRedoState() {
        var stack = UndoRedoStack<Int>()
        stack.push(1)
        XCTAssertTrue(stack.canUndo)
        XCTAssertFalse(stack.canRedo)
        XCTAssertEqual(stack.undoEntries, [1])
    }

    func testUndoMovesEntryToRedoStack() {
        var stack = UndoRedoStack<Int>()
        stack.push(1)
        stack.push(2)

        XCTAssertEqual(stack.undo(), 2)
        XCTAssertTrue(stack.canRedo)
        XCTAssertEqual(stack.undoEntries, [1])
        XCTAssertEqual(stack.redoEntries, [2])

        XCTAssertEqual(stack.undo(), 1)
        XCTAssertFalse(stack.canUndo)
        XCTAssertEqual(stack.redoEntries, [2, 1])
    }

    func testRedoMovesEntryBackToUndoStack() {
        var stack = UndoRedoStack<Int>()
        stack.push(1)
        stack.push(2)
        _ = stack.undo() // -> 2
        _ = stack.undo() // -> 1

        XCTAssertEqual(stack.redo(), 1)
        XCTAssertEqual(stack.redo(), 2)
        XCTAssertFalse(stack.canRedo)
        XCTAssertEqual(stack.undoEntries, [1, 2])
    }

    func testNewPushInvalidatesRedoHistory() {
        var stack = UndoRedoStack<Int>()
        stack.push(1)
        stack.push(2)
        _ = stack.undo() // 2 is now redoable

        XCTAssertTrue(stack.canRedo)
        stack.push(3) // a fresh edit must discard the redo branch
        XCTAssertFalse(stack.canRedo)
        XCTAssertEqual(stack.undoEntries, [1, 3])
    }

    func testRemoveAllClearsBothStacks() {
        var stack = UndoRedoStack<Int>()
        stack.push(1)
        _ = stack.undo()
        stack.push(2)

        stack.removeAll()
        XCTAssertFalse(stack.canUndo)
        XCTAssertFalse(stack.canRedo)
        XCTAssertTrue(stack.undoEntries.isEmpty)
        XCTAssertTrue(stack.redoEntries.isEmpty)
    }

    func testRedoIsNoOpWithoutPriorUndo() {
        var stack = UndoRedoStack<Int>()
        stack.push(1)
        XCTAssertNil(stack.redo())
        XCTAssertEqual(stack.undoEntries, [1])
    }
}
