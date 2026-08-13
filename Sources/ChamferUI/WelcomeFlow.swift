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

    public static func transitionDirection(
        fromIndex: Int,
        toIndex: Int
    ) -> BottomBarContentMotion.Direction {
        guard slides.indices.contains(fromIndex), slides.indices.contains(toIndex)
        else { return .stationary }

        return BottomBarContentMotion.direction(
            from: slides[fromIndex].id,
            to: slides[toIndex].id,
            orderedIDs: slides.map(\.id)
        )
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
    @LegacyState private var slideContentHeight: CGFloat?
    @LegacyState private var transitionDirection = BottomBarContentMotion.Direction.stationary

    private let onFinish: () -> Void

    public init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    private var slide: WelcomeSlide { slides[min(index, slides.count - 1)] }

    private static let welcomeNote = HomeNoteCardModel(
        id: "welcome.what",
        title: "Field notes",
        detail: "A NOTE YOU ALREADY WROTE",
        preview: "the trail gets quite after rain",
        document: NoteDocument(
            url: URL(fileURLWithPath: "/Welcome/Field notes.md"),
            text: "# Field notes\n\nthe trail gets quite after rain"
        ),
        source: .recent,
        isFeatured: false,
        role: .background
    )

    public var body: some View {
        ZStack {
            Chamfer.Palette.canvas.opacity(0.97).ignoresSafeArea()

            VStack(alignment: .leading, spacing: Chamfer.Space.section) {
                slideStage
                controls
            }
            .padding(.horizontal, 46)
            .padding(.vertical, 44)
            .frame(maxWidth: 520, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Chamfer.Radius.card, style: .continuous)
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
        selectSlide(at: index + 1)
    }

    private var slideStage: some View {
        ZStack(alignment: .topLeading) {
            slideContent(slide)
                .id(slide.id)
                .transition(slideTransition)
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.height
                } action: { height in
                    updateSlideHeight(height, for: slide.id)
                }
        }
        .frame(height: slideContentHeight, alignment: .topLeading)
        .clipped()
    }

    private func slideContent(_ slide: WelcomeSlide) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(slide.eyebrow.uppercased())
                .font(Chamfer.TypeScale.eyebrow)
                .foregroundStyle(Chamfer.Palette.pageTextSoft.opacity(0.8))

            Text(slide.title)
                .font(.system(size: 32, weight: .regular, design: .serif))
                .tracking(-0.9)
                .foregroundStyle(Chamfer.Palette.pageText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Chamfer.Space.regular)

            Text(slide.body)
                .font(.system(size: 15, design: .serif))
                .lineSpacing(3)
                .foregroundStyle(Chamfer.Palette.pageTextSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            slideVisual(for: slide)

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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func slideVisual(for slide: WelcomeSlide) -> some View {
        switch slide.id {
        case "what":
            StickyNotePreview(
                card: Self.welcomeNote,
                fill: HomeNoteSlotPalette.fill(for: 0),
                hand: HomeNoteHand(id: Self.welcomeNote.id),
                isHovered: false
            )
            .frame(width: 150, height: 104)
            .rotationEffect(.degrees(HomeNoteHand(id: Self.welcomeNote.id).rotation))
            .padding(.top, Chamfer.Space.loose)
            .padding(.leading, Chamfer.Space.regular)
            .accessibilityHidden(true)

        case "local":
            HStack(spacing: Chamfer.Space.regular) {
                ModelsEyebrowMark()
                    .scaleEffect(1.6)
                    .frame(width: 28, height: 18)
                Rectangle()
                    .fill(Chamfer.Palette.pageTextSoft.opacity(0.34))
                    .frame(width: 36, height: 1)
                Text("ON THIS MAC")
                    .font(Chamfer.TypeScale.eyebrow)
                    .foregroundStyle(Chamfer.Palette.pageTextSoft.opacity(0.68))
            }
            .padding(.top, Chamfer.Space.loose)
            .accessibilityHidden(true)

        case "review":
            // Byte-for-byte with the awkward vault fixture: the welcome shows
            // a real product state without making UI depend on the fixture
            // target that the shipping app deliberately excludes.
            DiffHunkView(
                Hunk(
                    before: "planted teh beans",
                    after: "Planted the beans.",
                    startLine: 3
                )
            )
            .frame(maxWidth: 360)
            .padding(.top, Chamfer.Space.loose)

        default:
            // Getting started is already followed immediately by the controls
            // that do exactly what it describes. Another sample object there
            // would compete with the real next step rather than explain it.
            EmptyView()
        }
    }

    private var controls: some View {
        HStack(spacing: Chamfer.Space.regular) {
            HStack(spacing: Chamfer.Space.hair) {
                ForEach(slides.indices, id: \.self) { position in
                    Button {
                        selectSlide(at: position)
                    } label: {
                        Capsule()
                            .fill(
                                position == index
                                    ? Chamfer.Palette.pageText.opacity(0.72)
                                    : Chamfer.Palette.pageTextSoft.opacity(0.26)
                            )
                            .frame(width: position == index ? 16 : 6, height: 6)
                            .frame(
                                width: Chamfer.Control.minimumHitSize,
                                height: Chamfer.Control.minimumHitSize
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .chamferFocusable(radius: Chamfer.Radius.pill)
                    .accessibilityLabel("Step \(position + 1): \(slides[position].eyebrow)")
                    .accessibilityValue(position == index ? "Current" : "")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Step \(index + 1) of \(slides.count)")

            Spacer(minLength: Chamfer.Space.regular)

            if !WelcomeFlow.isLast(index: index) {
                Button("Skip", action: finish)
                    .buttonStyle(ChamferButtonStyle(.quiet))
            }

            Button(WelcomeFlow.advanceTitle(atIndex: index), action: advance)
                .buttonStyle(ChamferButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
        }
    }

    private var slideTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(
                with: .offset(
                    x: BottomBarContentMotion.incomingOffset(
                        for: transitionDirection,
                        distance: Chamfer.Space.loose
                    )
                )
            )
            .animation(slideArrivalAnimation),
            removal: .opacity.combined(
                with: .offset(
                    x: BottomBarContentMotion.outgoingOffset(
                        for: transitionDirection,
                        distance: Chamfer.Space.loose
                    )
                )
            )
            .animation(slideDepartureAnimation)
        )
    }

    private var slideArrivalAnimation: Animation {
        Chamfer.Motion.reduce(Chamfer.Motion.contentArrival, when: reduceMotion)
    }

    private var slideDepartureAnimation: Animation {
        Chamfer.Motion.reduce(Chamfer.Motion.contentDeparture, when: reduceMotion)
    }

    private func selectSlide(at targetIndex: Int) {
        guard slides.indices.contains(targetIndex), targetIndex != index else { return }

        Haptics.pop()
        var directionTransaction = Transaction()
        directionTransaction.disablesAnimations = true
        withTransaction(directionTransaction) {
            transitionDirection = WelcomeFlow.transitionDirection(
                fromIndex: index,
                toIndex: targetIndex
            )
        }
        withAnimation(slideArrivalAnimation) {
            index = targetIndex
        }
    }

    private func updateSlideHeight(_ height: CGFloat, for slideID: String) {
        guard slideID == slide.id, height > 0 else { return }
        guard let currentHeight = slideContentHeight else {
            var firstMeasurement = Transaction()
            firstMeasurement.disablesAnimations = true
            withTransaction(firstMeasurement) {
                slideContentHeight = height
            }
            return
        }
        guard abs(currentHeight - height) >= 0.5 else { return }

        withAnimation(slideArrivalAnimation) {
            slideContentHeight = height
        }
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
