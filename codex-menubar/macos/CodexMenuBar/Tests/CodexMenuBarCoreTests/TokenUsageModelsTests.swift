import XCTest
@testable import CodexMenuBarCore

final class TokenUsageModelsTests: XCTestCase {
    func testFirstCumulativeValueIsMeasuredFromZero() {
        let current = TokenCounts(
            total: 120,
            input: 90,
            cachedInput: 40,
            output: 30,
            reasoning: 7
        )

        XCTAssertEqual(current.increment(since: nil), current)
    }

    func testEqualCumulativeValuesProduceZeroIncrement() {
        let counts = TokenCounts(
            total: 120,
            input: 90,
            cachedInput: 40,
            output: 30,
            reasoning: 7
        )

        XCTAssertEqual(counts.increment(since: counts), .zero)
    }

    func testDeltaRestartsOnlyFieldsThatDecrease() {
        let previous = TokenCounts(
            total: 100,
            input: 80,
            cachedInput: 30,
            output: 20,
            reasoning: 5
        )
        let current = TokenCounts(
            total: 140,
            input: 10,
            cachedInput: 35,
            output: 30,
            reasoning: 2
        )

        XCTAssertEqual(
            current.increment(since: previous),
            TokenCounts(
                total: 40,
                input: 10,
                cachedInput: 5,
                output: 10,
                reasoning: 2
            )
        )
    }

    func testAdditionKeepsTokenCategoriesIndependent() {
        let lhs = TokenCounts(total: 100, input: 70, cachedInput: 30, output: 30, reasoning: 4)
        let rhs = TokenCounts(total: 60, input: 40, cachedInput: 10, output: 20, reasoning: 3)

        XCTAssertEqual(
            lhs + rhs,
            TokenCounts(total: 160, input: 110, cachedInput: 40, output: 50, reasoning: 7)
        )
    }
}
