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
    /// 聪聪's "我们马上开始第一课！" toast shown right after onboarding.
    @State private var showFirstLessonToast = false

    enum SidebarItem: Hashable, Identifiable {
        case home
        case grade(Int)
        case league
        case review
        case shop
        case profile
        case achievements
        var id: String {
            switch self {
            case .home: return "home"
            case .grade(let g): return "grade-\(g)"
            case .league: return "league"
            case .review: return "review"
            case .shop: return "shop"
            case .profile: return "profile"
            case .achievements: return "achievements"
            }
        }
    }

    var body: some View {
        Group {
            if hSize == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        // 立刻进第一课 (ios-retention-11): the moment onboarding completes,
        // push the learner straight into lesson one — no empty home screen
        // between "I committed to a goal" and "I'm learning".
        .onChange(of: progressStore.hasCompletedOnboarding) { _, done in
            if done { startFirstLessonAfterOnboarding() }
        }
        .overlay(alignment: .top) {
            if showFirstLessonToast {
                firstLessonToast
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
    }

    // MARK: - Post-onboarding first lesson (ios-retention-11)

    /// Resolve the active book's very first path lesson and push it. If the
    /// book isn't downloaded yet (outline load throws) we simply stay on the
    /// home screen, where the download card takes over.
    private func startFirstLessonAfterOnboarding() {
        guard
            let bookId = progressStore.activeBookId,
            let outline = try? DataLoader.shared.loadOutline(bookId: bookId),
            let first = outline.pathLessonMetas(bookId: bookId).first
        else { return }

        activeTab = .learn
        selectedSidebar = .home
        withAnimation(Motion.bounce) { showFirstLessonToast = true }
        // Let the onboarding fade + toast land, then push the lesson.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            path.append(.lesson(bookId: bookId, lessonId: first.id))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation(.easeOut(duration: 0.3)) { showFirstLessonToast = false }
        }
    }

    private var firstLessonToast: some View {
        HStack(spacing: 10) {
            MascotView(mood: .cheer, size: 52, reactTo: .correct)
            Text("我们马上开始第一课！")
                .duoFont(.subhead)
                .foregroundStyle(DuoColors.ink)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(DuoColors.surface, in: .capsule)
        .overlay { Capsule().strokeBorder(DuoColors.border, lineWidth: 2) }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        .padding(.top, 8)
        .allowsHitTesting(false)
        .accessibilityIdentifier("first-lesson-toast")
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
        case .league:
            LeagueView(progressStore: progressStore)
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
                row(.league, label: "排行", icon: "trophy.fill", tint: DuoColors.bee)
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
        case .league:
            LeagueView(progressStore: progressStore)
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
