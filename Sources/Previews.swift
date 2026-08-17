import AppKit
import CoreGraphics
import ScreenCaptureKit

enum Previews {
    private static let lock = NSLock()
    private static var asked = false
    private static var cache: [CGWindowID: (Date, NSImage)] = [:]
    private static var shareable: SCShareableContent?
    private static var shareableAt = Date.distantPast

    static var isTrusted: Bool { CGPreflightScreenCaptureAccess() }

    static func prepare() {
        if isTrusted || asked { return }
        asked = true
        _ = CGRequestScreenCaptureAccess()
    }

    static func image(windowID: CGWindowID, maxPixel: CGFloat) -> NSImage? {
        lock.lock()
        if let hit = cache[windowID], Date().timeIntervalSince(hit.0) < 1.2 {
            let image = hit.1
            lock.unlock()
            return image
        }
        lock.unlock()

        if let image = cgCapture(windowID, maxPixel: maxPixel) {
            store(windowID, image)
            return image
        }
        return nil
    }

    static func capture(_ windowIDs: [CGWindowID], maxPixel: CGFloat, then: @escaping ([CGWindowID: NSImage]) -> Void) {
        prepare()
        DispatchQueue.global(qos: .userInitiated).async {
            var result: [CGWindowID: NSImage] = [:]
            for id in windowIDs {
                if let image = image(windowID: id, maxPixel: maxPixel) {
                    result[id] = image
                }
            }
            DispatchQueue.main.async { then(result) }
            sckCapture(windowIDs, maxPixel: maxPixel, then: then)
        }
    }

    private static func store(_ windowID: CGWindowID, _ image: NSImage) {
        lock.lock()
        cache[windowID] = (Date(), image)
        if cache.count > 40 {
            let stale = cache.filter { Date().timeIntervalSince($0.value.0) > 4 }.map(\.key)
            stale.forEach { cache.removeValue(forKey: $0) }
        }
        lock.unlock()
    }

    private static func cgCapture(_ windowID: CGWindowID, maxPixel: CGFloat) -> NSImage? {
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .nominalResolution]
        ), image.width > 8, image.height > 8 else {
            return nil
        }
        return scaled(image, maxPixel: maxPixel)
    }

    private static func sckCapture(_ windowIDs: [CGWindowID], maxPixel: CGFloat, then: @escaping ([CGWindowID: NSImage]) -> Void) {
        guard isTrusted else { return }
        let wanted = Set(windowIDs)
        let apply: (SCShareableContent) -> Void = { content in
            let group = DispatchGroup()
            let foundLock = NSLock()
            var found: [CGWindowID: NSImage] = [:]
            for window in content.windows where wanted.contains(window.windowID) {
                group.enter()
                let filter = SCContentFilter(desktopIndependentWindow: window)
                let config = SCStreamConfiguration()
                let size = window.frame.size
                let scale = min(maxPixel / max(size.width, 1), maxPixel / max(size.height, 1), 1)
                config.width = max(Int((size.width * scale).rounded()), 16)
                config.height = max(Int((size.height * scale).rounded()), 16)
                config.showsCursor = false
                config.scalesToFit = true
                let windowID = window.windowID
                SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, _ in
                    defer { group.leave() }
                    guard let image else { return }
                    let ns = scaled(image, maxPixel: maxPixel)
                    store(windowID, ns)
                    foundLock.lock()
                    found[windowID] = ns
                    foundLock.unlock()
                }
            }
            group.notify(queue: .main) {
                foundLock.lock()
                let images = found
                foundLock.unlock()
                if !images.isEmpty {
                    then(images)
                }
            }
        }

        lock.lock()
        let cached = shareable
        let fresh = Date().timeIntervalSince(shareableAt) < 2
        lock.unlock()
        if let cached, fresh {
            apply(cached)
            return
        }

        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { content, _ in
            guard let content else { return }
            lock.lock()
            shareable = content
            shareableAt = Date()
            lock.unlock()
            apply(content)
        }
    }

    private static func scaled(_ image: CGImage, maxPixel: CGFloat) -> NSImage {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let scale = min(maxPixel / max(width, 1), maxPixel / max(height, 1), 1)
        let size = NSSize(width: max(width * scale, 1), height: max(height * scale, 1))
        return NSImage(cgImage: image, size: size)
    }
}
