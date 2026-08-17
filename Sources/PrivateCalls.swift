import AppKit
import ApplicationServices
import Darwin

enum PrivateCalls {
    static func cgWindowID(of element: AXUIElement) -> CGWindowID? {
        guard let fn = axGetWindow else { return nil }
        var id: CGWindowID = 0
        return fn(element, &id) == .success && id != 0 ? id : nil
    }

    static func setFront(pid: pid_t, windowID: CGWindowID) {
        guard let setFront = slpsSetFront, let getPSN = getProcessForPID else { return }
        let psn = UnsafeMutablePointer<UInt32>.allocate(capacity: 2)
        psn.initialize(repeating: 0, count: 2)
        defer {
            psn.deinitialize(count: 2)
            psn.deallocate()
        }
        guard getPSN(pid, UnsafeMutableRawPointer(psn)) == 0 else { return }
        _ = setFront(UnsafeMutableRawPointer(psn), windowID, 1)
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

    private static let getProcessForPID: (@convention(c) (pid_t, UnsafeMutableRawPointer) -> Int32)? = {
        symbol(
            "GetProcessForPID",
            as: (@convention(c) (pid_t, UnsafeMutableRawPointer) -> Int32).self,
            in: [
                "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices",
                "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
            ]
        )
    }()

    private static let slpsSetFront: (@convention(c) (UnsafeMutableRawPointer, CGWindowID, UInt32) -> Int32)? = {
        symbol(
            "_SLPSSetFrontProcessWithOptions",
            as: (@convention(c) (UnsafeMutableRawPointer, CGWindowID, UInt32) -> Int32).self,
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
