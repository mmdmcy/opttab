import AppKit
import ApplicationServices
import Carbon
import Darwin

enum PrivateCalls {
    private static let userGenerated: UInt32 = 0x200

    static func cgWindowID(of element: AXUIElement) -> CGWindowID? {
        guard let fn = axGetWindow else { return nil }
        var id: CGWindowID = 0
        return fn(element, &id) == .success && id != 0 ? id : nil
    }

    @discardableResult
    static func focusWindow(pid: pid_t, windowID: CGWindowID, previousWindowID: CGWindowID? = nil) -> Bool {
        guard windowID != 0 else {
            makeFront(pid: pid)
            return false
        }
        guard let getPSN = getProcessForPID, let setFront = slpsSetFront else {
            NSLog("OptTab: SkyLight window symbols missing; using Accessibility fallback")
            return false
        }
        var psn = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: 0)
        let status = getPSN(pid, &psn)
        guard status == 0 else {
            NSLog("OptTab: GetProcessForPID failed pid=%d status=%d", pid, status)
            return false
        }
        if let previousWindowID, previousWindowID != 0, previousWindowID != windowID {
            postSpecial(&psn, windowID: previousWindowID, kind: 0x0D, marker: 0x02)
        }
        let result = setFront(&psn, windowID, userGenerated)
        makeKey(&psn, windowID)
        orderFront(windowID)
        if let previousWindowID, previousWindowID != 0, previousWindowID != windowID {
            postSpecial(&psn, windowID: windowID, kind: 0x0D, marker: 0x01)
            _ = setFront(&psn, windowID, userGenerated)
            makeKey(&psn, windowID)
            orderFront(windowID)
        }
        return result == 0
    }

    static func makeFront(pid: pid_t) {
        guard let getPSN = getProcessForPID, let setFront = slpsSetFront else { return }
        var psn = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: 0)
        guard getPSN(pid, &psn) == 0 else { return }
        _ = setFront(&psn, 0, userGenerated)
    }

    static func orderFront(_ windowID: CGWindowID) {
        guard windowID != 0, let connection = slsMainConnection?(), let order = slsOrderWindow else { return }
        _ = order(connection, windowID, 1, 0)
    }

    private static func makeKey(_ psn: inout ProcessSerialNumber, _ windowID: CGWindowID) {
        guard slpsPost != nil else { return }
        var bytes = eventBytes(windowID: windowID)
        bytes[0x08] = 0x01
        postEvent(&psn, &bytes)
        bytes[0x08] = 0x02
        postEvent(&psn, &bytes)
    }

    private static func postSpecial(
        _ psn: inout ProcessSerialNumber,
        windowID: CGWindowID,
        kind: UInt8,
        marker: UInt8
    ) {
        var bytes = eventBytes(windowID: windowID)
        bytes[0x08] = kind
        bytes[0x8A] = marker
        postEvent(&psn, &bytes)
    }

    private static func eventBytes(windowID: CGWindowID) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 0x100)
        bytes[0x04] = 0xF8
        bytes[0x3A] = 0x10
        var id = windowID
        withUnsafeBytes(of: &id) { raw in
            for (offset, byte) in raw.enumerated() {
                bytes[0x3C + offset] = byte
            }
        }
        var point = CGPoint(x: 300_000, y: 300_000)
        withUnsafeBytes(of: &point) { raw in
            for (offset, byte) in raw.enumerated() {
                bytes[0x20 + offset] = byte
            }
        }
        return bytes
    }

    private static func postEvent(_ psn: inout ProcessSerialNumber, _ bytes: inout [UInt8]) {
        guard let post = slpsPost else { return }
        bytes.withUnsafeMutableBufferPointer { buffer in
            if let ptr = buffer.baseAddress {
                _ = post(&psn, ptr)
            }
        }
    }

    private static let axGetWindow: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError)? = {
        symbol(
            "_AXUIElementGetWindow",
            as: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError).self,
            in: [
                "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices",
                "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
            ]
        )
    }()

    private static let getProcessForPID: (@convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> Int32)? = {
        symbol(
            "GetProcessForPID",
            as: (@convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> Int32).self,
            in: [
                "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices",
                "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
            ]
        )
    }()

    private static let slpsSetFront: (@convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> Int32)? = {
        symbol(
            "_SLPSSetFrontProcessWithOptions",
            as: (@convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> Int32).self,
            in: ["/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"]
        )
    }()

    private static let slpsPost: (@convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> Int32)? = {
        symbol(
            "SLPSPostEventRecordTo",
            as: (@convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> Int32).self,
            in: ["/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"]
        )
    }()

    private static let slsMainConnection: (@convention(c) () -> Int32)? = {
        symbol(
            "SLSMainConnectionID",
            as: (@convention(c) () -> Int32).self,
            in: [
                "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
                "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight",
            ]
        )
    }()

    private static let slsOrderWindow: (@convention(c) (Int32, CGWindowID, Int32, CGWindowID) -> Int32)? = {
        symbol(
            "SLSOrderWindow",
            as: (@convention(c) (Int32, CGWindowID, Int32, CGWindowID) -> Int32).self,
            in: [
                "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
                "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight",
            ]
        )
    }()

    private static func symbol<T>(_ name: String, as: T.Type, in paths: [String]) -> T? {
        for path in paths {
            guard let handle = dlopen(path, RTLD_LAZY), let pointer = dlsym(handle, name) else { continue }
            return unsafeBitCast(pointer, to: T.self)
        }
        return nil
    }
}
