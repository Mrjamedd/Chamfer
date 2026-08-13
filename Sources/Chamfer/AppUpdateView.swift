import ChamferUI
import SwiftUI

struct AppUpdatePanelView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var driver: AppUpdateUserDriver

    var body: some View {
        content
            .padding(Chamfer.Space.loose)
            .frame(width: Chamfer.Page.measure)
            .background(Chamfer.Palette.paper)
            .clipShape(
                RoundedRectangle(cornerRadius: Chamfer.Radius.card, style: .continuous)
            )
            .chamferRing(radius: Chamfer.Radius.card)
            .chamferFloat()
            .opacity(driver.isPresented ? 1 : 0)
            .scaleEffect(
                reduceMotion ? 1 : (driver.isPresented ? 1 : 0.96),
                anchor: .top
            )
            .animation(presentationAnimation, value: driver.isPresented)
            // The extra paper-free space belongs to the card's shadow, not to
            // the panel. The AppKit host stays visually absent.
            .padding(Chamfer.Space.section)
            .onExitCommand(perform: driver.dismissFromUser)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Chamfer update")
    }

    @ViewBuilder
    private var content: some View {
        switch driver.state {
        case .idle:
            EmptyView()

        case .permission:
            VStack(alignment: .leading, spacing: Chamfer.Space.loose) {
                heading(
                    eyebrow: "CHAMFER UPDATE",
                    title: "Keep Chamfer current?",
                    detail: "Chamfer can check once a day for an update, which Sparkle verifies before installation. You can still check manually from the Chamfer menu."
                )
                InlineNotice(
                    symbol: "hand.raised",
                    tone: .accent,
                    text: "Update checks do not include a system profile. Chamfer only asks Sparkle for the release feed."
                )
                actions {
                    Button("Not Now", action: driver.declineAutomaticChecks)
                        .buttonStyle(ChamferButtonStyle(.secondary))
                        .keyboardShortcut(.cancelAction)
                    Button("Check Automatically", action: driver.allowAutomaticChecks)
                        .buttonStyle(ChamferButtonStyle(.primary))
                        .keyboardShortcut(.defaultAction)
                }
            }

        case .checking:
            VStack(alignment: .leading, spacing: Chamfer.Space.loose) {
                heading(
                    eyebrow: "CHAMFER UPDATE",
                    title: "Looking for an update…",
                    detail: "Checking Chamfer’s release feed."
                )
                AppUpdateProgressTrack(fraction: nil, accessibilityValue: "Checking")
                actions {
                    Button("Cancel", action: driver.dismissFromUser)
                        .buttonStyle(ChamferButtonStyle(.secondary))
                        .keyboardShortcut(.cancelAction)
                }
            }

        case let .available(update):
            available(update)

        case let .downloading(update, progress):
            progressContent(
                eyebrow: "DOWNLOADING CHAMFER \(update.version)",
                title: "Bringing the update down",
                detail: downloadDetail(progress),
                fraction: progress.fraction,
                accessibilityValue: progressAccessibilityValue(progress),
                canCancel: true
            )

        case let .extracting(update, fraction):
            progressContent(
                eyebrow: "PREPARING CHAMFER \(update.version)",
                title: "Opening the update",
                detail: "Sparkle is checking and extracting the signed download.",
                fraction: fraction,
                accessibilityValue: fraction.map(percent) ?? "Extracting",
                canCancel: false
            )

        case let .readyToInstall(update):
            VStack(alignment: .leading, spacing: Chamfer.Space.loose) {
                heading(
                    eyebrow: "CHAMFER \(update.version)",
                    title: "Ready to install",
                    detail: "Chamfer will quit, install the signed update, and open again where you left it."
                )
                actions {
                    Button("Later", action: driver.dismissFromUser)
                        .buttonStyle(ChamferButtonStyle(.secondary))
                        .keyboardShortcut(.cancelAction)
                    Button("Install and Relaunch", action: driver.installAndRelaunch)
                        .buttonStyle(ChamferButtonStyle(.primary))
                        .keyboardShortcut(.defaultAction)
                }
            }

        case let .installing(update, applicationTerminated):
            VStack(alignment: .leading, spacing: Chamfer.Space.loose) {
                heading(
                    eyebrow: "CHAMFER \(update.version)",
                    title: applicationTerminated
                        ? "Installing the update…"
                        : "Chamfer is waiting to quit",
                    detail: applicationTerminated
                        ? "The signed update is being put in place."
                        : "A document or system prompt may be holding the app open. Finish there, then try again."
                )
                AppUpdateProgressTrack(fraction: nil, accessibilityValue: "Installing")
                if !applicationTerminated {
                    actions {
                        Button("Later", action: driver.dismissFromUser)
                            .buttonStyle(ChamferButtonStyle(.secondary))
                            .keyboardShortcut(.cancelAction)
                        Button("Try Again", action: driver.retryTerminating)
                            .buttonStyle(ChamferButtonStyle(.primary))
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }

        case .installed:
            VStack(alignment: .leading, spacing: Chamfer.Space.loose) {
                heading(
                    eyebrow: "CHAMFER UPDATE",
                    title: "Update installed",
                    detail: "The new version is in place."
                )
                actions {
                    Button("Done", action: driver.dismissFromUser)
                        .buttonStyle(ChamferButtonStyle(.secondary))
                        .keyboardShortcut(.defaultAction)
                }
            }

        case let .upToDate(message):
            VStack(alignment: .leading, spacing: Chamfer.Space.loose) {
                HStack(alignment: .top, spacing: Chamfer.Space.regular) {
                    heading(
                        eyebrow: "CHAMFER UPDATE",
                        title: message.title,
                        detail: message.detail
                    )
                    Spacer(minLength: Chamfer.Space.snug)
                    Pill("CURRENT", symbol: "checkmark", tone: .positive)
                }
                actions {
                    Button("Done", action: driver.dismissFromUser)
                        .buttonStyle(ChamferButtonStyle(.secondary))
                        .keyboardShortcut(.defaultAction)
                }
            }

        case let .error(message):
            VStack(alignment: .leading, spacing: Chamfer.Space.loose) {
                heading(
                    eyebrow: "CHAMFER UPDATE",
                    title: message.title,
                    detail: message.detail
                )
                InlineNotice(
                    symbol: "exclamationmark.triangle",
                    tone: .danger,
                    text: "The update did not complete. Try checking again in a little while."
                )
                actions {
                    Button("Done", action: driver.dismissFromUser)
                        .buttonStyle(ChamferButtonStyle(.secondary))
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func available(_ update: AppUpdateDetails) -> some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.loose) {
            HStack(alignment: .top, spacing: Chamfer.Space.regular) {
                heading(
                    eyebrow: "CHAMFER UPDATE",
                    title: availableTitle(update),
                    detail: update.isInformationOnly
                        ? "This release points to more information rather than an in-app download."
                        : "Here’s what changed."
                )
                Spacer(minLength: Chamfer.Space.snug)
                if update.isCritical {
                    Pill("IMPORTANT", symbol: "exclamationmark", tone: .danger)
                }
            }

            ScrollView(.vertical, showsIndicators: false) {
                AppUpdateReleaseNotesView(notes: update.releaseNotes)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: Chamfer.Page.margin * 4)

            actions {
                if !update.isInformationOnly {
                    Button("Skip This Version", action: driver.skipAvailableUpdate)
                        .buttonStyle(ChamferButtonStyle(.quiet))
                }
                Button("Later", action: driver.dismissFromUser)
                    .buttonStyle(ChamferButtonStyle(.secondary))
                    .keyboardShortcut(.cancelAction)
                Button(
                    update.isInformationOnly ? "Learn More" : primaryUpdateTitle(update),
                    action: driver.installAvailableUpdate
                )
                .buttonStyle(ChamferButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func progressContent(
        eyebrow: String,
        title: String,
        detail: String,
        fraction: Double?,
        accessibilityValue: String,
        canCancel: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.loose) {
            heading(eyebrow: eyebrow, title: title, detail: detail)
            AppUpdateProgressTrack(
                fraction: fraction,
                accessibilityValue: accessibilityValue
            )
            actions {
                Button(canCancel ? "Cancel" : "Hide", action: driver.dismissFromUser)
                    .buttonStyle(ChamferButtonStyle(.secondary))
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    private func heading(
        eyebrow: String,
        title: String,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.snug) {
            Text(eyebrow)
                .font(Chamfer.TypeScale.eyebrow)
                .foregroundStyle(Chamfer.Palette.brass)
            Text(title)
                .font(Chamfer.TypeScale.display)
                .foregroundStyle(Chamfer.Palette.textOnPaper)
            Text(detail)
                .font(Chamfer.TypeScale.body)
                .foregroundStyle(Chamfer.Palette.textOnPaperSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func actions<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: Chamfer.Space.snug) {
            Spacer()
            content()
        }
    }

    private func availableTitle(_ update: AppUpdateDetails) -> String {
        if update.isInformationOnly { return "Chamfer \(update.version) has news" }
        return switch update.stage {
        case .notDownloaded: "Chamfer \(update.version) is ready"
        case .downloaded: "Chamfer \(update.version) is downloaded"
        case .installing: "Chamfer \(update.version) is waiting to finish"
        }
    }

    private func primaryUpdateTitle(_ update: AppUpdateDetails) -> String {
        switch update.stage {
        case .notDownloaded: "Update Chamfer"
        case .downloaded: "Install Update"
        case .installing: "Install and Relaunch"
        }
    }

    private func downloadDetail(_ progress: AppUpdateProgress) -> String {
        let downloaded = ByteCountFormatter.string(
            fromByteCount: Int64(clamping: progress.completedBytes),
            countStyle: .file
        )
        guard let total = progress.totalBytes else {
            return "\(downloaded) downloaded. The server hasn’t reported a total."
        }
        let expected = ByteCountFormatter.string(
            fromByteCount: Int64(clamping: max(total, progress.completedBytes)),
            countStyle: .file
        )
        return "\(downloaded) of \(expected)"
    }

    private func progressAccessibilityValue(_ progress: AppUpdateProgress) -> String {
        progress.fraction.map(percent) ?? "Downloading"
    }

    private func percent(_ fraction: Double) -> String {
        "\(Int(fraction * 100)) percent"
    }

    private var presentationAnimation: Animation {
        Chamfer.Motion.reduce(
            driver.isPresented
                ? Chamfer.Motion.sheetArrival
                : Chamfer.Motion.sheetDeparture,
            when: reduceMotion
        )
    }
}

private struct AppUpdateReleaseNotesView: View {
    let notes: AppUpdateReleaseNotes

    var body: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.regular) {
            ForEach(Array(notes.blocks.enumerated()), id: \.offset) { _, block in
                switch block.style {
                case .heading:
                    Text(block.text)
                        .font(Chamfer.TypeScale.title)
                        .foregroundStyle(Chamfer.Palette.textOnPaper)
                case .paragraph:
                    Text(block.text)
                        .font(Chamfer.TypeScale.body)
                        .foregroundStyle(Chamfer.Palette.textOnPaperSoft)
                        .fixedSize(horizontal: false, vertical: true)
                case .listItem:
                    HStack(alignment: .firstTextBaseline, spacing: Chamfer.Space.snug) {
                        Circle()
                            .fill(Chamfer.Palette.pink)
                            .frame(width: Chamfer.Space.tight, height: Chamfer.Space.tight)
                            .accessibilityHidden(true)
                        Text(block.text)
                            .font(Chamfer.TypeScale.body)
                            .foregroundStyle(Chamfer.Palette.textOnPaperSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private struct AppUpdateProgressTrack: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let fraction: Double?
    let accessibilityValue: String

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Chamfer.Palette.pageText.opacity(0.09))
                if let fraction {
                    Capsule()
                        .fill(Chamfer.Palette.ink.opacity(0.78))
                        .frame(
                            width: max(
                                Chamfer.Space.tight,
                                proxy.size.width * min(max(fraction, 0), 1)
                            )
                        )
                        .animation(
                            Chamfer.Motion.reduce(Chamfer.Motion.quick, when: reduceMotion),
                            value: fraction
                        )
                } else {
                    AppUpdateIndeterminateSweep(width: proxy.size.width)
                }
            }
        }
        .frame(height: Chamfer.Space.tight)
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Update progress")
        .accessibilityValue(accessibilityValue)
    }
}

private struct AppUpdateIndeterminateSweep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @LegacyState private var advanced = false

    let width: CGFloat

    var body: some View {
        Capsule()
            .fill(Chamfer.Palette.ink.opacity(0.55))
            .frame(width: max(Chamfer.Space.loose, width * 0.32))
            .offset(x: advanced ? max(0, width * 0.68) : 0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(Chamfer.Motion.navigation.repeatForever(autoreverses: true)) {
                    advanced = true
                }
            }
    }
}
