import Foundation
import Testing
@testable import Chamfer

@Test func notificationActionsRouteToTheirExactDestinations() {
    let historyEntryID = UUID(uuidString: "8D0105AF-16E1-41BE-85EB-EA4E8B27E023")!

    #expect(
        NotificationRouter.route(
            actionIdentifier: NotificationAction.review,
            userInfo: [:]
        ) == .review
    )
    #expect(
        NotificationRouter.route(
            actionIdentifier: NotificationAction.undo,
            userInfo: [NotificationRouter.historyEntryKey: historyEntryID.uuidString]
        ) == .undo(historyEntryID)
    )
    #expect(
        NotificationRouter.route(
            actionIdentifier: NotificationAction.models,
            userInfo: [:]
        ) == .models
    )
    #expect(
        NotificationRouter.route(
            actionIdentifier: NotificationAction.vaults,
            userInfo: [:]
        ) == .vaults
    )
}

@Test func undoNotificationWithoutItsExactHistoryEntryDoesNothing() {
    #expect(
        NotificationRouter.route(
            actionIdentifier: NotificationAction.undo,
            userInfo: [:]
        ) == nil
    )
    #expect(
        NotificationRouter.route(
            actionIdentifier: NotificationAction.undo,
            userInfo: [NotificationRouter.historyEntryKey: "not-a-uuid"]
        ) == nil
    )
}
