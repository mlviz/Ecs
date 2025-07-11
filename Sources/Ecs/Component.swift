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

class ComponentArrayBuffer {
    let pointer: UnsafeMutableRawBufferPointer

    init(byteCount: Int, alignment: Int) {
        self.pointer = UnsafeMutableRawBufferPointer.allocate(
            byteCount: byteCount,
            alignment: alignment
        )
    }

    deinit {
        pointer.deallocate()
    }
}

public struct ComponentArray: @unchecked Sendable {
    private let layout: ComponentLayout
    private var buffer: ComponentArrayBuffer
    public private(set) var capacity: Int = 0
    public private(set) var count: Int = 0

    init(layout: ComponentLayout) {
        self.layout = layout
        self.buffer = ComponentArrayBuffer(
            byteCount: layout.stride * capacity,
            alignment: layout.alignment
        )
    }

    mutating func reserveCapacity(_ minimumCapacity: Int) {
        guard minimumCapacity > capacity else { return }
        let newCapacity = Swift.max(minimumCapacity, capacity * 2)
        let new = ComponentArrayBuffer(
            byteCount: layout.stride * newCapacity,
            alignment: layout.alignment
        )
        new.pointer.copyMemory(from: UnsafeRawBufferPointer(self.buffer.pointer))
        self.buffer = new
        capacity = newCapacity
    }

    subscript<T: Component>(_ index: Int) -> T {
        get {
            let pointer = buffer.pointer.assumingMemoryBound(to: T.self)
            return pointer[index]
        }
        mutating set(newValue) {
            ensureUnique()
            let pointer = buffer.pointer.assumingMemoryBound(to: T.self)
            pointer[index] = newValue
        }
    }

    mutating func append(_ bytes: UnsafeRawPointer) {
        reserveCapacity(count + 1)
        ensureUnique()
        let pointer = buffer.pointer.baseAddress!.advanced(by: count * layout.stride)
        pointer.copyMemory(from: bytes, byteCount: layout.stride)
        count += 1
    }

    mutating func append(value: Any) {
        var value = value
        withUnsafeBytes(of: &value) {
            append($0.baseAddress!)
        }
    }

    mutating func removeLast() {
        ensureUnique()
        count -= 1
    }

    mutating func moveLast(to index: Int) {
        ensureUnique()
        let from = count - 1
        let to = index
        if from != to {
            let pointer = buffer.pointer.baseAddress!
            let toPtr = pointer.advanced(by: to * layout.stride)
            let fromPtr = pointer.advanced(by: from * layout.stride)
            toPtr.copyMemory(from: fromPtr, byteCount: layout.stride)
        }
    }

    func pointer(at index: Int) -> UnsafeRawPointer {
        precondition((0..<count).contains(index), "Index out of bounds")
        let pointer = buffer.pointer.baseAddress!.advanced(by: index * layout.stride)
        return UnsafeRawPointer(pointer)
    }

    mutating func pointer(at index: Int) -> UnsafeMutableRawPointer {
        ensureUnique()
        precondition((0..<count).contains(index), "Index out of bounds")
        let pointer = buffer.pointer.baseAddress!.advanced(by: index * layout.stride)
        return pointer
    }

    func buffer<T: Component>(of type: T.Type) -> UnsafeBufferPointer<T> {
        return UnsafeBufferPointer(
            start: buffer.pointer.baseAddress?.assumingMemoryBound(to: T.self),
            count: count
        )
    }

    mutating func buffer<T: Component>(of type: T.Type) -> UnsafeMutableBufferPointer<T> {
        ensureUnique()
        return UnsafeMutableBufferPointer(
            start: buffer.pointer.baseAddress?.assumingMemoryBound(to: T.self),
            count: count
        )
    }
}

// private
extension ComponentArray {
    private mutating func ensureUnique() {
        if !isKnownUniquelyReferenced(&buffer) {
            let new = ComponentArrayBuffer(
                byteCount: layout.stride * capacity,
                alignment: layout.alignment
            )
            new.pointer.copyMemory(from: UnsafeRawBufferPointer(self.buffer.pointer))
            buffer = new
        }
    }
}
