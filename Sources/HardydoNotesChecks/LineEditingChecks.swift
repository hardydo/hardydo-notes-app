import Foundation
import HardydoNotesCore

func runLineEditingChecks() {
    func apply(_ text: String, _ edit: TextEdit?) -> String {
        guard let edit else { return text }
        return (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }
    let text = "one\ntwo\nthree"
    let down = LineEditing.moveLines(text, selection: NSRange(location: 1, length: 0), .down)
    checkEqual(apply(text, down), "two\none\nthree", "move line down")
    checkEqual(down?.selection.location, 5, "the caret follows a moved line")
    checkEqual(apply(text, LineEditing.moveLines(text, selection: NSRange(location: 9, length: 0), .up)), "one\nthree\ntwo", "move the last line up")
    check(LineEditing.moveLines(text, selection: NSRange(location: 0, length: 0), .up) == nil, "the first line cannot move up")
    checkEqual(apply(text, LineEditing.copyLines(text, selection: NSRange(location: 5, length: 0), .down)), "one\ntwo\ntwo\nthree", "copy line down")
    checkEqual(apply(text, LineEditing.copyLines(text, selection: NSRange(location: 9, length: 0), .down)), "one\ntwo\nthree\nthree", "copy the last line down")
    checkEqual(apply(text, LineEditing.deleteLines(text, selection: NSRange(location: 5, length: 0))), "one\nthree", "delete line")
    checkEqual(apply(text, LineEditing.deleteLines(text, selection: NSRange(location: 9, length: 0))), "one\ntwo", "delete the last line")
    func newline(_ text: String, _ selection: NSRange) -> String? {
        LineEditing.newlineKeepingIndent(text, selection: selection).map { apply(text, $0) }
    }
    checkEqual(newline("\titem", NSRange(location: 5, length: 0)), "\titem\n\t", "Return keeps a tab indent")
    checkEqual(newline("    item", NSRange(location: 8, length: 0)), "    item\n    ", "Return keeps a space indent")
    checkEqual(newline(" \t item", NSRange(location: 7, length: 0)), " \t item\n \t ", "Return keeps a mixed indent as it is")
    checkEqual(newline("item", NSRange(location: 4, length: 0)), nil, "Return on an unindented line is left to the editor")
    checkEqual(newline("  ab cd", NSRange(location: 4, length: 1)), "  ab\n  cd", "Return replaces the selection")
    checkEqual(newline("    item", NSRange(location: 2, length: 0)), "  \n    item", "Return inside the indent keeps only the part before the caret")
    checkEqual(LineEditing.newlineKeepingIndent("  ab", selection: NSRange(location: 4, length: 0))?.selection, NSRange(location: 7, length: 0),
               "the caret lands after the copied indent")
    let crlf = "one\r\ntwo\r\nthree"
    checkEqual(apply(crlf, LineEditing.moveLines(crlf, selection: NSRange(location: 1, length: 0), .down)), "two\r\none\r\nthree", "moving a CRLF line keeps CRLF")
    checkEqual(apply(crlf, LineEditing.moveLines(crlf, selection: NSRange(location: 11, length: 0), .up)), "one\r\nthree\r\ntwo", "moving the last CRLF line up keeps CRLF")
    checkEqual(LineEditing.moveLines(crlf, selection: NSRange(location: 1, length: 0), .down)?.selection.location, 6, "the caret follows a moved CRLF line")
    checkEqual(apply(crlf, LineEditing.copyLines(crlf, selection: NSRange(location: 11, length: 0), .down)), "one\r\ntwo\r\nthree\r\nthree", "copying the last CRLF line borrows CRLF")
    checkEqual(apply(crlf, LineEditing.deleteLines(crlf, selection: NSRange(location: 11, length: 0))), "one\r\ntwo", "deleting the last CRLF line removes the whole CRLF before it")
    checkEqual(apply(crlf, LineEditing.toggleComment(crlf, selection: NSRange(location: 0, length: 8), language: .javascript)), "// one\r\n// two\r\nthree",
               "commenting CRLF lines keeps CRLF")
    checkEqual(apply("a\r\n\r\nb", LineEditing.indent("a\r\n\r\nb", selection: NSRange(location: 0, length: 7), unit: "  ")), "  a\r\n\r\n  b",
               "indenting skips a blank CRLF line as it skips a blank LF line")
    let cr = "one\rtwo\rthree"
    checkEqual(apply(cr, LineEditing.moveLines(cr, selection: NSRange(location: 1, length: 0), .down)), "two\rone\rthree", "moving a CR line keeps CR")
    checkEqual(apply(cr, LineEditing.indent(cr, selection: NSRange(location: 0, length: 6), unit: "\t")), "\tone\r\ttwo\rthree", "indenting CR lines indents each line")
    let indented = "  item"
    let below = LineEditing.insertLine(indented, selection: NSRange(location: 3, length: 0), .down)
    checkEqual(apply(indented, below), "  item\n  ", "insert line below keeps indentation")
    checkEqual(apply(indented, LineEditing.insertLine(indented, selection: NSRange(location: 3, length: 0), .up)), "  \n  item", "insert line above")
    checkEqual(apply(text, LineEditing.indent(text, selection: NSRange(location: 0, length: 6), unit: "    ")), "    one\n    two\nthree", "indent selected lines")
    checkEqual(apply("    one\n  two", LineEditing.outdent("    one\n  two", selection: NSRange(location: 0, length: 13), unit: "    ")), "one\ntwo", "outdent removes up to one unit")
    checkEqual(LineEditing.indentUnit(for: "a\n\tb"), "\t", "tab indented text indents with tabs")
    let code = "let a = 1\n  let b = 2"
    let commented = apply(code, LineEditing.toggleComment(code, selection: NSRange(location: 0, length: 12), language: .swift))
    checkEqual(commented, "// let a = 1\n//   let b = 2", "comment lines at their shared indentation")
    checkEqual(apply(commented, LineEditing.toggleComment(commented, selection: NSRange(location: 0, length: 14), language: .swift)), code, "uncomment restores the lines")
    checkEqual(apply("# Title", LineEditing.toggleComment("# Title", selection: NSRange(location: 0, length: 0), language: .markdown)), "<!-- # Title -->", "markdown comments are HTML comments")
    checkEqual(LineEditing.selectLine(text, selection: NSRange(location: 1, length: 0)), NSRange(location: 0, length: 4), "select line")
    checkEqual(LineEditing.selectLine(text, selection: NSRange(location: 0, length: 4)), NSRange(location: 0, length: 8), "select line again adds the next line")
    checkEqual(LineEditing.location(ofLine: 3, in: text), 8, "go to line")
    checkEqual(LineEditing.location(ofLine: 99, in: text), 8, "go to a line past the end lands on the last line")
}
