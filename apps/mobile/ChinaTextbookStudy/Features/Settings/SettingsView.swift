import SwiftUI

/// App settings — appearance, sound & haptics, data, about.
struct SettingsView: View {
    @ObservedObject var progressStore: ProgressStore
    @ObservedObject private var settings = SettingsStore.shared
    @State private var showResetConfirm = false
    @State private var deniedHint = false

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                appearanceSection
                reminderSection
                soundSection
                dataSection
                aboutSection
            }
            .padding(20)
        }
        .background(DuoColors.bg.ignoresSafeArea())
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("确定要重置全部学习进度吗？此操作无法撤销。", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("重置进度", role: .destructive) {
                progressStore.resetProgress()
                HapticEngine.shared.success()
            }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        section("外观") {
            HStack(spacing: 8) {
                ForEach(AppAppearance.allCases) { mode in
                    let selected = settings.appearance == mode
                    Button {
                        HapticEngine.shared.tap()
                        withAnimation(Motion.press) { settings.appearance = mode }
                    } label: {
                        Text(mode.label)
                            .duoFont(.caption)
                            .foregroundStyle(selected ? .white : DuoColors.inkMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(selected ? DuoColors.primary : DuoColors.surfaceAlt, in: .rect(cornerRadius: Radius.control))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Streak reminder

    private var reminderSection: some View {
        section("提醒") {
            VStack(alignment: .leading, spacing: 8) {
                toggleRow("连胜提醒", icon: "bell.badge.fill", tint: DuoColors.fox, isOn: Binding(
                    get: { settings.streakReminderEnabled },
                    set: { wanted in
                        if wanted {
                            Task {
                                let granted = await NotificationService.shared.requestAuthorization()
                                settings.streakReminderEnabled = granted
                                if granted {
                                    NotificationService.shared.rescheduleStreakReminder(
                                        streak: progressStore.progress.streak,
                                        studiedToday: progressStore.todayXp > 0
                                    )
                                    HapticEngine.shared.success()
                                } else {
                                    deniedHint = true
                                }
                            }
                        } else {
                            settings.streakReminderEnabled = false
                            NotificationService.shared.cancel()
                        }
                    }
                ))
                Text(deniedHint
                     ? "系统未授权通知，请到「设置 › 通知 › 课本学习」中开启。"
                     : "每晚 20:00 提醒你保住连胜；当天已学习则自动跳过。")
                    .duoFont(.micro)
                    .foregroundStyle(deniedHint ? DuoColors.danger : DuoColors.inkSofter)
                    .padding(.horizontal, 2)
                    .padding(.bottom, 10)
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .background(DuoColors.surface, in: .rect(cornerRadius: Radius.card))
            .overlay { RoundedRectangle(cornerRadius: Radius.card).strokeBorder(DuoColors.border, lineWidth: 2) }
        }
    }

    // MARK: - Sound & haptics

    private var soundSection: some View {
        section("声音与触感") {
            VStack(spacing: 0) {
                toggleRow("音效", icon: "speaker.wave.2.fill", tint: DuoColors.secondary, isOn: Binding(
                    get: { !settings.isMuted },
                    set: { settings.isMuted = !$0 }
                ))
                divider
                toggleRow("触感反馈", icon: "hand.tap.fill", tint: DuoColors.beetle, isOn: $settings.hapticEnabled)
                divider
                toggleRow("自动朗读", icon: "text.bubble.fill", tint: DuoColors.fox, isOn: $settings.autoNarrate)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(DuoColors.surface, in: .rect(cornerRadius: Radius.card))
            .overlay { RoundedRectangle(cornerRadius: Radius.card).strokeBorder(DuoColors.border, lineWidth: 2) }
        }
    }

    private func toggleRow(_ title: String, icon: String, tint: Color, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 18, weight: .heavy)).foregroundStyle(tint).frame(width: 26)
            Text(title).duoFont(.body).foregroundStyle(DuoColors.ink)
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(DuoColors.primary)
        }
        .padding(.vertical, 12)
    }

    private var divider: some View {
        Rectangle().fill(DuoColors.border).frame(height: 1)
    }

    // MARK: - Data

    private var dataSection: some View {
        section("数据") {
            Button(role: .destructive) { showResetConfirm = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "trash.fill").font(.system(size: 17, weight: .heavy)).foregroundStyle(DuoColors.danger).frame(width: 26)
                    Text("重置学习进度").duoFont(.body).foregroundStyle(DuoColors.danger)
                    Spacer()
                }
                .padding(16)
                .background(DuoColors.surface, in: .rect(cornerRadius: Radius.card))
                .overlay { RoundedRectangle(cornerRadius: Radius.card).strokeBorder(DuoColors.border, lineWidth: 2) }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        section("关于") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("版本").duoFont(.body).foregroundStyle(DuoColors.ink)
                    Spacer()
                    Text(appVersion).duoFont(.caption).foregroundStyle(DuoColors.inkMuted)
                }
                Text("教材内容版权归原出版方所有，客户端代码 MIT 开源。")
                    .duoFont(.micro)
                    .foregroundStyle(DuoColors.inkSofter)
            }
            .padding(16)
            .background(DuoColors.surface, in: .rect(cornerRadius: Radius.card))
            .overlay { RoundedRectangle(cornerRadius: Radius.card).strokeBorder(DuoColors.border, lineWidth: 2) }
        }
    }

    // MARK: - Section wrapper

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).duoFont(.caption).tracking(1).foregroundStyle(DuoColors.inkMuted)
            content()
        }
    }
}
