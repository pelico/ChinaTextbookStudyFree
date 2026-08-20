import SwiftUI

/// One book's learning path — snake-shaped PathMap with lesson nodes,
/// claimable chest slots (every 5th lesson per unit) and side entries for
/// stories / reading.
struct BookDetailView: View {
    let bookId: String
    @ObservedObject var progressStore: ProgressStore
    @ObservedObject var downloader: AssetDownloader
    @Binding var path: [AppRoute]

    @State private var outline: Outline?
    @State private var loadError: String?
    @State private var lessons: [PathLessonMeta] = []
    /// A path chest the learner tapped and is currently opening.
    @State private var activeChest: ActiveChest?

    private struct ActiveChest: Identifiable { let id: String }

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
                    if node.kind == .chest {
                        activeChest = ActiveChest(id: node.id)
                    } else {
                        path.append(.lesson(bookId: bookId, lessonId: node.id))
                    }
                }
            }
        }
        // Chest open modal — full-screen cover so the back button / tab bar
        // can't be tapped mid-claim; rolls the reward, then banks + marks it.
        .fullScreenCover(item: $activeChest) { chest in
            ChestModalView(
                onClaim: { gems in
                    progressStore.addGems(gems)
                    progressStore.claimChest(chest.id)
                },
                onDismiss: { activeChest = nil }
            )
            .presentationBackground(.clear)
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

    /// Lesson + chest nodes for the path (shared builder with the Home tab).
    private func buildPathNodes() -> [PathMapNode] {
        PathNodeBuilder.nodes(bookId: bookId, lessons: lessons, progressStore: progressStore)
    }

    // MARK: - Loading

    private func load() {
        do {
            let outline = try DataLoader.shared.loadOutline(bookId: bookId)
            self.outline = outline
            // Peek at each lesson file for its question count, degrading to 0.
            self.lessons = outline.pathLessonMetas(bookId: bookId) { lessonId in
                (try? DataLoader.shared.loadLesson(bookId: bookId, lessonId: lessonId).questions.count) ?? 0
            }
            self.loadError = nil
        } catch {
            self.loadError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

}
