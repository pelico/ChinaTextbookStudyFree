import SwiftUI

/// Size-class-aware top-level layout.
///
/// - **Compact** (iPhone portrait) → one NavigationStack driven by `$path`,
///   root = HomeView.
/// - **Regular** (iPad, iPhone Pro Max landscape) → NavigationSplitView with
///   a persistent sidebar (grade + quick links) and a detail column that
///   owns its own navigation stack. Mirrors the commit `bff43ed` "桌面三栏"
///   intent for the Web side.
struct MainShell: View {
    @ObservedObject var progressStore: ProgressStore
    @ObservedObject var downloader: AssetDownloader
    let siteIndex: SiteIndex

    @Environment(\.horizontalSizeClass) private var hSize
    @State private var path: [AppRoute] = []
    @State private var selectedSidebar: SidebarItem? = .home
    @State private var activeTab: AppTab = .learn

    enum SidebarItem: Hashable, Identifiable {
        case home
        case grade(Int)
        case review
        case shop
        case profile
        case achievements
        var id: String {
            switch self {
            case .home: return "home"
            case .grade(let g): return "grade-\(g)"
            case .review: return "review"
            case .shop: return "shop"
            case .profile: return "profile"
            case .achievements: return "achievements"
            }
        }
    }

    var body: some View {
        if hSize == .regular {
            regularLayout
        } else {
            compactLayout
        }
    }

    /// Whether the tab bar should be hidden (immersive screens).
    private var hideTabBar: Bool {
        guard let last = path.last else { return false }
        switch last {
        case .lesson, .lessonResult, .reviewRunner, .storyReader, .passageReader, .reading:
            return true
        default:
            return false
        }
    }

    // MARK: - Compact (iPhone)

    @ViewBuilder
    private var compactLayout: some View {
        NavigationStack(path: $path) {
            compactTabRoot
                .navigationDestination(for: AppRoute.self) { route in
                    RouteView(
                        route: route,
                        progressStore: progressStore,
                        downloader: downloader,
                        siteIndex: siteIndex,
                        path: $path
                    )
                }
        }
        // Attach the tab bar as a bottom inset so every child ScrollView
        // reserves matching space — content never hides behind the bar.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !hideTabBar {
                BottomTabBar(activeTab: $activeTab, progressStore: progressStore)
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: hideTabBar)
        .onChange(of: activeTab) { _, _ in
            // Clear navigation stack when switching tabs.
            path.removeAll()
        }
    }

    @ViewBuilder
    private var compactTabRoot: some View {
        switch activeTab {
        case .learn:
            HomeView(
                progressStore: progressStore,
                downloader: downloader,
                siteIndex: siteIndex,
                path: $path
            )
        case .review:
            ReviewView(progressStore: progressStore, path: $path)
        case .shop:
            ShopView(progressStore: progressStore)
        case .profile:
            ProfileView(progressStore: progressStore, path: $path)
        }
    }

    // MARK: - Regular (iPad)

    @ViewBuilder
    private var regularLayout: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            NavigationStack(path: $path) {
                sidebarRootView
                    .navigationDestination(for: AppRoute.self) { route in
                        RouteView(
                            route: route,
                            progressStore: progressStore,
                            downloader: downloader,
                            siteIndex: siteIndex,
                            path: $path
                        )
                    }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedSidebar) {
            Section("主菜单") {
                row(.home, label: "学习", icon: "house.fill", tint: DuoColors.primary)
                row(.review, label: "错题本", icon: "book.fill", tint: DuoColors.fox)
                row(.shop, label: "商店", icon: "bag.fill", tint: DuoColors.beetle)
                row(.profile, label: "我的", icon: "person.crop.circle.fill", tint: DuoColors.secondary)
                row(.achievements, label: "成就墙", icon: "rosette", tint: .purple)
            }
            Section("按年级") {
                ForEach(1...6, id: \.self) { grade in
                    row(.grade(grade), label: "\(grade) 年级", icon: "books.vertical.fill", tint: .green)
                }
            }
        }
        .navigationTitle("课本学习")
        .onChange(of: selectedSidebar) { _, _ in
            // Reset the detail-column stack when the sidebar pick changes
            // so pushes from the previous item don't leak.
            path.removeAll()
        }
    }

    private func row(_ item: SidebarItem, label: String, icon: String, tint: Color) -> some View {
        Label {
            Text(label)
        } icon: {
            Image(systemName: icon).foregroundStyle(tint)
        }
        .tag(item)
        .accessibilityIdentifier("sidebar-\(item.id)")
    }

    // MARK: - Detail root

    @ViewBuilder
    private var sidebarRootView: some View {
        switch selectedSidebar ?? .home {
        case .home:
            HomeView(
                progressStore: progressStore,
                downloader: downloader,
                siteIndex: siteIndex,
                path: $path
            )
        case .grade(let grade):
            BookListView(
                grade: grade,
                siteIndex: siteIndex,
                path: $path
            )
        case .review:
            ReviewView(progressStore: progressStore, path: $path)
        case .shop:
            ShopView(progressStore: progressStore)
        case .profile:
            ProfileView(progressStore: progressStore, path: $path)
        case .achievements:
            AchievementsView(progressStore: progressStore)
        }
    }
}

/// Extracted from RootView so both compact and regular layouts can reuse it.
struct RouteView: View {
    let route: AppRoute
    @ObservedObject var progressStore: ProgressStore
    @ObservedObject var downloader: AssetDownloader
    let siteIndex: SiteIndex
    @Binding var path: [AppRoute]

    var body: some View {
        switch route {
        case .bookList(let grade):
            BookListView(grade: grade, siteIndex: siteIndex, path: $path)
        case .bookDetail(let bookId):
            BookDetailView(
                bookId: bookId,
                progressStore: progressStore,
                downloader: downloader,
                path: $path
            )
        case .lesson(let bookId, let lessonId):
            LessonRunnerView(
                bookId: bookId,
                lessonId: lessonId,
                progressStore: progressStore,
                path: $path
            )
        case .lessonResult(let result):
            LessonResultView(
                result: result,
                progressStore: progressStore,
                path: $path
            )
        case .review:
            ReviewView(progressStore: progressStore, path: $path)
        case .reviewRunner:
            MistakeReviewRunnerView(progressStore: progressStore, path: $path)
        case .achievements:
            AchievementsView(progressStore: progressStore)
        case .stories(let bookId):
            StoryListView(bookId: bookId, path: $path)
        case .storyReader(let bookId, let storyId):
            StoryReaderView(bookId: bookId, storyId: storyId)
        case .reading(let bookId):
            PassageListView(bookId: bookId, path: $path)
        case .passageReader(let bookId, let passageId):
            PassageReaderView(bookId: bookId, passageId: passageId)
        case .shop:
            ShopView(progressStore: progressStore)
        case .profile:
            ProfileView(progressStore: progressStore, path: $path)
        case .settings:
            SettingsView(progressStore: progressStore)
        }
    }
}
