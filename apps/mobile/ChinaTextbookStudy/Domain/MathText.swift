import Foundation

/// 数学公式的纯文本渲染 — iOS 侧对照 apps/web 的 MathText.tsx（KaTeX）。
///
/// 题库里大量题干/选项/答案含 `$...$` 行内 LaTeX（如 "$2 \times 3 = 6$"、
/// "$\frac{1}{5}$"）。App 是纯单机、零依赖，所以不引入 WebView/KaTeX，
/// 而是把常见 LaTeX 映射成 Unicode 数学符号后交给普通 `Text` 显示：
///
///   - `\times`→×、`\div`→÷、`\le`→≤、`\bigcirc`→◯ … 等符号命令
///   - `\frac{1}{5}` → ¹⁄₅（纯数字用上标 + U+2044 分数斜线 + 下标）
///     非纯数字退化为 a/b
///   - `x^2` → x²、`a_1` → a₁
///   - 未识别的 `\命令` 保底去掉反斜杠原样输出
///
/// **只用于显示**：TTS 路径与判分（`Grade.gradeAnswer` 读原始字符串）
/// 一律不要经过这里。
enum MathText {

    /// 把含 `$...$`（或 `$$...$$`）的字符串渲染成可直接显示的纯文本。
    /// 非公式段（中文语句混排）原样保留；`$` 不成对时剩余部分原样输出。
    static func render(_ text: String) -> String {
        // 快路径：绝大多数语文题干没有 $，直接返回避免逐字扫描。
        guard text.contains("$") else { return text }

        let chars = Array(text)
        var out = ""
        var i = 0
        while i < chars.count {
            if chars[i] == "$" {
                let isBlock = i + 1 < chars.count && chars[i + 1] == "$"
                let open = isBlock ? 2 : 1
                if let end = findClosingDollar(chars, from: i + open, isBlock: isBlock) {
                    out += renderMath(String(chars[(i + open)..<end]))
                    i = end + open
                } else {
                    // $ 不成对 — 当普通字符，剩余部分原样保留。
                    out += String(chars[i...])
                    break
                }
            } else {
                out.append(chars[i])
                i += 1
            }
        }
        return out
    }

    // MARK: - 公式段渲染

    /// 无参符号命令 → Unicode。
    private static let symbolCommands: [String: String] = [
        "times": "×", "div": "÷", "cdot": "·", "pm": "±",
        "le": "≤", "leq": "≤", "ge": "≥", "geq": "≥",
        "ne": "≠", "neq": "≠", "approx": "≈",
        "bigcirc": "◯", "square": "□", "triangle": "△",
        "angle": "∠", "pi": "π",
        "quad": " ", "qquad": " ",
    ]

