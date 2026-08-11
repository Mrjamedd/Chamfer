import ChamferCore
import Foundation
import Testing

@testable import ChamferUI

/// A welcome shown twice is worse than one shown never, and a welcome that
/// never appears is a feature nobody knows exists. Both directions are here.
@Test func theWelcomeAppearsUntilItHasBeenThroughOnce() {
    #expect(WelcomeFlow.shouldPresent(for: .unconfigured))

    var seen = AppPreferences.unconfigured
    seen.hasSeenWelcome = true
    #expect(!WelcomeFlow.shouldPresent(for: seen))

    // Explicitly false is not the same as finished: a preferences file written
    // by a build with no welcome in it has to see this one.
    var older = AppPreferences.unconfigured
    older.hasSeenWelcome = false
    #expect(WelcomeFlow.shouldPresent(for: older))
}

/// Finishing has to survive a relaunch, which means surviving the encoder.
@Test func finishingTheWelcomeIsRemembered() throws {
    var preferences = AppPreferences.unconfigured
    preferences.hasSeenWelcome = true

    let data = try JSONEncoder().encode(preferences)
    let restored = try JSONDecoder().decode(AppPreferences.self, from: data)

    #expect(restored.hasSeenWelcome == true)
    #expect(!WelcomeFlow.shouldPresent(for: restored))

    // And a state file from before the flag existed decodes without it.
    let older = try JSONDecoder().decode(
        AppPreferences.self,
        from: Data(#"{"notifications":[],"configuredNotifications":[]}"#.utf8)
    )
    #expect(older.hasSeenWelcome == nil)
    #expect(WelcomeFlow.shouldPresent(for: older))
}

@Test func theLastSlideOffersToStartRatherThanToContinue() {
    let last = WelcomeFlow.slides.count - 1

    #expect(WelcomeFlow.slides.count == 4)
    #expect(WelcomeFlow.advanceTitle(atIndex: 0) == "Next")
    #expect(WelcomeFlow.advanceTitle(atIndex: last) == "Get started")
    #expect(!WelcomeFlow.isLast(index: 0))
    #expect(WelcomeFlow.isLast(index: last))
    // Past the end reads as the end rather than as a fifth slide.
    #expect(WelcomeFlow.isLast(index: last + 3))
}

/// The welcome makes promises the app has to keep, so the promises are checked
/// rather than left to whoever edits the copy next.
@Test func everySlideSaysSomethingConcreteAndNothingUntrue() {
    for slide in WelcomeFlow.slides {
        #expect(!slide.title.isEmpty)
        #expect(!slide.fact.isEmpty)
        #expect(slide.body.count > 80, "\(slide.id) is too thin to be worth a panel")
        #expect(slide.title.count < 60, "\(slide.id) has a title that will wrap badly")
    }

    #expect(Set(WelcomeFlow.slides.map(\.id)).count == WelcomeFlow.slides.count)

    // The one claim the whole product rests on has to be made explicitly.
    let everything = WelcomeFlow.slides
        .flatMap { [$0.title, $0.body, $0.fact] }
        .joined(separator: " ")
    #expect(everything.contains("on this Mac"))
    #expect(everything.contains("Review"))
}
