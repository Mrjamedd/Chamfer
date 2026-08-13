import Testing
@testable import Chamfer

@Test func aLaterBookmarkFailureDoesNotEraseAnEarlierConnectedFolder() {
    var result = VaultConnectionResult.unchanged

    result.merge(.connected)
    result.merge(.lastingAccessRefused(folderName: "Shared notes"))

    #expect(result.didChange)
    #expect(
        result.notice
            == "Chamfer couldn’t keep access to “Shared notes”. macOS refused to issue a lasting permission for that folder, so it hasn’t been connected. Try a folder inside your home directory."
    )
}
