public typealias ComponentID = ObjectIdentifier

public typealias Component = BitwiseCopyable

public struct ComponentLayout: Sendable {
    public let stride: Int
    public let alignment: Int

    public init<T: Component>(_ type: T.Type) {
        self.stride = MemoryLayout<T>.stride
        self.alignment = MemoryLayout<T>.alignment
    }
}
