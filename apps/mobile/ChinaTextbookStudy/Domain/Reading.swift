import Foundation

/// 阅读完成 id 的单一事实源 —— packages/core/src/reading.ts 的 Swift 镜像。
///
/// 背景：历史上两端各写各的 key，`completedReadings` 的键空间零交集 ——
///   web ：`passage-{passageId}-listen` / `passage-{passageId}-followup` / `story-{storyId}`
///   iOS ：`{passageId}`（听读）/ `{passageId}-followup`（跟读）/ `{storyId}`（故事）
/// 导致备份互通时阅读进度 100% 失配（导入后全部显示未读，还能重复领 XP）。
///
/// 现在统一为 `reading:{kind}:{rawId}`，rawId 是数据层原始 id
/// （`Passage.id` / `Story.id`，形如 `chinese-g1up-p3`、`chinese-g3up-s1`）。
///
/// ⚠️ 规则必须与 core `readingId` / `normalizeReadingId` / `normalizeReadingMap`
/// 逐行一致；任何一端改动都会让备份互通再次错位。
enum Reading {

    /// 三种阅读活动：课文听读 / 课文跟读 / 故事阅读（含测验）。
    enum Kind: String, CaseIterable, Hashable {
        case listen
        case followup
        case story
    }

    /// 规范键前缀。
    static let idPrefix = "reading"

    /// 规范阅读完成 id：`reading:{kind}:{rawId}`。
    static func id(_ kind: Kind, _ rawId: String) -> String {
        "\(idPrefix):\(kind.rawValue):\(rawId)"
    }

    /// 解析规范 id；不是规范格式（或 kind 未知 / rawId 为空）返回 nil。
    static func parse(_ id: String) -> (kind: Kind, rawId: String)? {
        let head = "\(idPrefix):"
        guard id.hasPrefix(head) else { return nil }
        let rest = id.dropFirst(head.count)
        guard let sep = rest.firstIndex(of: ":") else { return nil }
        let kindPart = String(rest[..<sep])
        let rawId = String(rest[rest.index(after: sep)...])
        guard !kindPart.isEmpty, !rawId.isEmpty, let kind = Kind(rawValue: kindPart) else { return nil }
        return (kind, rawId)
    }

    /// 故事 id 形态 `{bookId}-s{序号}`（如 `chinese-g3up-s1`）；课文是 `-p{序号}`，
    /// 两者不会互相误判。
    private static func looksLikeStoryId(_ id: String) -> Bool {
        guard let range = id.range(of: "-s", options: .backwards) else { return false }
        let digits = id[range.upperBound...]
        return !digits.isEmpty && digits.allSatisfy(\.isNumber)
    }

    /// 把历史 id 归一化成规范 id（已是规范 id 原样返回，**幂等**）。
    ///
    /// 消歧顺序（先长后短，避免前后缀互吃）：
    ///   1. `reading:{kind}:{raw}`   → 原样
    ///   2. `story-{raw}`            → story    （web 故事）
    ///   3. `passage-{raw}-followup` → followup （web 跟读）
    ///   4. `passage-{raw}-listen`   → listen   （web 听读）
    ///   5. `passage-{raw}`          → listen   （web 早期无后缀写法）
    ///   6. `{raw}-followup`         → followup （iOS 跟读）
    ///   7. 裸 `{raw}`               → 命中 `-s\d+` 判 story，否则判 listen
    ///
    /// 无法识别的空串返回空串，交给调用方丢弃。
    static func normalize(_ legacyId: String) -> String {
        let id = legacyId.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.isEmpty { return "" }
        if parse(id) != nil { return id }

        if id.hasPrefix("story-") {
            let raw = String(id.dropFirst("story-".count))
            return raw.isEmpty ? "" : self.id(.story, raw)
        }

        if id.hasPrefix("passage-") {
            var raw = String(id.dropFirst("passage-".count))
            var kind = Kind.listen
            if raw.hasSuffix("-followup") {
                raw = String(raw.dropLast("-followup".count))
                kind = .followup
            } else if raw.hasSuffix("-listen") {
                raw = String(raw.dropLast("-listen".count))
            }
            return raw.isEmpty ? "" : self.id(kind, raw)
        }

        if id.hasSuffix("-followup") {
            let raw = String(id.dropLast("-followup".count))
            return raw.isEmpty ? "" : self.id(.followup, raw)
        }

        return self.id(looksLikeStoryId(id) ? .story : .listen, id)
    }

    /// 整表归一化（iOS 本地存的是「已读 id 集合」，没有完成日期）。
    /// 空键丢弃、重复键去重，结果排序保证与遍历顺序无关。
    static func normalizeIds(_ ids: [String]) -> [String] {
        var out = Set<String>()
        for raw in ids {
            let key = normalize(raw)
            if !key.isEmpty { out.insert(key) }
        }
        return out.sorted()
    }

    /// 整表归一化（备份信封里的 id → 完成日期），镜像 core `normalizeReadingMap`。
    /// 多个历史键归到同一规范键时**保留较早的完成日期**（与遍历顺序无关）。
    static func normalizeMap(_ map: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for (rawKey, value) in map {
            let key = normalize(rawKey)
            if key.isEmpty { continue }
            if let prev = out[key] {
                out[key] = earlierCompletion(prev, value)
            } else {
                out[key] = value
            }
        }
        return out
    }

    /// 两个完成时间取较早的一个（空串视作「未知」，永远输给非空）。
    private static func earlierCompletion(_ a: String, _ b: String) -> String {
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        let da = String(a.prefix(10))
        let db = String(b.prefix(10))
        if da != db { return da < db ? a : b }
        return a <= b ? a : b
    }
}
