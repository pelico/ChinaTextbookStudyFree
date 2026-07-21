import SwiftUI

/// Plain lesson list for one book — placeholder for the eventual PathMap.
/// This phase aims for a working learning loop, not the Duolingo-style art.
/// The PathMap visual treatment is deferred to Phase 6/7.
struct BookDetailView: View {
    let bookId: String
    @ObservedObject var progressStore: ProgressStore
    @ObservedObject var downloader: AssetDownloader
    @Binding var path: [AppRoute]

    @State private var outline: Outline?
    @State private var loadError: String?
    @State private var lessons: [LessonRow] = []

    /// Lightweight row metadata derived from outline + on-disk lesson files.
    struct LessonRow: Identifiable, Hashable {
        let id: String
        let title: String
        let unitNumber: Int
        let unitTitle: String
        let kpIndex: Int
        let kpTotal: Int
        let questionCount: Int
    }

    var body: some View {
        Group {
            if let outline {
                content(outline: outline)
            } else if let loadError {
                VStack(spacing: 12) {
                    Image(systemName: "tray.and.arrow.down").font(.largeTitle).foregroundStyle(.secondary)
                    Text("这本书还没下载").font(.headline)
                    Text(loadError).font(.footnote).foregroundStyle(.secondary)
                    if let entry = downloader.manifest?.books.first(where: { $0.bookId == bookId }) {
                        BookDownloadCard(entry: entry, downloader: downloader) { load() }
                            .padding(.horizontal, 24)
                    }
                }
                .padding()
            } else {
                ProgressView()
            }
        }
        .navigationTitle(outline?.textbook ?? bookId)
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
    }

    private func content(outline: Outline) -> some View {
        ZStack(alignment: .top) {
            DuoColors.darkBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Side entries (stories/reading) at top — dark themed
                HStack(spacing: 12) {
                    sideEntry(label: "课文听读", icon: "text.book.closed.fill", tint: DuoColors.secondary) {
                        path.append(.reading(bookId: bookId))
                    }
                    sideEntry(label: "课外故事", icon: "book.closed.fill", tint: DuoColors.beetle) {
                        path.append(.stories(bookId: bookId))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)

                // Snake-shaped PathMap
                PathMapView(lessons: buildPathNodes()) { node in
                    path.append(.lesson(bookId: bookId, lessonId: node.id))
                }
            }
        }
    }

    private func sideEntry(label: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(DuoColors.darkInk)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(DuoColors.darkSurface, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(DuoColors.darkSurfaceAlt, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
    }

    /// Convert lesson rows into PathMapNodes with status (completed/current/locked).
    private func buildPathNodes() -> [PathMapNode] {
        var foundCurrent = false
        return lessons.map { row in
            let stars = progressStore.stars(for: row.id) ?? 0
            let isCompleted = stars > 0
            let status: LessonStatus
            if isCompleted {
                status = .completed
            } else if !foundCurrent {
                status = .current
                foundCurrent = true
            } else {
                status = .locked
            }
            return PathMapNode(
                id: row.id,
                title: row.title,
                unitNumber: row.unitNumber,
                unitTitle: row.unitTitle,
                status: status,
                stars: stars
            )
        }
    }

    // MARK: - Loading

    private func load() {
        do {
            let outline = try DataLoader.shared.loadOutline(bookId: bookId)
            self.outline = outline
            self.lessons = expandLessons(outline: outline)
            self.loadError = nil
        } catch {
            self.loadError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    private func expandLessons(outline: Outline) -> [LessonRow] {
        var rows: [LessonRow] = []
        for unit in outline.units {
            for (i, kp) in unit.knowledgePoints.enumerated() {
                let lessonId = "\(bookId)-u\(unit.unitNumber)-kp\(i + 1)"
                // Try to peek at the file to get question count, but degrade gracefully.
                let count = (try? DataLoader.shared.loadLesson(bookId: bookId, lessonId: lessonId).questions.count) ?? 0
                rows.append(LessonRow(
                    id: lessonId,
                    title: kp.name,
                    unitNumber: unit.unitNumber,
                    unitTitle: unit.title,
                    kpIndex: i,
                    kpTotal: unit.knowledgePoints.count,
                    questionCount: count
                ))
            }
        }
        return rows
    }

}
