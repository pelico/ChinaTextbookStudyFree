import XCTest
@testable import ChinaTextbookStudy

/// MathText.render — LaTeX → Unicode 显示转换（只影响显示，不影响判分）。
final class MathTextTests: XCTestCase {

    // MARK: - 种子包真实样例

    func testSeedGrade1Comparison() {
        XCTAssertEqual(MathText.render("$9 > 8$"), "9 > 8")
    }

    func testSeedTimes() {
        XCTAssertEqual(MathText.render(#"$2 \times 3 = 6$"#), "2 × 3 = 6")
    }

    func testSeedBigcircBlank() {
        XCTAssertEqual(MathText.render(#"$4 - 0 = \bigcirc$"#), "4 - 0 = ◯")
    }

    func testSeedFractionInSentence() {
        XCTAssertEqual(MathText.render(#"甲数比乙数多 $\frac{1}{5}$"#), "甲数比乙数多 ¹⁄₅")
    }

    func testSeedFractionOption() {
        XCTAssertEqual(MathText.render(#"$\frac{1}{4}$"#), "¹⁄₄")
    }

    // MARK: - 符号命令

    func testSymbolCommands() {
        XCTAssertEqual(MathText.render(#"$6 \div 2$"#), "6 ÷ 2")
        XCTAssertEqual(MathText.render(#"$a \cdot b$"#), "a · b")
        XCTAssertEqual(MathText.render(#"$x \pm 1$"#), "x ± 1")
        XCTAssertEqual(MathText.render(#"$3 \le 5$"#), "3 ≤ 5")
        XCTAssertEqual(MathText.render(#"$3 \leq 5$"#), "3 ≤ 5")
        XCTAssertEqual(MathText.render(#"$5 \ge 3$"#), "5 ≥ 3")
        XCTAssertEqual(MathText.render(#"$5 \geq 3$"#), "5 ≥ 3")
        XCTAssertEqual(MathText.render(#"$1 \ne 2$"#), "1 ≠ 2")
        XCTAssertEqual(MathText.render(#"$1 \neq 2$"#), "1 ≠ 2")
        XCTAssertEqual(MathText.render(#"$\pi \approx 3.14$"#), "π ≈ 3.14")
        XCTAssertEqual(MathText.render(#"$\square + \triangle$"#), "□ + △")
        XCTAssertEqual(MathText.render(#"$\angle A$"#), "∠ A")
        XCTAssertEqual(MathText.render(#"$50\%$"#), "50%")
    }

    func testSpacingCommands() {
        XCTAssertEqual(MathText.render(#"$1\quad 2$"#), "1  2")
        XCTAssertEqual(MathText.render(#"$1\,2$"#), "1 2")
    }

    func testNoSpaceAfterCommand() {
        // 命令名贪婪读取字母，后面直接跟数字也能正确断开。
        XCTAssertEqual(MathText.render(#"$2\times3$"#), "2×3")
    }

    // MARK: - 分数

    func testMultiDigitFraction() {
        XCTAssertEqual(MathText.render(#"$\frac{12}{35}$"#), "¹²⁄₃₅")
    }

    func testNonNumericFractionFallsBack() {
        XCTAssertEqual(MathText.render(#"$\frac{a}{b}$"#), "a/b")
    }

    func testNestedFraction() {
        // 嵌套：内层先渲染成 ¹⁄₂，外层非纯数字退化为 a/b。
        XCTAssertEqual(MathText.render(#"$\frac{\frac{1}{2}}{3}$"#), "¹⁄₂/3")
    }

    func testFractionWithCommandInside() {
        XCTAssertEqual(MathText.render(#"$\frac{1 \times 2}{3}$"#), "1 × 2/3")
    }

    func testFractionMidSentence() {
        XCTAssertEqual(
            MathText.render(#"把 $\frac{1}{2}$ 化成小数是多少？"#),
            "把 ¹⁄₂ 化成小数是多少？"
        )
    }

    // MARK: - 上下标

    func testSuperscript() {
        XCTAssertEqual(MathText.render("$x^2$"), "x²")
        XCTAssertEqual(MathText.render("$10^{3}$"), "10³")
        XCTAssertEqual(MathText.render("$10^{12}$"), "10¹²")
        XCTAssertEqual(MathText.render("$2^n$"), "2ⁿ")
    }

    func testSubscript() {
        XCTAssertEqual(MathText.render("$a_1$"), "a₁")
        XCTAssertEqual(MathText.render("$a_{12}$"), "a₁₂")
    }

    func testUnmappableScriptKeepsCaret() {
        // 无法映射的上标原样带回 ^，不吞内容。
        XCTAssertEqual(MathText.render("$x^a$"), "x^a")
    }

    // MARK: - 容错

    func testPlainChineseUnchanged() {
        XCTAssertEqual(MathText.render("小明有5个苹果，吃了2个，还剩几个？"), "小明有5个苹果，吃了2个，还剩几个？")
        XCTAssertEqual(MathText.render(""), "")
    }

    func testUnpairedDollarKeptLiterally() {
        XCTAssertEqual(MathText.render("价格是$5"), "价格是$5")
        XCTAssertEqual(MathText.render("$"), "$")
    }

    func testDoubleDollarBlock() {
        XCTAssertEqual(MathText.render(#"$$2 \times 3 = 6$$"#), "2 × 3 = 6")
    }

    func testUnknownCommandDropsBackslash() {
        XCTAssertEqual(MathText.render(#"$\foo$"#), "foo")
    }

    func testBareBracesAreGroupingOnly() {
        XCTAssertEqual(MathText.render("${12} + 3$"), "12 + 3")
    }

    func testMultipleMathSegments() {
        XCTAssertEqual(
            MathText.render(#"$\frac{1}{4}$ 和 $\frac{2}{4}$ 谁大？"#),
            "¹⁄₄ 和 ²⁄₄ 谁大？"
        )
    }

    // MARK: - 判分不受影响（渲染只做显示）

    func testGradingUsesRawStringsNotRendered() {
        let q = Question(
            id: 1, type: .choice, score: 10, difficulty: 1, knowledgePoint: "分数",
            question: #"下面哪个是 $\frac{1}{4}$？"#,
            options: [#"$\frac{1}{4}$"#, #"$\frac{1}{2}$"#, #"$\frac{3}{4}$"#, "$1$"],
            answer: "A", explanation: "", audio: nil
        )
        // 判分读原始 answer/letter，与显示转换无关。
        XCTAssertTrue(Grade.gradeAnswer(question: q, userAnswer: "A"))
        XCTAssertFalse(Grade.gradeAnswer(question: q, userAnswer: "B"))
    }
}
