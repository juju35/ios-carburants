@testable import CarburantsKit
import XCTest

final class ParsingTests: XCTestCase {
    private func stations() throws -> [Station] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "records", withExtension: "json", subdirectory: "Fixtures"))
        return try CarburantsAPI.parseRecords(Data(contentsOf: url))
    }

    func testPricesShortagesAndEndedShortages() throws {
        let station = try XCTUnwrap(stations().first)
        XCTAssertEqual(station.id, 35000001)
        XCTAssertEqual(station.latitude, 48.1046, accuracy: 1e-6)
        XCTAssertEqual(station.price(.gazole), 1.689)
        XCTAssertNotNil(station.fuels[.gazole]?.updated)
        XCTAssertNotNil(station.fuels[.sp98]?.updated)

        // Temporary shortage: sold here, no price.
        XCTAssertTrue(station.sells(.e10))
        XCTAssertNil(station.price(.e10))
        XCTAssertNotNil(station.fuels[.e10]?.ruptureSince)

        // Ended shortage: kept without a price.
        XCTAssertNotNil(station.fuels[.e85])
        XCTAssertFalse(station.fuels[.e85]?.available ?? true)

        XCTAssertFalse(station.sells(.gplc))
        XCTAssertTrue(station.automate24)
        XCTAssertEqual(station.services, ["Boutique alimentaire", "Gonflage"])
        XCTAssertEqual(station.hours.map(\.day), [1, 7])
        XCTAssertEqual(station.hours.first?.ranges, [TimeRange(open: "07:00", close: "21:00")])
        XCTAssertTrue(station.hours.last?.closed ?? false)
    }

    func testStringIdHighwayAndDefinitiveShortage() throws {
        let station = try XCTUnwrap(stations().last)
        XCTAssertEqual(station.id, 35700002)
        XCTAssertTrue(station.highway)
        XCTAssertFalse(station.sells(.gplc))
        XCTAssertFalse(station.sellsAny(Fuel.allCases))
    }

    func testBestAndSort() throws {
        let list = Station.samples
        let sorted = StationSort.sorted(list, by: .price, fuels: [.e10, .gazole])
        XCTAssertEqual(sorted.first?.best([.e10, .gazole])?.fuel, .gazole)
        XCTAssertEqual(StationSort.sorted(list, by: .distance, fuels: [.gazole]).first?.id, 35000001)
    }
}

final class TextTests: XCTestCase {
    func testNames() {
        XCTAssertEqual(TextCase.name("RELAIS LES TROIS MARCHES"), "Relais les Trois Marches")
        XCTAssertEqual(TextCase.name("STATION D'ACIGNE RN12"), "Station d'Acigne RN12")
        XCTAssertEqual(TextCase.name("Super U Rennes"), "Super U Rennes")
        XCTAssertEqual(TextCase.address("21 avenue CHARLES TILLON"), "21 avenue Charles Tillon")
        XCTAssertEqual(TextCase.city("SAINT-GREGOIRE"), "Saint-Gregoire")
        XCTAssertEqual(TextCase.key("E. Leclerc"), "eleclerc")
        XCTAssertEqual(TextCase.key("Intermarché"), "intermarche")
    }

    func testUsefulOsmName() {
        XCTAssertNil(StationRepository.usefulOsmName("Station-service", brand: "Total"))
        XCTAssertNil(StationRepository.usefulOsmName("TotalEnergies", brand: "TotalEnergies"))
        XCTAssertNil(StationRepository.usefulOsmName("Total", brand: "TotalEnergies"))
        XCTAssertEqual(StationRepository.usefulOsmName("Relais de Bretagne", brand: "Avia"), "Relais de Bretagne")
    }

    func testBrandIndexFallsBackToShorterNames() {
        let index = ["intermarche": "Q3153200"]
        XCTAssertEqual(BrandIndex.qid("Intermarché Super Rennes", in: index), "Q3153200")
        XCTAssertNil(BrandIndex.qid("Avia", in: index))
    }

    func testFormat() {
        XCTAssertEqual(Format.distance(0.847), "850 m")
        XCTAssertEqual(Format.distance(3.42), "3,4 km")
        XCTAssertEqual(Format.distance(12.4), "12 km")
        XCTAssertEqual(Format.price(1.749), "1,749 €")
        XCTAssertEqual(Format.fuels([.e10, .sp98]), "E10, SP98")
    }
}

final class OpeningTests: XCTestCase {
    private func date(_ text: String) -> Date {
        // Monday 2026-10-19 in French time (UTC+2).
        ISO8601DateFormatter().date(from: text)!
    }

    private let station = Station(
        id: 1, address: "", postcode: "", city: "", latitude: 0, longitude: 0,
        hours: (1...6).map { DayHours(day: $0, closed: false, ranges: [TimeRange(open: "07:00", close: "21:00")]) }
            + [DayHours(day: 7, closed: true, ranges: [])],
        fuels: [:]
    )

    func testOpenClosedAndNextDay() {
        XCTAssertEqual(Opening.of(station, at: date("2026-10-19T10:00:00+02:00"))?.text, "Ouvert · ferme à 21:00")
        XCTAssertEqual(Opening.of(station, at: date("2026-10-19T06:00:00+02:00"))?.text, "Fermé · ouvre à 07:00")
        XCTAssertEqual(Opening.of(station, at: date("2026-10-19T22:00:00+02:00"))?.text, "Fermé · ouvre demain à 07:00")
        // Saturday night: Sunday is closed, Monday next.
        XCTAssertEqual(Opening.of(station, at: date("2026-10-24T22:00:00+02:00"))?.text, "Fermé · ouvre lun. à 07:00")
    }

    func testAlwaysOpen() {
        var always = station
        always.hours = (1...7).map { DayHours(day: $0, closed: false, ranges: [TimeRange(open: "00:00", close: "23:59")]) }
        XCTAssertEqual(Opening.of(always)?.state, .always)
    }
}
