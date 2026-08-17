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

    static func focusWindow(pid: pid_t, windowID: CGWindowID) {
        guard let getPSN = getProcessForPID, let setFront = slpsSetFront else { return }
        var psn = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: 0)
        guard getPSN(pid, &psn) == 0 else { return }
        _ = setFront(&psn, windowID, userGenerated)
        makeKey(&psn, windowID)
    }

    private static func makeKey(_ psn: inout ProcessSerialNumber, _ windowID: CGWindowID) {
        guard let post = slpsPost else { return }
        var bytes = [UInt8](repeating: 0, count: 0xF8)
        bytes[0x04] = 0xF8
        bytes[0x3A] = 0x10
        var id = windowID
        withUnsafeBytes(of: &id) { raw in
            for (offset, byte) in raw.enumerated() {
                bytes[0x3C + offset] = byte
            }
        }
        for i in 0x20..<0x30 {
            bytes[i] = 0xFF
        }
        bytes[0x08] = 0x01
        bytes.withUnsafeMutableBufferPointer { buffer in
            if let ptr = buffer.baseAddress {
                _ = post(&psn, ptr)
            }
        }
        bytes[0x08] = 0x02
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

    private static func symbol<T>(_ name: String, as: T.Type, in paths: [String]) -> T? {
        for path in paths {
            guard let handle = dlopen(path, RTLD_LAZY), let pointer = dlsym(handle, name) else { continue }
            return unsafeBitCast(pointer, to: T.self)
        }
        return nil
    }
}
