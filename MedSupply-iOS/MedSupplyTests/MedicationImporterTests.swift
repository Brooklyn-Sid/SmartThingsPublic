import XCTest
@testable import MedSupply

final class MedicationImporterTests: XCTestCase {
    func testAmountParsing() {
        XCTAssertEqual(MedicationImporter.parseAmount("1 tablet"), 1)
        XCTAssertEqual(MedicationImporter.parseAmount("¼ tablet"), 0.25)
        XCTAssertEqual(MedicationImporter.parseAmount("1/2 tablet"), 0.5)
        XCTAssertEqual(MedicationImporter.parseAmount("1 ½ tablets"), 1.5)
        XCTAssertEqual(MedicationImporter.parseAmount("2"), 2)
        XCTAssertNil(MedicationImporter.parseAmount("tablet"))
    }

    func testScheduleParsing() {
        func perDay(_ s: String) -> Double? {
            guard let parsed = MedicationImporter.parseSchedule(s) else { return nil }
            return parsed.0.dosesPerDay(custom: parsed.1, number: parsed.1)
        }
        XCTAssertEqual(MedicationImporter.parseSchedule("Daily")?.0, .onceDaily)
        XCTAssertEqual(MedicationImporter.parseSchedule("BID")?.0, .twiceDaily)
        XCTAssertEqual(perDay("Twice weekly")!, 2.0 / 7.0, accuracy: 1e-9)
        XCTAssertEqual(perDay("3 times a week")!, 3.0 / 7.0, accuracy: 1e-9)
        XCTAssertEqual(perDay("Every 28 days")!, 1.0 / 28.0, accuracy: 1e-9)
        XCTAssertEqual(perDay("every 2 weeks")!, 1.0 / 14.0, accuracy: 1e-9)
        XCTAssertEqual(MedicationImporter.parseSchedule("As needed")?.0, .asNeeded)
        XCTAssertEqual(MedicationImporter.parseSchedule("Twice weekly")?.0, .timesPerWeek)
        XCTAssertEqual(MedicationImporter.parseSchedule("Twice weekly")?.1, 2)
        XCTAssertEqual(MedicationImporter.parseSchedule("Every 28 days")?.0, .everyNDays)
        XCTAssertEqual(MedicationImporter.parseSchedule("Every 28 days")?.1, 28)
        XCTAssertEqual(MedicationImporter.parseSchedule("once monthly")?.0, .everyNDays)
        XCTAssertNil(MedicationImporter.parseSchedule("with meals sometimes"))
    }

    func testDateParsing() {
        let cal = Calendar.current
        let d1 = MedicationImporter.parseDate("11/1/2026")!
        XCTAssertEqual(cal.dateComponents([.year, .month, .day], from: d1), DateComponents(year: 2026, month: 11, day: 1))
        let d2 = MedicationImporter.parseDate("01/24/27")!
        XCTAssertEqual(cal.dateComponents([.year, .month, .day], from: d2), DateComponents(year: 2027, month: 1, day: 24))
        XCTAssertNotNil(MedicationImporter.parseDate("2026-11-01"))
        XCTAssertNil(MedicationImporter.parseDate("13/40/2026"))
    }

    func testParsesSheetStyleCSV() throws {
        let csv = """
        Medication name,Generic name,Strength,Amount per dose,Schedule,Quantity on hand,Count verified date,Estimated run-out date,Pharmacy,Prescription number,Prescribing doctor,Refills remaining,Controlled
        Lipitor,atorvastatin,20 mg,1 tablet,Daily,30.00,11/1/2026,12/01/26,Corner Pharmacy,RX-1,Dr. Smith,3,
        Example Patch,"thyroid, porcine (desiccated)",0.1 mg,1 patch,Twice weekly,8,11/1/2026,,Corner Pharmacy,,Dr. Smith,,
        Pen,,5 mg,1 injection,Every 28 days,3,11/1/2026,,Mail order,,Dr. Jones,,yes
        ,,,,,,,,,,,,
        """
        let today = MedicationImporter.parseDate("11/7/2026")!
        let rows = try MedicationImporter.parse(csv, today: today)
        XCTAssertEqual(rows.count, 3)

        let first = rows[0].draft
        XCTAssertEqual(first.brandName, "Lipitor")
        XCTAssertEqual(first.genericName, "atorvastatin")
        XCTAssertEqual(first.dose, "20 mg")
        XCTAssertEqual(first.count, 30)
        XCTAssertEqual(first.frequency, .onceDaily)
        XCTAssertEqual(first.rxNumber, "RX-1")
        XCTAssertEqual(first.refillsRemaining, 3)
        XCTAssertFalse(first.isControlled)
        XCTAssertTrue(rows[0].warnings.isEmpty)

        XCTAssertEqual(rows[1].draft.genericName, "thyroid, porcine (desiccated)")
        XCTAssertNil(rows[1].draft.refillsRemaining)

        XCTAssertEqual(rows[1].draft.unitName, "patch")
        XCTAssertEqual(rows[1].draft.scheduleText, "1 patch twice a week")

        XCTAssertTrue(rows[2].draft.isControlled)
        XCTAssertEqual(rows[2].draft.frequency, .everyNDays)
        XCTAssertEqual(rows[2].draft.scheduleText, "1 injection every 28 days")
    }

    func testUnitParsing() {
        XCTAssertEqual(MedicationImporter.parseUnit("1 patch"), "patch")
        XCTAssertEqual(MedicationImporter.parseUnit("¼ tablet"), "tablet")
        XCTAssertEqual(MedicationImporter.parseUnit("2 capsules"), "capsule")
        XCTAssertEqual(MedicationImporter.parseUnit("1 injection"), "injection")
        XCTAssertEqual(MedicationImporter.parseUnit("1 pill"), "tablet")
        XCTAssertNil(MedicationImporter.parseUnit("2"))
    }

    func testFormatting() {
        XCTAssertEqual(Fmt.unit("patch", count: 8), "patches")
        XCTAssertEqual(Fmt.unit("tablet", count: 1), "tablet")
        XCTAssertEqual(Fmt.unit("tablet", count: 20.25), "tablets")
        XCTAssertEqual(Fmt.amount(0.25), "¼")
        XCTAssertEqual(Fmt.amount(1.5), "1½")
        XCTAssertEqual(Fmt.amount(2), "2")
    }

    func testMissingNameColumnThrows() {
        XCTAssertThrowsError(try MedicationImporter.parse("Foo,Bar\n1,2"))
    }
}
