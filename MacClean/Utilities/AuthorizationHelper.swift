import Foundation
import Security

// Global static C string that outlives all authorization calls
private let kSystemPrivilegeAdmin = "system.privilege.admin".utf8CString

class AuthorizationHelper {
    nonisolated(unsafe) private var authorizationRef: AuthorizationRef?
    
    func requestAdminRights() -> Bool {
        var authRef: AuthorizationRef?
        let status = AuthorizationCreate(nil, nil, AuthorizationFlags(), &authRef)
        
        guard status == errAuthorizationSuccess, let auth = authRef else {
            return false
        }
        
        // Request admin rights using system.privilege.admin
        // Use global static array pointer that outlives the authorization call
        return kSystemPrivilegeAdmin.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return false }
            let namePtr = UnsafePointer<CChar>(baseAddress)
            
            var authItem = AuthorizationItem(
                name: namePtr,
                valueLength: 0,
                value: nil,
                flags: 0
            )
            
            // Create rights with mutable pointer that outlives the call
            return withUnsafeMutablePointer(to: &authItem) { itemPtr in
                var authRights = AuthorizationRights(count: 1, items: itemPtr)
                let authFlags: AuthorizationFlags = [
                    .interactionAllowed,
                    .extendRights,
                    .preAuthorize
                ]
                
                let authStatus = AuthorizationCopyRights(
                    auth,
                    &authRights,
                    nil,
                    authFlags,
                    nil
                )
                
                if authStatus == errAuthorizationSuccess {
                    self.authorizationRef = auth
                    return true
                }
                
                return false
            }
        }
    }
    
    func deleteDirectoryContents(at path: String) throws -> (itemsDeleted: Int, spaceFreed: Int64) {
        guard authorizationRef != nil else {
            throw CleanupError.authorizationFailed
        }
        
        // Use rm command with authorization
        // First, get the size before deletion
        let fileManager = FileManager.default
        let url = URL(fileURLWithPath: path)
        
        guard fileManager.fileExists(atPath: path) else {
            return (0, 0)
        }
        
        let sizeBefore = fileManager.sizeOfDirectory(at: url)
        let countBefore = fileManager.countItems(in: url)
        
        // Use Process to execute rm with elevated privileges
        // Note: This requires the authorization to be valid
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/rm")
        process.arguments = ["-rf", "\(path)/*"]
        
        // Note: In a production app, you'd use SMJobBless with a helper tool
        // For now, we'll try direct deletion which may still fail without proper setup
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                return (countBefore, sizeBefore)
            } else {
                throw CleanupError.deletionFailed("rm command failed with status \(process.terminationStatus)")
            }
        } catch {
            throw CleanupError.deletionFailed("Failed to execute deletion: \(error.localizedDescription)")
        }
    }
    
    var hasAuthorization: Bool {
        return authorizationRef != nil
    }
    
    func freeAuthorization() {
        if let authRef = authorizationRef {
            AuthorizationFree(authRef, AuthorizationFlags())
            self.authorizationRef = nil
        }
    }
    
    deinit {
        // Access property directly in deinit - deinit is always nonisolated
        if let authRef = authorizationRef {
            AuthorizationFree(authRef, AuthorizationFlags())
        }
    }
}

