import Foundation

extension Outline {
    /// Flatten units → knowledge points into path lesson metadata, using the
    /// same "\(bookId)-u\(unit)-kp\(i+1)" lesson-id convention as DataLoader.
    /// Shared by the path screen and the lesson result (chest slot lookup).
    func pathLessonMetas(
        bookId: String,
        questionCount: (String) -> Int = { _ in 0 }
    ) -> [PathLessonMeta] {
        var rows: [PathLessonMeta] = []
        for unit in units {
            for (i, kp) in unit.knowledgePoints.enumerated() {
                let lessonId = "\(bookId)-u\(unit.unitNumber)-kp\(i + 1)"
                rows.append(PathLessonMeta(
                    id: lessonId,
                    title: kp.name,
                    unitNumber: unit.unitNumber,
                    unitTitle: unit.title,
                    kpIndex: i,
                    kpTotal: unit.knowledgePoints.count,
                    questionCount: questionCount(lessonId)
                ))
            }
        }
        return rows
    }

    /// 每个单元的「单元挑战」槽位（Wave E1）。
    ///
    /// 只有 outline 声明了 `examLessonId` **且**本地课程文件确实可加载时才
    /// 产出——旧资产包（outline 更新了、lesson 文件还没跟上）里挑战节点
    /// 直接隐藏，不给孩子一个点了会报错的按钮。
    func examSlots(bookId: String) -> [ExamSlot] {
        units.compactMap { unit in
            guard let examId = unit.examLessonId else { return nil }
            guard let lesson = try? DataLoader.shared.loadLesson(bookId: bookId, lessonId: examId) else {
                return nil
            }
            return ExamSlot(
                lessonId: examId,
                title: lesson.title,
                unitNumber: unit.unitNumber,
                unitTitle: unit.title,
                questionCount: lesson.questions.count
            )
        }
    }
}

/// 单元挑战节点的元数据（outline + 本地 exam 课文件都齐才存在）。
struct ExamSlot: Hashable {
    /// "{bookId}-u{n}-exam"
    let lessonId: String
    /// 「第 n 单元挑战」
    let title: String
    let unitNumber: Int
    let unitTitle: String
    let questionCount: Int
}
