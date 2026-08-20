import SwiftUI

/// App entry — delegates to `MainShell` once the site index is loaded.
///
/// Everything route-related moved into [MainShell.swift](MainShell.swift) so
/// the split-view / stack-view fork lives in one place.
struct RootView: View {
    @StateObject private var progressStore = ProgressStore.shared
    @StateObject private var downloader = AssetDownloader.shared
    @ObservedObject private var settings = SettingsStore.shared
    @State private var siteIndex: SiteIndex?
    @State private var loadError: String?

    /// A purchased dark theme forces dark; otherwise the user's own preference.
    private var effectiveColorScheme: ColorScheme? {
        if progressStore.equippedThemeData?.isDark == true { return .dark }
        return settings.appearance.colorScheme
    }

    var body: some View {
        Group {
            if let siteIndex {
                MainShell(
                    progressStore: progressStore,
                    downloader: downloader,
                    siteIndex: siteIndex
                )
            } else if let loadError {
                VStack(spacing: 12) {
                    Text("加载失败").duoFont(.subhead)
                    Text(loadError).duoFont(.caption).foregroundStyle(DuoColors.inkMuted)
                }
                .padding()
            } else {
                ProgressView("加载中…")
            }
        }
        // Rounded typeface app-wide: any Text that doesn't specify its own
        // `design:` inherits SF Rounded, so the whole app reads "Duolingo".
        .fontDesign(.rounded)
        // One opt-in appearance switch (light-first default); a purchased dark
        // theme (暗夜模式 / 曜石黑) wins over the preference while equipped.
        .preferredColorScheme(effectiveColorScheme)
        .tint(DuoColors.primary)
        .onAppear { progressStore.applyEquippedTheme() }
        .onChange(of: progressStore.equippedTheme) { _, _ in
            progressStore.applyEquippedTheme()
        }
        // First-run onboarding covers the shell until the learner picks a
        // book and a daily goal.
        .overlay {
            if let siteIndex, !progressStore.hasCompletedOnboarding {
                OnboardingView(progressStore: progressStore, siteIndex: siteIndex, onDone: {})
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: progressStore.hasCompletedOnboarding)
        .task {
            SeedInstaller.installIfNeeded()
            do {
                siteIndex = try DataLoader.shared.loadSiteIndex()
            } catch {
                loadError = String(describing: error)
            }
            _ = downloader.loadCachedManifest()
            Task { try? await downloader.loadManifest() }
            // Refresh the rolling reminder window so a lapsed learner keeps
            // getting evening nudges (no-op unless the toggle is on).
            NotificationService.shared.rescheduleStreakReminder(
                streak: progressStore.reminderStreak,
                studiedToday: progressStore.studiedToday
            )
        }
    }
}

/// Book list for one grade — used by the iPad sidebar's "按年级" items to show
/// a persistent book list on the detail column (the bookList route).
struct BookListView: View {
    let grade: Int
    let siteIndex: SiteIndex
    @Binding var path: [AppRoute]

    var body: some View {
        List(siteIndex.books.filter { $0.grade == grade }, id: \.id) { book in
            Button {
                path.append(.bookDetail(bookId: book.id))
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.fullName).font(.headline)
                    Text("\(book.unitsCount) 单元 · \(book.lessonsCount) 节小课")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("\(grade) 年级")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    RootView()
}