    private static let superscripts: [Character: String] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
        "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾", "n": "ⁿ",
    ]

    private static let subscripts: [Character: String] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
        "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎",
    ]

    /// 渲染一段去掉 $ 定界符后的 LaTeX。
    private static func renderMath(_ latex: String) -> String {
        let chars = Array(latex)
        var out = ""
        var i = 0
        while i < chars.count {
            switch chars[i] {
            case "\\":
                i = renderCommand(chars, at: i + 1, into: &out)
            case "^", "_":
                let isSup = chars[i] == "^"
                let (arg, next) = parseScriptArgument(chars, at: i + 1)
                out += mapScript(arg, isSuperscript: isSup)
                i = next
            case "{", "}":
                // 裸花括号只做分组，不显示。
                i += 1
            default:
                out.append(chars[i])
                i += 1
            }
        }
        return out
    }

    /// 解析 `\` 之后的命令并追加渲染结果，返回消费到的位置。
    private static func renderCommand(_ chars: [Character], at start: Int, into out: inout String) -> Int {
        guard start < chars.count else { return start }

        // 单字符命令：\% \, \; \  \{ \}
        let c = chars[start]
        if !c.isLetter {
            switch c {
            case "%": out += "%"
            case ",", ";", " ": out += " "
            case "{": out += "{"
            case "}": out += "}"
            default: out.append(c)
            }
            return start + 1
        }

        // 字母命令：连续读字母作为命令名。
        var end = start
        while end < chars.count, chars[end].isLetter { end += 1 }
        let name = String(chars[start..<end])

        if name == "frac" {
            if let (numRaw, afterNum) = parseBraceGroup(chars, at: end),
               let (denRaw, afterDen) = parseBraceGroup(chars, at: afterNum) {
                out += renderFraction(numerator: renderMath(numRaw), denominator: renderMath(denRaw))
                return afterDen
            }
            // \frac 后没跟两个 {..}{..} — 保底去反斜杠输出。
            out += name
            return end
        }

        if let symbol = symbolCommands[name] {
            out += symbol
        } else {
            // 未识别命令保底去反斜杠输出，不吞内容。
            out += name
        }
        return end
    }

    /// 纯数字分数 → 上标数字 + U+2044（FRACTION SLASH）+ 下标数字，
    /// 如 ¹⁄₅、¹²⁄₃₅；否则退化为 a/b。
    private static func renderFraction(numerator: String, denominator: String) -> String {
        let isDigits: (String) -> Bool = { !$0.isEmpty && $0.allSatisfy { $0.isNumber && $0.isASCII } }
        if isDigits(numerator), isDigits(denominator) {
            let sup = numerator.map { superscripts[$0] ?? String($0) }.joined()
            let sub = denominator.map { subscripts[$0] ?? String($0) }.joined()
            return sup + "\u{2044}" + sub
        }
        return numerator + "/" + denominator
    }

    /// 解析 `^`/`_` 的参数：`{...}`（内部再走一遍渲染）或紧跟的单个字符。
    private static func parseScriptArgument(_ chars: [Character], at start: Int) -> (arg: String, next: Int) {
        guard start < chars.count else { return ("", start) }
        if chars[start] == "{" {
            if let (raw, next) = parseBraceGroup(chars, at: start) {
                return (renderMath(raw), next)
            }
            return ("", start + 1)
        }
        return (String(chars[start]), start + 1)
    }

    /// 参数全部可映射时转上/下标（x² / a₁），否则带回 ^/_ 原样输出。
    private static func mapScript(_ arg: String, isSuperscript: Bool) -> String {
        guard !arg.isEmpty else { return "" }
        let table = isSuperscript ? superscripts : subscripts
        var mapped = ""
        for ch in arg {
            guard let m = table[ch] else {
                return (isSuperscript ? "^" : "_") + arg
            }
            mapped += m
        }
        return mapped
    }

    /// 从 `start` 处解析一个 `{...}` 组（花括号可嵌套一层以上，按深度计数），
    /// 返回组内内容与右括号之后的位置。`start` 不是 `{` 或括号不配对时返回 nil。
    private static func parseBraceGroup(_ chars: [Character], at start: Int) -> (content: String, next: Int)? {
        guard start < chars.count, chars[start] == "{" else { return nil }
        var depth = 1
        var i = start + 1
        while i < chars.count {
            if chars[i] == "\\", i + 1 < chars.count {
                i += 2 // 跳过转义字符（如 \{），不参与配对
                continue
            }
            if chars[i] == "{" { depth += 1 }
            if chars[i] == "}" {
                depth -= 1
                if depth == 0 {
                    return (String(chars[(start + 1)..<i]), i + 1)
                }
            }
            i += 1
        }
        return nil
    }

    /// 找配对的 `$`（或 `$$`）。找不到返回 nil。
    private static func findClosingDollar(_ chars: [Character], from: Int, isBlock: Bool) -> Int? {
        var i = from
        while i < chars.count {
            if chars[i] == "$" {
                if !isBlock { return i }
                if i + 1 < chars.count, chars[i + 1] == "$" { return i }
            }
            i += 1
        }
        return nil
    }
}
