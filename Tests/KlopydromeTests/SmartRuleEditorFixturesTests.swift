import XCTest
@testable import Klopydrome

final class SmartRuleEditorFixturesTests: XCTestCase {

    func testVisualTreeFixtureRoundTripsNativeEditorContract() throws {
        let document = """
        {
          "all": [
            {"contains": {"artist": "Björk"}},
            {"inTheRange": {"year": [1993, 2001]}},
            {"any": [
              {"is": {"vendorMood": "immersive"}},
              {"all": [
                {"gte": {"playcount": 3}},
                {"contains": {"genre": "electronic"}}
              ]}
            ]}
          ],
          "sort": "-year,title",
          "order": "desc",
          "limit": 25
        }
        """

        let query = try JSONDecoder().decode(SmartQuery.self, from: Data(document.utf8))
        let root = QueryNode(query: query)
        let reencoded = SmartQuery(
            root: root.mapExpr(),
            sort: query.sort,
            limit: query.limit,
            limitPercent: query.limitPercent,
            offset: query.offset,
            refreshDelay: query.refreshDelay,
            order: query.order
        )

        XCTAssertEqual(root.logic, .all)
        XCTAssertEqual(root.children.count, 3)
        XCTAssertEqual(root.children[0].rule?.field, .artist)
        XCTAssertEqual(root.children[0].rule?.op, .contains)
        XCTAssertEqual(root.children[0].rule?.value.text, "Björk")
        XCTAssertEqual(root.children[1].rule?.op, .inTheRange)
        XCTAssertEqual(root.children[1].rule?.value.range, [.number(1993), .number(2001)])

        let anyGroup = try XCTUnwrap(root.children[2])
        XCTAssertEqual(anyGroup.logic, .any)
        XCTAssertEqual(anyGroup.children[1].logic, .all)
        XCTAssertEqual(anyGroup.children[1].children.count, 2)

        let customRule = try XCTUnwrap(anyGroup.children[0].rule)
        XCTAssertEqual(customRule.field, .custom)
        XCTAssertEqual(customRule.customField, "vendorMood")
        XCTAssertEqual(customRule.op, .is_)
        XCTAssertEqual(customRule.value.text, "immersive")

        XCTAssertEqual(reencoded, query)
        XCTAssertEqual(reencoded.sort, "-year,title")
        XCTAssertEqual(reencoded.order, "desc")
        XCTAssertEqual(reencoded.limit, 25)
    }
}
