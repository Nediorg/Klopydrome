import XCTest
@testable import Klopydrome
import NavidromeClient

final class SmartQueryTests: XCTestCase {

    private func song(id: String = "s1",
                      artist: String? = "Уматурман",
                      album: String? = nil,
                      title: String? = "Ночной дозор",
                      genre: String? = "rock",
                      duration: Int? = 200,
                      year: Int? = 2005,
                      playCount: Int? = 10,
                      userRating: Int? = 3,
                      starred: String? = nil) -> SubsonicSong {
        SubsonicSong(id: id, title: title, album: album, artist: artist, year: year,
                     genre: genre, duration: duration, playCount: playCount,
                     starred: starred, userRating: userRating)
    }

    // MARK: Rules

    func testContainsRuleMatchesCaseInsensitive() {
        let rule = QueryExpr(rule: .contains, field: "artist", value: .string("уматурман"))
        XCTAssertTrue(rule.matches(song()))
    }

    func testContainsRuleNoMatch() {
        let rule = QueryExpr(rule: .contains, field: "artist", value: .string("rammstein"))
        XCTAssertFalse(rule.matches(song()))
    }

    func testNumericRule() {
        let gt = QueryExpr(rule: .gt, field: "duration", value: .number(150))
        XCTAssertTrue(gt.matches(song()))
        let gte = QueryExpr(rule: .gte, field: "duration", value: .number(200))
        XCTAssertTrue(gte.matches(song()))
        let lt = QueryExpr(rule: .lt, field: "duration", value: .number(100))
        XCTAssertFalse(lt.matches(song()))
    }

    func testEmptyRuleNeverMatches() {
        let blank = QueryExpr(rule: .contains, field: "artist", value: .string(""))
        XCTAssertFalse(blank.matches(song()))
        let whitespace = QueryExpr(rule: .contains, field: "artist", value: .string("   "))
        XCTAssertFalse(whitespace.matches(song()))
    }

    func testMissingFieldNeverMatches() {
        let rule = QueryExpr(rule: .is_, field: "album", value: .string("Some Album"))
        XCTAssertFalse(rule.matches(song(album: nil)))
    }

    // MARK: Starred

    func testStarredRuleMatchesWhenFavorited() {
        let rule = QueryExpr(rule: .is_, field: "starred", value: .number(1))
        XCTAssertTrue(rule.matches(song(starred: "2024-01-01T00:00:00Z")))
        XCTAssertFalse(rule.matches(song(starred: nil)))
    }

    func testStarredRuleMatchesWhenNotFavorited() {
        let rule = QueryExpr(rule: .is_, field: "starred", value: .number(0))
        XCTAssertTrue(rule.matches(song(starred: nil)))
        XCTAssertFalse(rule.matches(song(starred: "2024-01-01T00:00:00Z")))
    }

    // MARK: Groups

    func testEmptyGroupNeverMatches() {
        let group = QueryExpr(group: .all, children: [])
        XCTAssertFalse(group.matches(song()))
        let any = QueryExpr(group: .any, children: [])
        XCTAssertFalse(any.matches(song()))
    }

    func testAllGroupMatchesEveryRule() {
        let group = QueryExpr(group: .all, children: [
            QueryExpr(rule: .contains, field: "genre", value: .string("rock")),
            QueryExpr(rule: .gte, field: "year", value: .number(2000)),
        ])
        XCTAssertTrue(group.matches(song()))
        XCTAssertFalse(group.matches(song(year: 1999)))
    }

    func testAnyGroupMatchesOneRule() {
        let group = QueryExpr(group: .any, children: [
            QueryExpr(rule: .contains, field: "genre", value: .string("pop")),
            QueryExpr(rule: .gte, field: "playCount", value: .number(5)),
        ])
        XCTAssertTrue(group.matches(song(playCount: 10)))
        XCTAssertFalse(group.matches(song(genre: "classical", playCount: 1)))
    }

    // MARK: JSON round-trip

    func testDSLDecodesFromServerForm() throws {
        let json = """
        {"all":[{"gt":{"duration":180}},{"any":[{"contains":{"artist":"уматурман"}},{"is":{"genre":"rock"}}]} ]}
        """
        let query = try JSONDecoder().decode(SmartQuery.self, from: Data(json.utf8))
        XCTAssertTrue(query.root.isGroup)
        XCTAssertEqual(query.root.groupLogic, .all)
        XCTAssertEqual(query.root.children.count, 2)
        XCTAssertEqual(query.root.children[0].op, .gt)
        XCTAssertEqual(query.root.children[0].field, "duration")
        XCTAssertEqual(query.root.children[0].value, .number(180))
    }

