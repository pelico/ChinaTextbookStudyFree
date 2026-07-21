import SwiftUI

/// Reusable download affordance for a book bundle. Shows size, a live progress
/// bar + percentage while downloading, inline errors, and completes via a
/// scale-in success. Bound to `AssetDownloader`'s published state.
struct BookDownloadCard: View {
    let entry: ManifestEntry
    @ObservedObject var downloader: AssetDownloader
    var onComplete: () -> Void = {}

    private var progress: Double { downloader.bookProgress[entry.bookId] ?? 0 }
    private var inFlight: Bool { downloader.inFlight.contains(entry.bookId) }
    private var totalBytes: Int64 { entry.data.bytes + entry.audio.bytes }
    private var sizeText: String { ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file) }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(DuoColors.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("下载课本内容").duoFont(.subhead).foregroundStyle(DuoColors.ink)
                    Text("含课程与音频 · \(sizeText)").duoFont(.caption).foregroundStyle(DuoColors.inkMuted)
                }
                Spacer()
            }

            if inFlight {
                VStack(spacing: 6) {
                    StyledProgressBar(progress: progress, height: 12, trackColor: DuoColors.surfaceAlt)
                    Text("\(Int(progress * 100))%")
                        .duoNumeral(.caption)
                        .foregroundStyle(DuoColors.secondary)
                        .contentTransition(.numericText())
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else if let err = downloader.lastError {
                Text(err).duoFont(.caption).foregroundStyle(DuoColors.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(inFlight ? "下载中…" : (downloader.lastError != nil ? "重试下载" : "下载课本")) {
                Task {
                    try? await downloader.ensureBookDownloaded(entry)
                    if downloader.isBookDownloaded(entry.bookId) { onComplete() }
                }
            }
            .buttonStyle(ChunkyButtonStyle(inFlight ? .disabled : .secondary))
            .disabled(inFlight)
        }
        .padding(16)
        .background(DuoColors.surface, in: .rect(cornerRadius: Radius.card))
        .overlay { RoundedRectangle(cornerRadius: Radius.card).strokeBorder(DuoColors.border, lineWidth: 2) }
        .onChange(of: progress) { _, p in
            if p >= 1 { HapticEngine.shared.success(); onComplete() }
        }
    }
}
