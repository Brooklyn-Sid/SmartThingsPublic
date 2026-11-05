import XCTest
@testable import MedSupply

final class SupplyMathTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    func testRunOutDateOncePerDay() {
        let runOut = SupplyMath.runOutDate(start: 30, refreshed: day(2026, 11, 5), dailyUsage: 1, calendar: cal)
        XCTAssertEqual(runOut, cal.startOfDay(for: day(2026, 12, 5)))
    }

    func testRunOutDateTwoPillsTwiceDaily() {
        // 60 pills, 2 per dose, twice a day = 4/day → 15 days.
        let runOut = SupplyMath.runOutDate(start: 60, refreshed: day(2026, 11, 5), dailyUsage: 4, calendar: cal)
        XCTAssertEqual(runOut, cal.startOfDay(for: day(2026, 11, 20)))
    }

    func testPartialDayRoundsDown() {
        // 10 pills at 3/day → 3 full days.
        let runOut = SupplyMath.runOutDate(start: 10, refreshed: day(2026, 11, 5), dailyUsage: 3, calendar: cal)
        XCTAssertEqual(runOut, cal.startOfDay(for: day(2026, 11, 8)))
    }

    func testNoUsageMeansNoProjection() {
        XCTAssertNil(SupplyMath.runOutDate(start: 30, refreshed: .now, dailyUsage: 0, calendar: cal))
    }

    func testEstimatedCountDecreasesAndClampsAtZero() {
        let refreshed = day(2026, 11, 5, hour: 20)
        XCTAssertEqual(SupplyMath.estimatedCount(start: 30, refreshed: refreshed, dailyUsage: 1,
                                                 on: day(2026, 11, 5, hour: 8), calendar: cal), 30)
        XCTAssertEqual(SupplyMath.estimatedCount(start: 30, refreshed: refreshed, dailyUsage: 1,
                                                 on: day(2026, 11, 15), calendar: cal), 20)
        XCTAssertEqual(SupplyMath.estimatedCount(start: 30, refreshed: refreshed, dailyUsage: 1,
                                                 on: day(2027, 1, 15), calendar: cal), 0)
    }

    func testEstimatedCountAcrossDSTChange() {
        // US DST ends Nov 1, 2026; day counting must still be whole days.
        let count = SupplyMath.estimatedCount(start: 30, refreshed: day(2026, 10, 30), dailyUsage: 1,
                                              on: day(2026, 11, 3), calendar: cal)
        XCTAssertEqual(count, 26)
    }
}
