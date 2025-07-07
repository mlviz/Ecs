public typealias ArchetypeID = [ComponentID]

public struct ArchetypeSchema: Sendable {
    public let layout: [ComponentLayout]
    public let id: [ComponentID]

    public init<T: Component>(componentType: T.Type) {
        self.layout = [ComponentLayout(T.self)]
        self.id = [ComponentID(T.self)]
    }

    /// Does NOT sort or de-duplicate the arrays
    private init(layout: [ComponentLayout], id: [ComponentID]) {
        self.layout = layout
        self.id = id
    }

    public func adding<T: Component>(_ type: T.Type) -> ArchetypeSchema {
        let newLayout = ComponentLayout(T.self)
        let newID = ComponentID(T.self)

        var index: Int?
        for i in 0...id.count {
            if i < id.count && newID > id[i] {
                continue
            }
            if i == id.count || newID < id[i] {
                index = i
            }
            break
        }

        var layout = layout
        var id = id
        if let index {
            layout.insert(newLayout, at: index)
            id.insert(newID, at: index)
        }
        return ArchetypeSchema(layout: layout, id: id)
    }

    public func removing<T: Component>(_ type: T.Type) -> ArchetypeSchema {
        let newID = ComponentID(T.self)

        var layout = layout
        var id = id
        for i in 0..<id.count {
            if newID == id[i] {
                layout.remove(at: i)
                id.remove(at: i)
                break
            }
        }
        return ArchetypeSchema(layout: layout, id: id)
    }
}

public struct Archetype: Sendable {
    public let schema: ArchetypeSchema
    private var components: [ComponentArray] = []
    private var indices: [ComponentID: Int] = [:]

    public var count: Int { components.first?.count ?? 0 }

    public init(schema: ArchetypeSchema) {
        self.schema = schema
        self.components.reserveCapacity(schema.layout.count)
        for i in 0..<schema.layout.count {
            let id = schema.id[i]
            components.append(ComponentArray(layout: schema.layout[i]))
            indices[id] = components.count - 1
        }

    }

    public mutating func reserveCapacity(_ minimumCapacity: Int) {
        for i in 0..<components.count {
            components[i].reserveCapacity(minimumCapacity)
        }
    }

    public mutating func append(_ data: [ComponentID: UnsafeRawPointer]) {
        for i in 0..<components.count {
            let id = schema.id[i]
            guard let pointer = data[id] else {
                preconditionFailure("Component \(id) not found")
            }
            components[i].append(pointer)
        }
    }

    public mutating func removeLast() {
        for i in 0..<components.count {
            components[i].removeLast()
        }
    }

    public mutating func moveLast(to index: Int) {
        for i in 0..<components.count {
            components[i].moveLast(to: index)
        }
    }

    public func read(at index: Int) -> [ComponentID: UnsafeRawPointer] {
        precondition((0..<count).contains(index), "Index out of bounds")

        var data: [ComponentID: UnsafeRawPointer] = [:]
        for i in 0..<components.count {
            let id = schema.id[i]
            data[id] = components[i].pointer(at: index)
        }
        return data
    }

    public func contains<T: Component>(_ type: T.Type) -> Bool {
        let id = ComponentID(T.self)
        return indices[id] != nil
    }

    public func get<T: Component>(_ type: T.Type, at index: Int) -> T? {
        guard let componentIndex = indices[ComponentID(T.self)] else { return nil }
        let value: T = components[componentIndex][index]
        return value
    }

    public subscript<T: Component>(_ index: Int) -> T {
        get {
            guard let componentIndex = indices[ComponentID(T.self)] else {
                preconditionFailure("Component \(T.self) not found in archetype.")
            }
            return components[componentIndex][index]
        }
        mutating set(newValue) {
            guard let componentIndex = indices[ComponentID(T.self)] else {
                preconditionFailure("Component \(T.self) not found in archetype.")
            }
            components[componentIndex][index] = newValue
        }
    }

    public func pointer<T: Component>(to type: T.Type) -> UnsafePointer<T> {
        let id = ComponentID(type.self)
        guard let index = indices[id] else {
            preconditionFailure("Component \(T.self) not found in archetype.")
        }
        return components[index].pointer(at: 0).assumingMemoryBound(to: T.self)
    }

    public mutating func pointer<T: Component>(to type: T.Type) -> UnsafeMutablePointer<T> {
        let id = ComponentID(type.self)
        guard let index = indices[id] else {
            preconditionFailure("Component \(T.self) not found in archetype.")
        }
        return components[index].pointer(at: 0).assumingMemoryBound(to: T.self)
    }
}
