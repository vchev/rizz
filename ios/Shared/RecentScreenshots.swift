import Photos
import UIKit

/// Finds the newest screenshots in Photos, so the keyboard can read the chat
/// without the user copying anything. Images stay on the phone; only the text
/// read from them is sent, and only when the user taps the button.
enum RecentScreenshots {
    enum Failure: LocalizedError {
        case noAccess(Int)   // the Photos status iOS reported, to tell device cases apart
        case limitedAccess
        case noneFound

        var errorDescription: String? {
            switch self {
            case .noAccess(let status):
                return "Coax can't see your screenshots yet (code \(status)). Use the Back Tap shortcut, or copy their message and tap the clipboard button."
            case .limitedAccess:
                return "Coax can only see the photos you picked, so new screenshots are hidden. Open Settings › Coax › Photos and choose Full Access."
            case .noneFound:
                return "No screenshots found. Take a screenshot of the chat, then try again."
            }
        }
    }

    static var hasAccess: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    /// Full access: "Limit Access" hides new screenshots from Coax.
    static var hasFullAccess: Bool {
        PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized
    }

    /// Only some photos were allowed, so new screenshots can't be seen.
    static var isLimited: Bool {
        PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited
    }

    /// Only the app can show the permission prompt; the keyboard uses what the app was granted.
    static func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    /// The newest `count` screenshots, oldest first, downscaled for low memory use.
    static func latest(_ count: Int = 2, maxWidth: CGFloat = ScreenshotReader.maxWidth) async throws -> [UIImage] {
        try await latestWithDates(count, maxWidth: maxWidth).map(\.image)
    }

    /// Like `latest`, with when each screenshot was taken. Oldest first.
    /// `skipping` leaves out that many of the newest screenshots (used to look further back).
    static func latestWithDates(_ count: Int = 2, skipping: Int = 0, maxWidth: CGFloat = ScreenshotReader.maxWidth) async throws
        -> [(image: UIImage, taken: Date)] {
        // Inside the keyboard, iOS may report a status that differs from the
        // app's, so try the fetch anyway and only blame access if it finds nothing.
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .limited { throw Failure.limitedAccess }

        let assets = fetchScreenshots(limit: count + skipping)

        var newestFirst: [PHAsset] = []
        assets.enumerateObjects { asset, i, _ in if i >= skipping { newestFirst.append(asset) } }
        guard !newestFirst.isEmpty else {
            throw status == .authorized ? Failure.noneFound : Failure.noAccess(status.rawValue)
        }

        var images: [(image: UIImage, taken: Date)] = []
        for asset in newestFirst.reversed() {
            // A screenshot taken a moment ago may not be ready to load yet: wait
            // for the newest one rather than quietly reading only older ones.
            let isNewest = skipping == 0 && asset.localIdentifier == newestFirst.first?.localIdentifier
            var image = await image(for: asset, maxWidth: maxWidth)
            var tries = 0
            while image == nil && isNewest && tries < 8 {
                try? await Task.sleep(nanoseconds: 300_000_000)
                image = await self.image(for: asset, maxWidth: maxWidth)
                tries += 1
            }
            if let image {
                images.append((image, asset.creationDate ?? .distantPast))
            } else if isNewest {
                throw Failure.noneFound
            }
        }
        guard !images.isEmpty else { throw Failure.noneFound }
        return images
    }

    /// Screenshots, newest first.
    static func fetchScreenshots(limit: Int) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit
        let albums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumScreenshots, options: nil)
        if let screenshots = albums.firstObject {
            return PHAsset.fetchAssets(in: screenshots, options: options)
        }
        options.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0",
                                        PHAssetMediaSubtype.photoScreenshot.rawValue)
        return PHAsset.fetchAssets(with: .image, options: options)
    }

    /// The newest screenshot's id and time, without loading the image.
    static func newest() -> (id: String, created: Date)? {
        guard let asset = fetchScreenshots(limit: 1).firstObject else { return nil }
        return (asset.localIdentifier, asset.creationDate ?? .distantPast)
    }

    private static func image(for asset: PHAsset, maxWidth: CGFloat) async -> UIImage? {
        let width = CGFloat(max(asset.pixelWidth, 1))
        let scale = min(1, maxWidth / width)
        let size = CGSize(width: (width * scale).rounded(), height: (CGFloat(asset.pixelHeight) * scale).rounded())

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat   // exactly one callback
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFit,
                                                  options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}

/// Watches for a screenshot taken while the Coax keyboard is open, so it can
/// read it without a tap. Only looks at screenshots newer than `start()`.
/// Photos tells us about changes; a light check every half second backs that
/// up, in case iOS doesn't send change notices to the keyboard. The Photos
/// lookups run off the main thread and pause while the user is typing, so
/// they never slow the keys down.
@MainActor
final class ScreenshotWatcher: NSObject, PHPhotoLibraryChangeObserver {
    var onNewScreenshot: (() -> Void)?
    private var since = Date()
    private var lastSeenID: String?
    private var timer: Timer?
    private var registered = false
    private var checking = false
    private var quietUntil = Date.distantPast
    private let queue = DispatchQueue(label: "coax.screenshot-watcher", qos: .utility)

    /// `lookBack`: also read a screenshot taken up to this many seconds before
    /// starting (the iMessage app uses this, for "screenshot, then open Coax").
    func start(lookBack: TimeInterval = 0) {
        stop()
        since = Date().addingTimeInterval(-lookBack)
        lastSeenID = nil
        if lookBack > 0 {
            check()
        } else {
            checking = true
            queue.async { [weak self] in
                let newest = RecentScreenshots.newest()
                Task { @MainActor in
                    guard let self else { return }
                    self.lastSeenID = newest?.id
                    self.checking = false
                }
            }
        }
        PHPhotoLibrary.shared().register(self)
        registered = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if registered {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
            registered = false
        }
    }

    /// Call on every key press: checks wait until typing pauses for 2 seconds.
    func userIsTyping() {
        quietUntil = Date().addingTimeInterval(2)
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in self.check() }
    }

    private func check() {
        guard !checking, Date() >= quietUntil else { return }
        checking = true
        let since = self.since
        queue.async { [weak self] in
            let newest = RecentScreenshots.newest()
            Task { @MainActor in
                guard let self else { return }
                self.checking = false
                guard let newest,
                      newest.id != self.lastSeenID,
                      newest.created > since.addingTimeInterval(-2)
                else { return }
                self.lastSeenID = newest.id
                self.onNewScreenshot?()
            }
        }
    }
}
