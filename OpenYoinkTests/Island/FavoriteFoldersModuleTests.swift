import AppKit
import XCTest
@testable import OpenYoink

@MainActor
final class FavoriteFoldersModuleTests: XCTestCase {
    private var temporaryURLs: [URL] = []

    override func tearDown() {
        for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryURLs = []
    }

    func testPersistenceRoundTripPreservesOrderAndMetadata() throws {
        let directory = try makeTemporaryDirectory()
        let persistence = FavoriteFoldersPersistenceController(directoryURL: directory)
        let firstAddedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let secondAddedAt = Date(timeIntervalSince1970: 1_700_000_001)
        let first = FavoriteFolder(
            bookmark: Data("first".utf8),
            lastKnownPath: "/tmp/First",
            customDisplayName: "Work",
            addedAt: firstAddedAt
        )
        let second = FavoriteFolder(
            bookmark: Data("second".utf8),
            lastKnownPath: "/tmp/Second",
            addedAt: secondAddedAt
        )

        try persistence.saveNow([first, second])

        XCTAssertEqual(persistence.loadResult(), .loaded([first, second]))
    }

    func testCorruptPersistenceIsQuarantinedWithoutOverwrite() throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appendingPathComponent("folder-favorites.json")
        let corrupt = Data("not json".utf8)
        try corrupt.write(to: fileURL)
        let persistence = FavoriteFoldersPersistenceController(directoryURL: directory)

        XCTAssertEqual(persistence.loadResult(), .failed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("folder-favorites.json.corrupt-") })
    }

    func testAddingFoldersDeduplicatesAndRejectsFiles() throws {
        let folder = try makeTemporaryDirectory()
        let file = folder.appendingPathComponent("note.txt")
        try Data("note".utf8).write(to: file)
        let store = makeStore()
        store.start()

        let first = store.addFolders([folder, file])
        let second = store.addFolders([folder])

        XCTAssertEqual(first, .init(added: 1, duplicates: 0, rejected: 1))
        XCTAssertEqual(second, .init(added: 0, duplicates: 1, rejected: 0))
        XCTAssertEqual(store.items.count, 1)
    }

    func testDefaultOpenDoesNotSpecifyFinderOrAnotherApplication() throws {
        let folder = try makeTemporaryDirectory()
        let opener = FavoriteFolderOpenerSpy()
        let store = makeStore(opener: opener)
        store.start()
        _ = store.addFolders([folder])
        let itemID = try XCTUnwrap(store.items.first?.id)

        XCTAssertTrue(store.open(itemID))
        XCTAssertEqual(opener.openedFolderURLs, [folder.standardizedFileURL])
        XCTAssertEqual(opener.applicationArguments, [nil])
    }

    func testOpenWithApplicationPassesOnlyTheExplicitOverride() throws {
        let folder = try makeTemporaryDirectory()
        let application = URL(fileURLWithPath: "/Applications/QSpace.app")
        let opener = FavoriteFolderOpenerSpy()
        let store = makeStore(opener: opener)
        store.start()
        _ = store.addFolders([folder])
        let itemID = try XCTUnwrap(store.items.first?.id)

        XCTAssertTrue(store.open(itemID, with: application))
        XCTAssertEqual(opener.applicationArguments, [application])
    }

    func testOpenFailureMarksOnlyTheFavoriteUnavailable() throws {
        let folder = try makeTemporaryDirectory()
        let opener = FavoriteFolderOpenerSpy()
        opener.nextErrorMessage = "Handler unavailable"
        let store = makeStore(opener: opener)
        store.start()
        _ = store.addFolders([folder])
        let itemID = try XCTUnwrap(store.items.first?.id)

        XCTAssertTrue(store.open(itemID))

        XCTAssertTrue(store.isUnavailable(itemID))
        XCTAssertTrue(store.noticeIsError)
    }

    func testPasteboardRoutingAcceptsFoldersAndRejectsFiles() throws {
        let folder = try makeTemporaryDirectory()
        let file = folder.appendingPathComponent("note.txt")
        try Data("note".utf8).write(to: file)
        let store = makeStore()

        let folderPasteboard = NSPasteboard(
            name: .init("FavoriteFoldersTests-folder-\(UUID().uuidString)")
        )
        folderPasteboard.clearContents()
        folderPasteboard.writeObjects([folder as NSURL])
        let filePasteboard = NSPasteboard(
            name: .init("FavoriteFoldersTests-file-\(UUID().uuidString)")
        )
        filePasteboard.clearContents()
        filePasteboard.writeObjects([file as NSURL])

        XCTAssertTrue(store.canImportFolders(from: folderPasteboard))
        XCTAssertFalse(store.canImportFolders(from: filePasteboard))
    }

    func testRemoveFavoriteDoesNotDeleteOriginalFolder() throws {
        let folder = try makeTemporaryDirectory()
        let store = makeStore()
        store.start()
        _ = store.addFolders([folder])
        let itemID = try XCTUnwrap(store.items.first?.id)

        store.remove(itemID)

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
    }

    func testMoveRenameAndSelectionRemainOrdered() throws {
        let first = try makeTemporaryDirectory()
        let second = try makeTemporaryDirectory()
        let store = makeStore()
        store.start()
        _ = store.addFolders([first, second])
        let firstID = try XCTUnwrap(store.items.first?.id)
        let secondID = try XCTUnwrap(store.items.last?.id)

        store.move(secondID, before: firstID)
        store.rename(secondID, to: "Projects")
        store.select(secondID)

        XCTAssertEqual(store.items.map(\.id), [secondID, firstID])
        XCTAssertEqual(store.items.first?.displayName, "Projects")
        XCTAssertEqual(store.selectedID, secondID)
    }

    func testStartAndStopAreIdempotent() {
        let store = makeStore()

        store.start()
        store.start()
        XCTAssertTrue(store.isRunning)

        store.stop()
        store.stop()
        XCTAssertFalse(store.isRunning)
    }

    private func makeStore(
        opener: (any FavoriteFolderOpening)? = nil
    ) -> FavoriteFoldersStore {
        FavoriteFoldersStore(
            bookmarkService: BookmarkService(),
            opener: opener ?? FavoriteFolderOpenerSpy()
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "OpenYoink-FavoriteFoldersTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryURLs.append(url)
        return url
    }
}

@MainActor
private final class FavoriteFolderOpenerSpy: FavoriteFolderOpening {
    var defaultApplication: URL?
    var applications: [URL] = []
    private(set) var openedFolderURLs: [URL] = []
    private(set) var applicationArguments: [URL?] = []
    var nextErrorMessage: String?

    func defaultApplicationURL(for folderURL: URL) -> URL? {
        defaultApplication
    }

    func applicationURLs(for folderURL: URL) -> [URL] {
        applications
    }

    func open(
        _ folderURL: URL,
        with applicationURL: URL?,
        completion: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        openedFolderURLs.append(folderURL.standardizedFileURL)
        applicationArguments.append(applicationURL)
        completion(nextErrorMessage)
    }
}