    func testJSONReencodesToCanonicalForm() throws {
        let query = try JSONDecoder().decode(SmartQuery.self, from: Data(
            #"{"all":[{"contains":{"artist":"ref"}}]}"#.utf8))
        let data = try JSONEncoder().encode(query)
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let all = try XCTUnwrap(dict["all"] as? [[String: Any]])
        let contains = try XCTUnwrap(all[0]["contains"] as? [String: Any])
        XCTAssertEqual(contains["artist"] as? String, "ref")
    }

    func testSortMetaRoundTrip() throws {
        let payload = Data(#"{"all":[],"sort":"-random","limit":42,"liveUpdate":false}"#.utf8)
        let query = try JSONDecoder().decode(SmartQuery.self, from: payload)
        XCTAssertEqual(query.sort, "-random")
        XCTAssertEqual(query.limit, 42)
        // The deprecated `liveUpdate` meta key is tolerated on decode but not
        // modelled: an empty limit (absent) means unlimited, not a flag.
    }

    func testSmartSortRoundTripsDirectionPrefix() {
        // A server sort with a direction prefix must map back to the same
        // field (with its original direction), not fall back to title/ascending.
        XCTAssertEqual(SmartSort(json: "-year")?.json(descending: true), "-year")
        XCTAssertEqual(SmartSort(json: "-year"), .year)
        XCTAssertEqual(SmartSort(json: "+rating"), .rating)
        XCTAssertEqual(SmartSort(json: "playCount"), .playCount)
        XCTAssertEqual(SmartSort(json: "-random"), .random)
        // Multi-field sorts aren't a single picker field; they stay verbatim.
        XCTAssertNil(SmartSort(json: "-year,title"))
    }

    // MARK: Engine helpers

    func testGenreHintSingleValue() throws {
        let query = try JSONDecoder().decode(SmartQuery.self, from: Data(
            #"{"all":[{"is":{"genre":"rock"}},{"contains":{"artist":"x"}}]}"#.utf8))
        XCTAssertEqual(SmartQueryMath.genreHint(query), "rock")
    }

    func testGenreHintAmbiguousReturnsNil() throws {
        let query = try JSONDecoder().decode(SmartQuery.self, from: Data(
            #"{"any":[{"is":{"genre":"rock"}},{"is":{"genre":"pop"}}]}"#.utf8))
        XCTAssertNil(SmartQueryMath.genreHint(query))
    }

    func testSortRandomShufflesPool() {
        let songs = (0..<20).map { song(id: "s\($0)", playCount: $0) }
        let sorted = SmartQueryMath.sort(songs, sort: "playCount", shuffle: false)
        XCTAssertEqual(sorted.map(\.playCount), Array(0..<20))
    }

    func testJSONValueEmpty() {
        XCTAssertTrue(JSONValue.string("  ").isEmpty)
        XCTAssertTrue(JSONValue.number(0).isEmpty)
        XCTAssertFalse(JSONValue.string("x").isEmpty)
        XCTAssertFalse(JSONValue.number(3).isEmpty)
    }

    // MARK: Server round-trip bridge

    func testNDJSONDecodesToQuery() throws {
        let ndjson = NDJSON.object([
            "all": .array([
                .object(["gt": .object(["duration": .number(180)])])
            ]),
            "sort": .string("-rating,title"),
            "limit": .number(42)
        ])
        let query = try XCTUnwrap(SmartQuery(ndjson: ndjson))
        XCTAssertTrue(query.root.isGroup)
        XCTAssertEqual(query.root.children[0].op, .gt)
        XCTAssertEqual(query.sort, "-rating,title")
        XCTAssertEqual(query.limit, 42)
    }

    func testNDJSONEncodesQueryLosslessly() throws {
        let json = """
        {"all":[{"contains":{"artist":"ref"}}],"sort":"-year,title",\
        "limitPercent":10,"offset":5,"refreshDelay":"30m","order":"desc","limit":7}
        """
        let payload = Data(json.utf8)
        let query = try JSONDecoder().decode(SmartQuery.self, from: payload)
        let roundTripped = query.ndjsonValue
        let data = try JSONEncoder().encode(roundTripped)
        let reparsed = try JSONDecoder().decode(SmartQuery.self, from: data)
        XCTAssertEqual(reparsed, query)
    }

    func testOrderMetaRoundTrip() throws {
        let payload = Data(#"{"all":[{"is":{"loved":true}}],"sort":"year","order":"desc","limit":25}"#.utf8)
        let query = try JSONDecoder().decode(SmartQuery.self, from: payload)
        XCTAssertEqual(query.sort, "year")
        XCTAssertEqual(query.order, "desc")
        let reparsed = try JSONDecoder().decode(
            SmartQuery.self, from: try JSONEncoder().encode(query))
        XCTAssertEqual(reparsed.order, "desc")
    }

    // MARK: Engine — sort + window

    func testMultiFieldSortWithDirections() {
        let songs = [
            song(id: "s0", year: 2005, userRating: 1),
            song(id: "s1", year: 2005, userRating: 5),
            song(id: "s2", year: 2001, userRating: 4)
        ]
        let sorted = SmartQueryMath.sort(songs, sort: "-year,rating", shuffle: false)
        // Year descending; within a year rating ascending.
        XCTAssertEqual(sorted.map(\.id), ["s0", "s1", "s2"])
    }

    func testGlobalOrderReversesEveryField() {
        let songs = [
            song(id: "s0", year: 2005, userRating: 1),
            song(id: "s1", year: 2005, userRating: 5),
            song(id: "s2", year: 2001, userRating: 4)
        ]
        let sorted = SmartQueryMath.sort(songs, sort: "year,rating", order: "desc", shuffle: false)
        // Everyone reversed: year ascending per field, then rating descending.
        XCTAssertEqual(sorted.map(\.id), ["s1", "s0", "s2"])
    }

    func testWindowAppliesOffsetWithNilLimit() {
        let songs = (0..<10).map { song(id: "s\($0)") }
        XCTAssertEqual(SmartQueryMath.window(songs, offset: nil, limit: nil).count, 10)
        XCTAssertEqual(SmartQueryMath.window(songs, offset: 4, limit: 3).map(\.id), ["s4", "s5", "s6"])
        XCTAssertEqual(SmartQueryMath.window(songs, offset: 8, limit: nil).map(\.id).last, "s9")
        XCTAssertEqual(SmartQueryMath.window(songs, offset: 8, limit: nil).count, 2)
    }
}