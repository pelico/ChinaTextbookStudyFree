import Foundation

/// 跳级测试（jump ahead）抽题纯函数 —— packages/core/src/jump.ts 的 Swift 镜像。
///
/// 规则（双端口径）：
///   - 从目标单元之前所有单元的课程题库里均匀抽 `testSize` 道题；
///   - 通过线 `passAccuracy`（正确率 ≥ 0.80）；
///   - 抽样是纯函数：同一 seed + 同一题库 → 同一结果；重试换 seed 即换一套题；
///   - 均匀 = 按课程轮转取题（round-robin），每节课被抽到的题数最多差 1；
///   - 题库不足 size 时全取（仍做确定性洗牌）。
///
/// 注意：跳级测试是合成会话，不写 completedLessons、不进错题本；通过后由
/// `ProgressStore.applyJumpUnlock` 批量标记之前未完成课程
/// completed{stars:1, accuracy:0.8}，不发 XP / 宝石。
enum Jump {

    /// 跳级测试题数。
    static let testSize = 15
    /// 跳级通过线（正确率 ≥ 0.80）。
    static let passAccuracy = 0.8

    /// 一节前置课程的题目来源。
    struct QuestionSource {
        let lessonId: String
        let questions: [Question]
    }

    /// 抽出的题目（保留来源课程 id，便于报错定位）。
    struct SampledQuestion: Hashable {
        let lessonId: String
        let question: Question
    }

    // MARK: - 确定性 RNG（镜像 jump.ts makeRng：SplitMix64 计数流 → [0,1)）

    private static func makeRng(_ seedStr: String) -> () -> Double {
        var state = League.djb2Hash(seedStr)
        return {
            state = state &+ 1
            // 取高 53 位构造 [0,1) 双精度
            return Double(League.mix64(state) >> 11) / 9_007_199_254_740_992.0
        }
    }

    /// 确定性 Fisher–Yates 洗牌。
    private static func shuffle<T>(_ arr: inout [T], rng: () -> Double) {
        guard arr.count > 1 else { return }
        for i in stride(from: arr.count - 1, through: 1, by: -1) {
            let j = Int(rng() * Double(i + 1))
            arr.swapAt(i, min(j, i))
        }
    }

    // MARK: - 抽题

    /// 从全部前置课程的题库均匀抽 `size` 道题。
    ///
    /// 保证：课程内按题目 id 去重；题库充足时各课程被抽题数最多相差 1；
    /// 可用题总数 ≤ size 时全部返回；同 (sources, size, seed) 输出完全一致。
    static func sampleQuestions(
        sources: [QuestionSource],
        size: Int = testSize,
        seed: String = "jump"
    ) -> [SampledQuestion] {
        guard size > 0 else { return [] }

        // 1. 每节课内部去重 + 各自确定性洗牌
        var groups: [[SampledQuestion]] = []
        for src in sources {
            var seen = Set<Int>()
            var group: [SampledQuestion] = []
            for q in src.questions where !seen.contains(q.id) {
                seen.insert(q.id)
                group.append(SampledQuestion(lessonId: src.lessonId, question: q))
            }
            guard !group.isEmpty else { continue }
            shuffle(&group, rng: makeRng("\(seed)#\(src.lessonId)"))
            groups.append(group)
        }

        let total = groups.reduce(0) { $0 + $1.count }
        let targetSize = min(size, total)
        guard targetSize > 0 else { return [] }

        // 2. 课程顺序确定性洗牌（避免总是第一单元占满名额）
        shuffle(&groups, rng: makeRng("\(seed)#groups"))

        // 3. 轮转取题：每轮从每节课取 1 道，直到取满
        var picked: [SampledQuestion] = []
        var round = 0
        while picked.count < targetSize {
            var tookAny = false
            for group in groups {
                if picked.count >= targetSize { break }
                if round < group.count {
                    picked.append(group[round])
                    tookAny = true
                }
            }
            if !tookAny { break }   // 兜底防死循环
            round += 1
        }

        // 4. 出题顺序整体再洗一次，避免同一课程的题总是相邻
        shuffle(&picked, rng: makeRng("\(seed)#order"))
        return picked
    }
}
