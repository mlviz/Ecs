public typealias ArchetypeID = [ComponentID]

public struct ArchetypeSchema {
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

public class Archetype {
    public let schema: ArchetypeSchema
    public private(set) var storages: [UnsafeMutableRawPointer] = []
    public private(set) var entities: [EntityID] = []
    public private(set) var indices: [ComponentID: Int] = [:]
    public private(set) var capacity: Int = 0
    
    public var count: Int { entities.count }
    
    public init(schema: ArchetypeSchema) {
        self.schema = schema
        self.storages.reserveCapacity(schema.layout.count)
        for i in 0..<schema.layout.count {
            let id = schema.id[i]
            let stride = schema.layout[i].stride
            let alignment = schema.layout[i].alignment
            indices[id] = storages.count
            storages.append(UnsafeMutableRawPointer.allocate(byteCount: capacity * stride, alignment: alignment))
        }
    }

    deinit {
        for storage in storages {
            storage.deallocate()
        }
    }
}

public extension Archetype {
    func reserveCapacity(_ n: Int) {
        guard n > capacity else { return }
        let newCapacity = Swift.max(n, capacity * 2)
        for i in 0..<storages.count {
            let stride = schema.layout[i].stride
            let alignment = schema.layout[i].alignment
            let oldStorage = storages[i]
            let newStorage = UnsafeMutableRawPointer.allocate(byteCount: newCapacity * stride, alignment: alignment)
            newStorage.copyMemory(from: oldStorage, byteCount: count * stride)
            oldStorage.deallocate()
            storages[i] = newStorage
        }
        entities.reserveCapacity(newCapacity)
        capacity = newCapacity
    }
    
    func append(_ entity: EntityID) {
        reserveCapacity(count + 1)
        entities.append(entity)
    }
    
    @discardableResult
    func removeLast() -> EntityID {
        entities.removeLast()
    }
    
    func moveLastEntity(to index: Int) {
        precondition(entities.indices.contains(index), "Index out of bounds")
        let from = count - 1
        let to = index
        if from != to {
            for i in 0..<storages.count {
                let storage = storages[i]
                let stride = schema.layout[i].stride
                
                let toPtr = storage.advanced(by: to * stride)
                let fromPtr = storage.advanced(by: from * stride)
                toPtr.copyMemory(from: fromPtr, byteCount: stride)
            }
            entities[to] = entities[from]
        }
    }
    
    func read(at index: Int) ->  [ComponentID: UnsafeMutableRawPointer] {
        precondition(entities.indices.contains(index), "Index out of bounds")
        
        var data: [ComponentID: UnsafeMutableRawPointer] = [:]
        for i in 0..<storages.count {
            let id = schema.id[i]
            let stride = schema.layout[i].stride
            let offset = index * stride
            data[id] = storages[i].advanced(by: offset)
        }
        return data
    }
    
    func write(data: [ComponentID: UnsafeMutableRawPointer], at index: Int) {
        precondition(entities.indices.contains(index), "Index out of bounds")
        
        for i in 0..<storages.count {
            let id = schema.id[i]
            let stride = schema.layout[i].stride
            let offset = index * stride
            if let pointer = data[id] {
                storages[i].advanced(by: offset).copyMemory(from: pointer, byteCount: stride)
            }
        }
    }
    
    func contains<T: Component>(_ type: T.Type) -> Bool {
        let id = ComponentID(T.self)
        return indices[id] != nil
    }

    func pointer<T: Component>(for type: T.Type) -> UnsafeMutablePointer<T> {
        let id = ComponentID(type.self)
        guard let index = indices[id] else {
            preconditionFailure("Component \(T.self) not found in archetype.")
        }
        return storages[index].assumingMemoryBound(to: T.self)
    }

    func pointers<each T: Component>(for types: repeat (each T).Type) -> (repeat UnsafeMutablePointer<each T>) {
        (repeat pointer(for: (each T).self))
    }
}

extension Archetype: Hashable {
    public static func == (lhs: Archetype, rhs: Archetype) -> Bool {
        lhs.schema.id == rhs.schema.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(schema.id)
    }
}
