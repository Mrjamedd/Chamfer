import ChamferCore
import SwiftUI

/// One panel of the welcome.
///
/// Content is a value rather than a view so the sequence can be reasoned about
/// and tested without a window: what it says, how many there are, and which one
/// is the last.
public struct WelcomeSlide: Identifiable, Equatable, Sendable {
    public let id: String
    /// The small capitalised word above the title.
    public let eyebrow: String
    public let title: String
    public let body: String
    /// One concrete fact, set apart. Every slide has one, because a welcome
    /// made only of adjectives is the kind people click through.
    public let fact: String

    public init(id: String, eyebrow: String, title: String, body: String, fact: String) {
        self.id = id
        self.eyebrow = eyebrow
        self.title = title
        self.body = body
        self.fact = fact
    }
}

/// What the welcome says, and when it is shown.
///
/// Four panels, which is the most anybody reads before pressing the button.
/// They answer the four questions somebody opening this app for the first time
/// actually has — what is it, where does my writing go, what will it change,
/// and what happens next — rather than touring the interface.
public enum WelcomeFlow {
    public static let slides: [WelcomeSlide] = [
        WelcomeSlide(
            id: "what",
            eyebrow: "Chamfer",
            title: "A quiet editor for notes you already wrote.",
            body: """
                Chamfer reads the Markdown notes in a folder you choose and \
                offers small corrections: a misspelling, an agreement, a \
                heading that lost its blank line. It never writes anything you \
                have not seen.
                """,
            fact: "Nothing happens until you connect a folder."
        ),
        WelcomeSlide(
            id: "local",
            eyebrow: "Where your notes go",
            title: "Nowhere. The model runs on this Mac.",
            body: """
                Chamfer downloads a language model sized to your hardware and \
                runs it as its own process, on a private port, for as long as \
                the app is open. Your notes are read on this machine and \
                nowhere else.
                """,
            fact: "Quit Chamfer and the model stops with it."
        ),
        WelcomeSlide(
            id: "review",
            eyebrow: "What it changes",
            title: "You decide, one rewrite at a time.",
            body: """
                Every suggestion arrives in Review as a diff you can read. \
                Accept it and Chamfer takes a snapshot first, so anything \
                applied can be undone. Reject it and the note is untouched.
                """,
            fact: "A rewrite Chamfer is unsure of is always shown, never applied."
        ),
        WelcomeSlide(
            id: "start",
            eyebrow: "Getting started",
            title: "Connect a folder, then forget about it.",
            body: """
                Point Chamfer at a folder of notes and choose what it may fix — \
                spelling only, grammar, or a full cleanup. It runs when a note \
                goes quiet, and leaves what it finds in Review for whenever you \
                get to it.
                """,
            fact: "You can change any of this per folder, later."
        )
    ]

    /// Whether the welcome should open, given what has been saved.
    ///
    /// Reads the absence of a `true` rather than the presence of a `false`, so
    /// a preferences file written before the welcome existed still shows it
    /// once. See `AppPreferences.hasSeenWelcome`.
    public static func shouldPresent(for preferences: AppPreferences) -> Bool {
        preferences.hasSeenWelcome != true
    }

    public static func title(atIndex index: Int) -> String {
        slides.indices.contains(index) ? slides[index].title : ""
    }

    /// The button's words. Named here so the last panel cannot say "Next" and
    /// then close.
    public static func advanceTitle(atIndex index: Int) -> String {
        index >= slides.count - 1 ? "Get started" : "Next"
    }

    public static func isLast(index: Int) -> Bool {
        index >= slides.count - 1
    }
}

// MARK: - The window

/// The welcome, over the app it is welcoming.
///
/// A cover rather than a separate window: the dashboard is already behind it,
/// dimmed, which is a truer promise of what pressing the button leads to than
/// a floating panel would be.
public struct WelcomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let slides = WelcomeFlow.slides
    @LegacyState private var index = 0
    @LegacyState private var hasAppeared = false

    private let onFinish: () -> Void

    public init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    private var slide: WelcomeSlide { slides[min(index, slides.count - 1)] }

    public var body: some View {
        ZStack {
            Chamfer.Palette.canvas.opacity(0.97).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Text(slide.eyebrow.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .kerning(1.3)
                    .foregroundStyle(Chamfer.Palette.pageTextSoft.opacity(0.8))

                Text(slide.title)
                    .font(.system(size: 32, weight: .regular, design: .serif))
                    .tracking(-0.9)
                    .foregroundStyle(Chamfer.Palette.pageText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)

                Text(slide.body)
                    .font(.system(size: 15, design: .serif))
                    .lineSpacing(3)
                    .foregroundStyle(Chamfer.Palette.pageTextSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)

                HStack(spacing: 9) {
                    Rectangle()
                        .fill(Chamfer.Palette.brass.opacity(0.55))
                        .frame(width: 2)
                    Text(slide.fact)
                        .font(.system(size: 12, design: .serif))
                        .foregroundStyle(Chamfer.Palette.pageText.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 20)

                Spacer(minLength: 24)

                HStack(spacing: 14) {
                    HStack(spacing: 6) {
                        ForEach(slides.indices, id: \.self) { position in
                            Capsule()
                                .fill(
                                    position == index
                                        ? Chamfer.Palette.pageText.opacity(0.72)
                                        : Chamfer.Palette.pageTextSoft.opacity(0.26)
                                )
                                .frame(width: position == index ? 16 : 6, height: 6)
                        }
                    }
                    .accessibilityLabel("Step \(index + 1) of \(slides.count)")

                    Spacer(minLength: 12)

                    if !WelcomeFlow.isLast(index: index) {
                        Button("Skip", action: finish)
                            .buttonStyle(ChamferButtonStyle(.quiet))
                    }

                    Button(WelcomeFlow.advanceTitle(atIndex: index), action: advance)
                        .buttonStyle(ChamferButtonStyle(.primary))
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 46)
            .padding(.vertical, 44)
            .frame(maxWidth: 520, maxHeight: 430, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Chamfer.Palette.paper)
                    .shadow(
                        color: Chamfer.Palette.pageText.opacity(0.14),
                        radius: 34,
                        y: 16
                    )
            )
            .opacity(hasAppeared ? 1 : 0)
            .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.98)
            .animation(
                Chamfer.Motion.reduce(Chamfer.Motion.navigation, when: reduceMotion),
                value: hasAppeared
            )
            .animation(
                Chamfer.Motion.reduce(Chamfer.Motion.interactive, when: reduceMotion),
                value: index
            )
        }
        .onAppear { hasAppeared = true }
        .onExitCommand(perform: finish)
        .accessibilityAddTraits(.isModal)
    }

    private func advance() {
        guard !WelcomeFlow.isLast(index: index) else {
            finish()
            return
        }
        Haptics.pop()
        index += 1
    }

    private func finish() {
        Haptics.commit()
        onFinish()
    }
}

public extension Notification.Name {
    /// Posted by the Help menu to bring the welcome back.
    ///
    /// A notification rather than a binding into the scene, for the same reason
    /// the settings link is a closure: `commands` is built where the window's
    /// state is not in scope, and threading a binding out of a `WindowGroup`
    /// to reach it costs more than one name.
    static let chamferShowWelcome = Notification.Name("chamfer.showWelcome")
}
