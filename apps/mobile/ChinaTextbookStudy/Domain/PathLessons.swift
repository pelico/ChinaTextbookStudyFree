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
}
