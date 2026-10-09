import Foundation
import HardydoNotesCore
import Testing

private func regions(_ text: String, _ language: ContentLanguage) -> [String] {
    CodeFolding.regions(in: text, language: language).map { "\($0.startLine)-\($0.endLine)" }
}

@Suite struct CodeFoldingTests {
    @Test func bracketsFoldJSONAndJavaScriptBlocks() {
        #expect(regions("{\n  \"a\": [\n    1,\n    2\n  ],\n  \"b\": \"{\"\n}", .json) == ["0-5", "1-3"], "JSON objects and arrays fold, closing lines stay visible")
        #expect(regions("function a() {\n  // }\n  const s = \"}\";\n  return 1;\n}", .javascript) == ["0-3"], "brackets in comments and strings are ignored")
        #expect(regions("const a = { b: 1 };\nlet c = [\n];", .javascript) == [], "one-line and empty blocks do not fold")
    }

    @Test func indentationFoldsPythonYAMLAndShell() {
        #expect(regions("def f(x):\n    if x:\n        return 1\n\n    return 2\n\nprint(f(1))", .python) == ["0-4", "1-2"], "Python folds by indentation, trailing blank lines stay outside")
        #expect(regions("a:\n  b: 1\n  c:\n    - d\ne: 2", .yaml) == ["0-3", "2-3"], "YAML folds by indentation")
        #expect(regions("if [ -n \"$1\" ]; then\n\techo hi\nfi", .shell) == ["0-1"], "tabs count as indentation")
    }

    @Test func markdownHeadingsAndFencesFold() {
        #expect(regions("# A\ntext\n## B\nmore\n\n# C\n```js\nx\ny\n```\nend", .markdown) == ["0-3", "2-3", "5-10", "6-9"], "Markdown headings fold to the next heading of the same level; a fence folds through its closing line")
    }

    @Test func emptyTextHasNoRegions() {
        #expect(regions("", .json) == [], "empty text has no regions")
    }

    @Test func bracketsInKeysAndShorterFencesDoNotBreakPairing() {
        #expect(regions("{\n  \"a[\": [\n    1\n  ],\n  \"b\": 2\n}", .json) == ["0-4", "1-2"], "a bracket inside a JSON key does not break pairing")
        #expect(regions("````md\n```js\nx\n```\n````\nend", .markdown) == ["0-4"], "a longer fence is not closed by a shorter one inside it")
    }

    @Test func caseClausesFoldToTheirLastStatement() {
        #expect(regions("switch (t) {\n  case \"a\":\n    return 1;\n  case \"b\":\n  case \"c\":\n    x();\n    y();\n\n  default:\n    z();\n}", .javascript) == ["0-9", "1-2", "4-6", "8-9"], "case clauses fold to their last statement; empty clauses do not fold")
        #expect(regions("switch x {\ncase .a:\n    f()\n    g()\ndefault:\n    h()\n}", .swift) == ["0-5", "1-3", "4-5"], "Swift case clauses fold")
    }

    @Test func importsCommentRunsAndTemplateStringsFold() {
        #expect(regions("import a from \"a\";\nimport {\n  b,\n} from \"b\";\n\n// one\n// two\nconst x = 1;\n/*\n block\n*/\n// #region tools\nconst y = 2;\n// #endregion", .typescript) == ["0-3", "1-2", "5-6", "8-10", "11-13"], "imports, line comment runs, block comments and regions fold")
        #expect(regions("const s = `a\nb\nc`;", .javascript) == ["0-1"], "a template string folds with its closing line visible")
    }

    @Test func offSideBlocksAndRegionMarkersFold() {
        #expect(regions("a\n  b\n\nc", .plainText) == ["0-2"], "indentation blocks keep trailing blank lines outside off-side languages")
        #expect(regions("# region x\na = 1\nb = 2\n# endregion", .python) == ["0-3"], "region markers fold through the end marker")
    }

    @Test func markdownListsTablesQuotesAndSetextHeadingsFold() {
        #expect(regions("- a\n  b\n- c\n\n| h | i |\n| - | - |\n| 1 | 2 |\n\n> q\n> r", .markdown) == ["0-1", "4-6", "8-9"], "multi-line list items, tables and block quotes fold")
        #expect(regions("Title\n=====\ntext\n\nSub\n---\nmore", .markdown) == ["0-6", "4-6"], "setext headings fold like ATX headings")
        #expect(regions("<!-- #region -->\na\n<!-- #endregion -->", .markdown) == ["0-2"], "Markdown region comments fold")
    }

    @Test func shiftKeepsRegionsAboveStretchesEnclosingOnesAndMovesTheRest() {
        let folds = [0: 9, 2: 4, 6: 8, 12: 15]
        let shifted = CodeFolding.shiftRegions(folds, editedLines: 5, through: 5, lineDelta: 2)
        #expect(shifted == [0: 11, 2: 4, 8: 10, 14: 17], "regions above stay, an enclosing one stretches and those below move")
    }

    @Test func regionStartingOnAnEditedLineIsDropped() {
        let folds = [0: 9, 2: 4, 6: 8, 12: 15]
        #expect(CodeFolding.shiftRegions(folds, editedLines: 2, through: 3, lineDelta: -1) == [0: 8, 5: 7, 11: 14], "a region starting on an edited line is dropped")
    }

    @Test func regionEndingOnAnEditedLineIsDropped() {
        let folds = [0: 9, 2: 4, 6: 8, 12: 15]
        #expect(CodeFolding.shiftRegions(folds, editedLines: 8, through: 8, lineDelta: 0) == [0: 9, 2: 4, 12: 15], "a region ending on an edited line is dropped")
    }
}
