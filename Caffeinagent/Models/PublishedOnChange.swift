import Combine

/// `@Published` that says nothing when the new value equals the old one.
///
/// `@Published` sends `objectWillChange` on every write, also of an equal
/// value. SwiftUI then works out the scenes and the menu bar label again
/// for nothing, and a scene that writes its own state back through a
/// binding (`MenuBarExtra(isInserted:)` on macOS 26) never comes to rest.
@propertyWrapper
struct PublishedOnChange<Value: Equatable> {
    private var value: Value

    init(wrappedValue: Value) {
        value = wrappedValue
    }

    @available(*, unavailable, message: "@PublishedOnChange is for the properties of a class")
    var wrappedValue: Value {
        get { fatalError() }
        set { fatalError() }
    }

    static subscript<Owner: ObservableObject>(
        _enclosingInstance owner: Owner,
        wrapped _: ReferenceWritableKeyPath<Owner, Value>,
        storage storage: ReferenceWritableKeyPath<Owner, PublishedOnChange<Value>>
    ) -> Value where Owner.ObjectWillChangePublisher == ObservableObjectPublisher {
        get { owner[keyPath: storage].value }
        set {
            guard owner[keyPath: storage].value != newValue else { return }
            owner.objectWillChange.send()
            owner[keyPath: storage].value = newValue
        }
    }
}
