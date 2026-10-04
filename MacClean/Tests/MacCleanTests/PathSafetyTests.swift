#if canImport(XCTest)
import XCTest

/// Covers the rules that decide what cleanup is allowed to delete.
/// These run once a unit test target that includes the Tests folder is added to the project.
final class PathSafetyTests: XCTestCase {
    private var temporaryDirectory: URL!
    
    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCleanTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }
    
    func testIsPathInsideComparesWholeComponents() {
        XCTAssertTrue(FileManager.isPath("/Users/me/Desktop", inside: "/Users/me/Desktop"))
        XCTAssertTrue(FileManager.isPath("/Users/me/Desktop/a.txt", inside: "/Users/me/Desktop"))
        XCTAssertFalse(FileManager.isPath("/Users/me/Desktop Backup/a.txt", inside: "/Users/me/Desktop"))
    }
    
    func testIsPathInsideNormalizesDotDot() {
        XCTAssertTrue(FileManager.isPath("/Users/me/Library/Caches/../Preferences/x.plist", inside: "/Users/me/Library/Preferences"))
    }
    
    func testEmptyProtectedPathProtectsNothing() {
        XCTAssertFalse(FileManager.isPath("/Users/me/Library/Caches", inside: ""))
    }
    
    func testUserProtectedPathIsNotDeleted() throws {
        let protectedFile = temporaryDirectory.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: protectedFile)
        
        XCTAssertThrowsError(
            try FileManager.default.safeDelete(at: protectedFile, moveToTrash: false, protectedPaths: [temporaryDirectory.path])
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: protectedFile.path))
    }
    
    func testPermanentDeleteRemovesUnprotectedFile() throws {
        let file = temporaryDirectory.appendingPathComponent("remove.txt")
        try Data("remove".utf8).write(to: file)
        
        let trashURL = try FileManager.default.safeDelete(at: file, moveToTrash: false)
        
        XCTAssertNil(trashURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
    
    func testExcludedFilesAreKept() throws {
        let keep = temporaryDirectory.appendingPathComponent("keep.txt")
        let remove = temporaryDirectory.appendingPathComponent("remove.txt")
        try Data("a".utf8).write(to: keep)
        try Data("b".utf8).write(to: remove)
        
        let files = [
            CleanupFile(path: keep.path, size: 1, modificationDate: Date(), isExcluded: true),
            CleanupFile(path: remove.path, size: 1, modificationDate: Date())
        ]
        let outcome = FileManager.default.safeDeleteFiles(files, category: "Test", moveToTrash: false)
        
        XCTAssertEqual(outcome.itemsDeleted, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: keep.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: remove.path))
    }
    
    func testFileScannerListsFilesNotFolders() throws {
        let folder = temporaryDirectory.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("a".utf8).write(to: folder.appendingPathComponent("a.txt"))
        
        let files = FileScanner.scanFilesSync(at: temporaryDirectory)
        
        XCTAssertEqual(files.map(\.name), ["a.txt"])
    }
    
    func testRotatedLogDetection() {
        XCTAssertTrue(BackgroundFileWork.isRotatedLog(URL(fileURLWithPath: "/var/log/system.log.0.gz")))
        XCTAssertTrue(BackgroundFileWork.isRotatedLog(URL(fileURLWithPath: "/var/log/wifi.log.1")))
        XCTAssertFalse(BackgroundFileWork.isRotatedLog(URL(fileURLWithPath: "/var/log/system.log")))
    }
    
    func testOnlySafeCategoriesArePreselected() {
        XCTAssertFalse(CleanupCategoryType.safeDefaults.contains(.downloads))
        XCTAssertFalse(CleanupCategoryType.safeDefaults.contains(.iosBackups))
        XCTAssertFalse(CleanupCategoryType.safeDefaults.contains(.trash))
        XCTAssertTrue(CleanupCategoryType.safeDefaults.contains(.userCaches))
    }
}
#endif
