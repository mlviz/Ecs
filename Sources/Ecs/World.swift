import Synchronization

private let globalWorldID = Atomic<UInt>(0)

public final class WorldID: Sendable {
    public let id = {
        let (value, _) = globalWorldID.add(1, ordering: .relaxed)
        return value
    }()
}

public struct World: Sendable {
    private var _id = WorldID()
    public var id: UInt { _id.id }

    public private(set) var entityManager = CowEntityManager()
    public private(set) var entities = [(archetypeIndex: Int, entityIndex: Int)?]()
    public private(set) var archetypes = [Archetype]()
    public private(set) var indices = [ArchetypeID: Int]()
    public private(set) var groups = [ComponentID: Set<Int>]()
    public private(set) var groupsVersion: UInt = 0

    private static let entityArchetypeSchema = ArchetypeSchema(componentType: Entity.self)
}

// public
extension World {
    public mutating func create() -> Entity {
        ensureUniqueID()

        var entity = entityManager.create()

        let archetypeIndex = archetypeIndex(Self.entityArchetypeSchema)
        withUnsafeMutableBytes(of: &entity) {
            archetypes[archetypeIndex].append([Entity.componentID: $0.baseAddress!])
        }
        addToGroups(archetypeIndex: archetypeIndex)

        let metadata = (
            archetypeIndex: archetypeIndex,
            entityIndex: archetypes[archetypeIndex].count - 1
        )

        if entities.indices.contains(entity.id) {
            entities[entity.id] = metadata
        } else {
            entities.append(metadata)
        }

        return entity
    }

    public func isAlive(_ entity: Entity) -> Bool {
        entityManager.isAlive(entity)
    }

    public mutating func destroy(_ entity: Entity) {
        guard isAlive(entity) else { return }

        ensureUniqueID()

        if let (archetypeIndex, entityIndex) = entities[entity.id] {
            removeEntity(archetypeIndex: archetypeIndex, entityIndex: entityIndex)
        }
        entityManager.destroy(entity)
    }

    public mutating func insert<T: Component>(_ component: T, for entity: Entity) {
        precondition(T.self != Entity.self, "Cannot add Entity to an entity")

        guard isAlive(entity), let (oldArchetypeIndex, oldEntityIndex) = entities[entity.id]
        else { return }

        ensureUniqueID()

        let newSchema = archetypes[oldArchetypeIndex].schema.adding(T.self)
        let newArchetypeIndex = archetypeIndex(newSchema)
        guard newArchetypeIndex != oldArchetypeIndex else {
            archetypes[oldArchetypeIndex][oldEntityIndex] = component
            return
        }

        var data = archetypes[oldArchetypeIndex].read(at: oldEntityIndex)
        var component = component
        withUnsafeMutableBytes(of: &component) {
            data[ComponentID(T.self)] = UnsafeRawPointer($0.baseAddress)
        }
        archetypes[newArchetypeIndex].append(data)
        addToGroups(archetypeIndex: newArchetypeIndex)

        removeEntity(archetypeIndex: oldArchetypeIndex, entityIndex: oldEntityIndex)
        entities[entity.id] = (
            archetypeIndex: newArchetypeIndex,
            entityIndex: archetypes[newArchetypeIndex].count - 1
        )
    }

    public mutating func remove<T: Component>(_ type: T.Type, for entity: Entity) {
        precondition(T.self != Entity.self, "Cannot remove Entity from an entity")

        guard isAlive(entity), let (oldArchetypeIndex, oldEntityIndex) = entities[entity.id]
        else { return }

        guard archetypes[oldArchetypeIndex].contains(T.self) else { return }

        ensureUniqueID()

        let newSchema = archetypes[oldArchetypeIndex].schema.removing(T.self)
        let newArchetypeIndex = archetypeIndex(newSchema)

        let data = archetypes[oldArchetypeIndex].read(at: oldEntityIndex)
        archetypes[newArchetypeIndex].append(data)
        addToGroups(archetypeIndex: newArchetypeIndex)

        removeEntity(archetypeIndex: oldArchetypeIndex, entityIndex: oldEntityIndex)
        entities[entity.id] = (
            archetypeIndex: newArchetypeIndex,
            entityIndex: archetypes[newArchetypeIndex].count - 1
        )
    }

    public func get<T: Component>(_ type: T.Type, for entity: Entity) -> T? {
        guard isAlive(entity), let (archetypeIndex, entityIndex) = entities[entity.id]
        else { return nil }
        return archetypes[archetypeIndex].get(T.self, at: entityIndex)
    }

    public mutating func update<T: Component>(
        _ type: T.Type,
        for entity: Entity,
        _ body: (inout T) throws -> Void
    ) rethrows {
        guard isAlive(entity), let (archetypeIndex, entityIndex) = entities[entity.id]
        else { return }
        guard archetypes[archetypeIndex].contains(T.self) else { return }
        let pointer: UnsafeMutablePointer<T> = archetypes[archetypeIndex]
            .pointer(to: T.self)
            .advanced(by: entityIndex)
        try body(&pointer.pointee)
    }

    public func pointer<T: Component>(
        to type: T.Type,
        inArchetypeAt i: Int
    ) -> UnsafePointer<T> {
        archetypes[i].pointer(to: T.self)
    }

    public mutating func pointer<T: Component>(
        to type: T.Type,
        inArchetypeAt i: Int
    ) -> UnsafeMutablePointer<T> {
        archetypes[i].pointer(to: T.self)
    }
}

// private
extension World {
    private mutating func ensureUniqueID() {
        if !isKnownUniquelyReferenced(&_id) {
            self._id = WorldID()
        }
    }

    private mutating func archetypeIndex(_ schema: ArchetypeSchema) -> Int {
        if let index = indices[schema.id] {
            return index
        }
        let archetype = Archetype(schema: schema)
        archetypes.append(archetype)
        let index = archetypes.count - 1
        indices[archetype.schema.id] = index
        return index
    }

    private mutating func removeEntity(archetypeIndex: Int, entityIndex: Int) {
        let lastEntityIndex = archetypes[archetypeIndex].count - 1
        let entity: Entity = archetypes[archetypeIndex][entityIndex]
        let lastEntity: Entity = archetypes[archetypeIndex][lastEntityIndex]
        if entityIndex != lastEntityIndex {
            archetypes[archetypeIndex].moveLast(to: entityIndex)
            entities[lastEntity.id] = (archetypeIndex: archetypeIndex, entityIndex: entityIndex)
        }
        archetypes[archetypeIndex].removeLast()
        entities[entity.id] = nil

        if archetypes[archetypeIndex].count == 0 {
            removeFromGroups(archetypeIndex: archetypeIndex)
        }
    }

    private mutating func addToGroups(archetypeIndex: Int) {
        for id in archetypes[archetypeIndex].schema.id {
            groups[id, default: []].insert(archetypeIndex)
        }
        groupsVersion += 1
    }

    private mutating func removeFromGroups(archetypeIndex: Int) {
        for id in archetypes[archetypeIndex].schema.id {
            groups[id]?.remove(archetypeIndex)
        }
        groupsVersion += 1
    }
}
