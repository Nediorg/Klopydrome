import XCTest
@testable import NavidromeClient

final class CacheTests: XCTestCase {

    private var tempDir: URL!
    private var cache: CacheManager!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CacheTests-\(UUID().uuidString)", isDirectory: true)
        cache = CacheManager(rootURL: tempDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testWriteAndRead() async throws {
        let data = Data("hello".utf8)
        try await cache.write(data: data, to: .covers, key: "abc-300.img")
        let hasFile = await cache.hasFile(for: .covers, key: "abc-300.img")
        XCTAssertTrue(hasFile)
        let readData = await cache.readData(for: .covers, key: "abc-300.img")
        XCTAssertEqual(readData, data)
    }

    func testMoveFile() async throws {
        let source = tempDir.appendingPathComponent("tmp.bin")
        try Data("payload".utf8).write(to: source)
        let url = try await cache.moveFile(from: source, to: .streams, key: "song1.mp3")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    func testKeySanitization() {
        let bad = cache.fileURL(for: .covers, key: "../evil/name with spaces😀")
        XCTAssertFalse(bad.path.contains(".."))
        XCTAssertFalse(bad.path.contains(" "))
    }

    func testFileKeysListsOnDiskFiles() async throws {
        try await cache.write(data: Data("a".utf8), to: .streams, key: "song1.mp3")
        try await cache.write(data: Data("b".utf8), to: .streams, key: "song2.flac")
        try await cache.write(data: Data("c".utf8), to: .streams, key: "song3.mp3")
        await cache.removeFile(for: .streams, key: "song2.flac")
        // Extensions survive sanitization so AVPlayer can sniff the format of
        // a cached stream by its file name; the list reports on-disk names,
        // which match what `isCached` looks up.
        let streamKeys = await cache.fileKeys(for: .streams)
        let coverKeys = await cache.fileKeys(for: .covers)
        XCTAssertEqual(Set(streamKeys), ["song1.mp3", "song3.mp3"])
        XCTAssertTrue(coverKeys.isEmpty)
    }

    /// A stream's cache file must keep its audio extension (AVPlayer resolves
    /// local file formats from the file name), and the file must be seekable
    /// by the same key afterwards.
    func testStreamFileKeepsExtension() async throws {
        let source = tempDir.appendingPathComponent("tmp.bin")
        try Data("payload".utf8).write(to: source)
        let url = try await cache.moveFile(from: source, to: .streams, key: "song1.mp3")
        XCTAssertEqual(url.pathExtension, "mp3")
        let hasFile = await cache.hasFile(for: .streams, key: "song1.mp3")
        XCTAssertTrue(hasFile)
    }

    func testEvictionByTotalLimit() async throws {
        let small = CacheLimits(maxTotalBytes: 300, maxCoversBytes: 300,
                                maxStreamsBytes: 300, maxMetadataBytes: 300)
        await cache.setLimits(small)
        try await cache.write(data: Data(repeating: 1, count: 200), to: .streams, key: "one.mp3")
        try await cache.write(data: Data(repeating: 2, count: 200), to: .streams, key: "two.mp3")
        // After the second write, eviction should have removed the oldest file.
        let hasOne = await cache.hasFile(for: .streams, key: "one.mp3")
        let hasTwo = await cache.hasFile(for: .streams, key: "two.mp3")
        XCTAssertTrue(hasTwo, "newest file should survive")
        XCTAssertFalse(hasOne, "oldest file should have been evicted")
        let total = await cache.totalBytesAsync()
        XCTAssertLessThanOrEqual(total, 300)
    }

    func testClear() async throws {
        try await cache.write(data: Data([1]), to: CacheKind.metadata, key: "k1")
        try await cache.write(data: Data([2]), to: CacheKind.metadata, key: "k2")
        await cache.clear(kind: CacheKind.metadata)
        let has1 = await cache.hasFile(for: CacheKind.metadata, key: "k1")
        let has2 = await cache.hasFile(for: CacheKind.metadata, key: "k2")
        XCTAssertFalse(has1)
        XCTAssertFalse(has2)
    }

    func testMetadataKeyStable() {
        let a = [URLQueryItem(name: "query", value: "hi"), URLQueryItem(name: "size", value: "20")]
        let b = [URLQueryItem(name: "size", value: "20"), URLQueryItem(name: "query", value: "hi")]
        XCTAssertEqual(CacheManager.metadataKey(endpoint: "search3", params: a),
                       CacheManager.metadataKey(endpoint: "search3", params: b))
    }

    // MARK: Artist discography cache

    func testDiscographyCacheRoundTrip() async throws {
        let pool = [SubsonicSong(id: "s1", title: "t1"),
                    SubsonicSong(id: "s2", title: "t2")]
        let initial = await cache.cachedDiscography(for: "artist-1")
        XCTAssertNil(initial)
        await cache.cacheDiscography(pool, for: "artist-1")
        let cached1 = await cache.cachedDiscography(for: "artist-1")
        XCTAssertEqual(cached1, pool)
        let cached2 = await cache.cachedDiscography(for: "artist-2")
        XCTAssertNil(cached2)
    }

    func testClearEmptiesDiscographyCache() async throws {
        await cache.cacheDiscography([SubsonicSong(id: "s1")], for: "artist-1")
        await cache.clear()
        let cached = await cache.cachedDiscography(for: "artist-1")
        XCTAssertNil(cached)
    }
}