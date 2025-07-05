public final class World {
    private var entityManager = EntityManager()
    public private(set) var entities = [(archetype: Archetype, index: Int)?]()
    public private(set) var archetypes = [ArchetypeID: Archetype]()
    public private(set) var archetypesVersion: Int = 0
    public private(set) var groups = [ComponentID: Set<ArchetypeRef>]()

    private static let entityArchetypeSchema = ArchetypeSchema(componentType: Entity.self)

    public init() {}
}

// public
extension World {
    public func create() -> Entity {
        var entity = entityManager.create()

        let archetype = archetype(Self.entityArchetypeSchema)
        withUnsafeMutableBytes(of: &entity) {
            archetype.append([Entity.componentID: $0.baseAddress!])
        }

        let metadata = (archetype: archetype, index: archetype.count - 1)
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

    public func destroy(_ entity: Entity) {
        guard isAlive(entity) else { return }

        if let (archetype, i) = entities[entity.id] {
            remove(entity: entity.id, from: archetype, at: i)
        }
        entityManager.destroy(entity)
    }

    public func insert<T: Component>(_ component: T, for entity: Entity) {
        precondition(T.self != Entity.self, "Cannot add Entity to an entity")

        guard isAlive(entity), let (oldArchetype, oldIndex) = entities[entity.id] else { return }

        let newArchetype = archetype(oldArchetype.schema.adding(T.self))
        guard newArchetype !== oldArchetype else {
            oldArchetype.update(T.self, at: oldIndex) { $0 = component }
            return
        }

        var component = component
        withUnsafeMutableBytes(of: &component) {
            var data = oldArchetype.read(at: oldIndex)
            data[ComponentID(T.self)] = $0.baseAddress

            newArchetype.append(data)
        }

        remove(entity: entity.id, from: oldArchetype, at: oldIndex)
        entities[entity.id] = (archetype: newArchetype, index: newArchetype.count - 1)
    }

    public func remove<T: Component>(_ type: T.Type, for entity: Entity) {
        precondition(T.self != Entity.self, "Cannot remove Entity from an entity")

        guard isAlive(entity), let (oldArchetype, oldIndex) = entities[entity.id] else { return }
        guard oldArchetype.contains(T.self) else { return }

        let newArchetype = archetype(oldArchetype.schema.removing(T.self))

        let data = oldArchetype.read(at: oldIndex)
        newArchetype.append(data)

        remove(entity: entity.id, from: oldArchetype, at: oldIndex)
        entities[entity.id] = (archetype: newArchetype, index: newArchetype.count - 1)
    }

    public func has<T: Component>(_ type: T.Type, for entity: Entity) -> Bool {
        guard isAlive(entity), let (archetype, _) = entities[entity.id] else { return false }
        return archetype.contains(T.self)
    }

    public func get<T: Component>(_ type: T.Type, for entity: Entity) -> T? {
        guard isAlive(entity), let (archetype, index) = entities[entity.id] else { return nil }
        guard archetype.contains(T.self) else { return nil }
        return archetype.get(T.self, at: index)
    }

    public func update<T: Component>(
        _ type: T.Type, for entity: Entity, _ body: (inout T) -> Void
    ) {
        guard isAlive(entity), let (archetype, index) = entities[entity.id] else { return }
        guard archetype.contains(T.self) else { return }
        archetype.update(T.self, at: index, body)
    }

    public func query<each T>(_ types: repeat (each T).Type) -> Query<repeat each T> {
        Query(world: self)
    }
}

// private
extension World {
    private func archetype(_ schema: ArchetypeSchema) -> Archetype {
        if let archetype = archetypes[schema.id] {
            return archetype
        }
        let archetype = Archetype(schema: schema)
        archetypes[schema.id] = archetype
        for id in archetype.schema.id {
            groups[id, default: []].insert(ArchetypeRef(archetype: archetype))
        }
        archetypesVersion += 1
        return archetype
    }

    private func remove(entity: EntityID, from archetype: Archetype, at index: Int) {
        let last = archetype.get(Entity.self, at: archetype.count - 1)
        if last.id != entity {
            archetype.moveLast(to: index)
            entities[last.id] = (archetype: archetype, index: index)
        }
        archetype.removeLast()
        entities[entity] = nil

        if archetype.count == 0 {
            archetypes.removeValue(forKey: archetype.schema.id)
            for id in archetype.schema.id {
                groups[id]?.remove(ArchetypeRef(archetype: archetype))
            }
            archetypesVersion += 1
        }
    }
}
