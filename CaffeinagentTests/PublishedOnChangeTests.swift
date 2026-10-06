import Combine
import XCTest

private final class Model: ObservableObject {
    @PublishedOnChange var shown = true
    @PublishedOnChange var names: [String: Int] = [:]
    @PublishedOnChange private(set) var count = 0
    private(set) var observed = 0
    @PublishedOnChange var saved = 0 { didSet { observed += 1 } }

    func setCount(_ value: Int) {
        count = value
    }
}

final class PublishedOnChangeTests: XCTestCase {
    private var model = Model()
    private var publishes = 0
    private var seenBeforeChange: [Bool] = []
    private var cancellable: AnyCancellable?

    override func setUp() {
        model = Model()
        publishes = 0
        seenBeforeChange = []
        cancellable = model.objectWillChange.sink { [unowned self] in
            publishes += 1
            seenBeforeChange.append(model.shown)
        }
    }

    func testAChangePublishesOnceBeforeTheValueIsSet() {
        model.shown = false
        XCTAssertFalse(model.shown)
        XCTAssertEqual(publishes, 1)
        XCTAssertEqual(seenBeforeChange, [true], "objectWillChange comes before the change")
    }

    /// What `MenuBarExtra(isInserted:)` does on macOS 26: it writes the
    /// value it was given back, every time the scenes are worked out.
    func testWritingTheSameValuePublishesNothing() {
        for _ in 0..<1000 { model.shown = true }
        XCTAssertEqual(publishes, 0)
        model.shown = false
        for _ in 0..<1000 { model.shown = false }
        XCTAssertEqual(publishes, 1)
    }

    func testAChangeInPlacePublishesOnlyWhenItChangesSomething() {
        model.names["claude"] = nil
        XCTAssertEqual(publishes, 0)
        model.names["claude"] = 1
        model.names["claude"] = 1
        XCTAssertEqual(publishes, 1)
        XCTAssertEqual(model.names, ["claude": 1])
    }

    func testPrivateSetterAndInitialValue() {
        XCTAssertEqual(model.count, 0)
        model.setCount(0)
        XCTAssertEqual(publishes, 0)
        model.setCount(2)
        XCTAssertEqual(model.count, 2)
        XCTAssertEqual(publishes, 1)
    }

    /// The observer of the property still runs on every write, so one
    /// that saves the value has to compare for itself.
    func testDidSetRunsOnEveryWrite() {
        model.saved = 0
        model.saved = 1
        XCTAssertEqual(model.observed, 2)
        XCTAssertEqual(publishes, 1)
    }
}
