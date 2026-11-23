import XCTest

/// The release notes both apps read: plain items for the Mac, and lead-ins and symbols for the iPhone.
final class ReleaseNotesTests: XCTestCase {
    func testPlainNotes() {
        let notes = ReleaseNotes.parse("""
            <h2>Fifteen 1.3</h2>
            <p>Your calendar, next to the timer.</p>
            <ul>
              <li>See today&rsquo;s events.</li>
              <li>Fifteen now asks before it quits.</li>
            </ul>
            """, version: "1.3")
        XCTAssertEqual(notes.title, "Fifteen 1.3")
        XCTAssertEqual(notes.intro, "Your calendar, next to the timer.")
        XCTAssertEqual(notes.items, ["See today’s events.", "Fifteen now asks before it quits."])
        XCTAssertEqual(notes.entries.map(\.text), notes.items)
        XCTAssertEqual(notes.entries.compactMap(\.title), [])
        XCTAssertEqual(notes.entries.compactMap(\.symbol), [])
    }

    func testLeadInsAndSymbols() {
        let notes = ReleaseNotes.parse("""
            <ul>
              <li data-symbol="calendar"><strong>Calendar.</strong> See today's events
                  from the top of the timer.</li>
              <li><strong>Reminders</strong></li>
              <li data-symbol="lock.iphone">Breaks keep time.</li>
            </ul>
            """, version: "1.4")
        XCTAssertEqual(notes.entries, [
            .init(title: "Calendar.", text: "See today's events from the top of the timer.", symbol: "calendar"),
            .init(title: "Reminders", text: "", symbol: nil),
            .init(title: nil, text: "Breaks keep time.", symbol: "lock.iphone"),
        ])
        // The Mac still sees each item as one line.
        XCTAssertEqual(notes.items.first, "Calendar. See today's events from the top of the timer.")
        XCTAssertEqual(notes.title, "Fifteen 1.4")
    }
}
