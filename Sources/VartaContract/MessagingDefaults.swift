import Foundation

#if os(macOS)
import Darwin
#endif

public enum MessagingDefaults {

    public static func defaultServiceRoot() -> URL {
        userHomeDirectory().appendingPathComponent("Messaging", isDirectory: true)
    }

    private static func userHomeDirectory() -> URL {
        #if os(macOS)
        if let passwd = getpwuid(getuid()),
           let home = passwd.pointee.pw_dir {
            let path = String(cString: home)
            if !path.isEmpty {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        #endif

        return FileManager.default.homeDirectoryForCurrentUser
    }
}
