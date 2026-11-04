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

    /// Only the app can show the permission prompt; the keyboard uses what the app was granted.
    static func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    /// The newest `count` screenshots, oldest first, downscaled for low memory use.
    static func latest(_ count: Int = 2, maxWidth: CGFloat = ScreenshotReader.maxWidth) async throws -> [UIImage] {
        // Inside the keyboard, iOS may report a status that differs from the
        // app's, so try the fetch anyway and only blame access if it finds nothing.
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .limited { throw Failure.limitedAccess }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = count

        let assets: PHFetchResult<PHAsset>
        let albums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumScreenshots, options: nil)
        if let screenshots = albums.firstObject {
            assets = PHAsset.fetchAssets(in: screenshots, options: options)
        } else {
            options.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0",
                                            PHAssetMediaSubtype.photoScreenshot.rawValue)
            assets = PHAsset.fetchAssets(with: .image, options: options)
        }

        var newestFirst: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in newestFirst.append(asset) }
        guard !newestFirst.isEmpty else {
            throw status == .authorized ? Failure.noneFound : Failure.noAccess(status.rawValue)
        }

        var images: [UIImage] = []
        for asset in newestFirst.reversed() {
            if let image = await image(for: asset, maxWidth: maxWidth) {
                images.append(image)
            }
        }
        guard !images.isEmpty else { throw Failure.noneFound }
        return images
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
