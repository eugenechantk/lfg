import AVKit
import Testing
@testable import LFG

@Suite @MainActor
struct VideoPictureInPictureTests {
    @Test func floatingPlayerSurvivesPaneRemovalAndReleasesWhenStopped() {
        var owner: HostVideoPlayer.Coordinator? = .init()
        weak var retainedOwner = owner
        let controller = owner!.controller
        controller.player = AVPlayer()
        owner!.playerViewControllerWillStartPictureInPicture(controller)
        owner!.detach()
        owner = nil
        #expect(retainedOwner != nil)
        #expect(controller.player != nil)
        retainedOwner?.playerViewControllerDidStopPictureInPicture(controller)
        #expect(controller.player == nil)
        #expect(retainedOwner == nil)
    }

    @Test func closingAnInlinePlayerReleasesItsPlayback() {
        let owner = HostVideoPlayer.Coordinator()
        owner.controller.player = AVPlayer()
        owner.detach()
        #expect(owner.controller.player == nil)
    }

    @Test func failedFloatingStartReleasesAnAlreadyClosedPane() {
        var owner: HostVideoPlayer.Coordinator? = .init()
        weak var retainedOwner = owner
        let controller = owner!.controller
        controller.player = AVPlayer()
        owner!.playerViewControllerWillStartPictureInPicture(controller)
        owner!.detach()
        owner = nil
        retainedOwner?.playerViewController(controller, failedToStartPictureInPictureWithError: URLError(.cannotLoadFromNetwork))
        #expect(retainedOwner == nil)
        #expect(controller.player == nil)
    }

    @Test func reopeningTheFloatingFileReusesItsPlayer() {
        let url = URL(string: "https://example.com/clip.mp4")!
        let view = HostVideoPlayer(url: url, client: nil, allowsPictureInPicture: true)
        let owner = view.makeCoordinator()
        owner.url = url
        owner.controller.player = AVPlayer()
        owner.playerViewControllerWillStartPictureInPicture(owner.controller)
        owner.detach()
        let reopened = view.makeCoordinator()
        #expect(reopened === owner)
        owner.playerViewControllerDidStopPictureInPicture(owner.controller)
        #expect(owner.controller.player != nil)
        reopened.detach()
        owner.detach()
    }

    @Test func appDeclaresBackgroundPlaybackForFloatingVideo() {
        #expect((Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])?.contains("audio") == true)
    }
}
