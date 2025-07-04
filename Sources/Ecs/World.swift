public final class World {
    private var entityManager = EntityManager()
    private var archetypes = [ArchetypeID: Archetype]()
    private var entities = [EntityID: (archetype: Archetype, index: Int)]()
    private var groups = [ComponentID: Set<Archetype>]()

    public init() { }
}

public extension World {
    func create() -> Entity { entityManager.create() }
    
    func isAlive(_ entity: Entity) -> Bool { entityManager.isAlive(entity) }

    func destroy(_ entity: Entity) {
        guard isAlive(entity) else { return }
        
        if let (archetype, i) = entities.removeValue(forKey: entity.id) {
            remove(entity: entity.id, from: archetype, at: i)
        }
        entityManager.destroy(entity)
    }

    func insert<T: Component>(_ component: consuming T, for entity: Entity) {
        guard isAlive(entity) else { return }
        
        if let (oldArchetype, oldIndex) = entities[entity.id] {
            let newArchetype = archetype(oldArchetype.schema.adding(T.self))
            let newIndex = newArchetype.count
            
            withUnsafeMutableBytes(of: &component) {
                var data = oldArchetype.read(at: oldIndex)
                data[ComponentID(T.self)] = $0.baseAddress
                
                newArchetype.append(entity.id)
                newArchetype.write(data: data, at: newIndex)
            }
            remove(entity: entity.id, from: oldArchetype, at: oldIndex)
            entities[entity.id] = (archetype: newArchetype, index: newIndex)
        } else {
            let newArchetype = archetype(ArchetypeSchema(componentType: T.self))
            let newIndex = newArchetype.count
            withUnsafeMutableBytes(of: &component) {
                let data = [ComponentID(T.self): $0.baseAddress!]
                newArchetype.append(entity.id)
                newArchetype.write(data: data, at: newIndex)
            }
            entities[entity.id] = (archetype: newArchetype, index: newIndex)
        }
    }

    func remove<T: Component>(_ type: T.Type, for entity: Entity) {
        guard isAlive(entity), let (oldArchetype, oldIndex) = entities[entity.id], oldArchetype.contains(T.self)
        else { return }
        
        if oldArchetype.schema.id.count > 1 {
            let newArchetype = archetype(oldArchetype.schema.removing(T.self))
            let newIndex = newArchetype.count
            
            let data = oldArchetype.read(at: oldIndex)
            newArchetype.append(entity.id)
            newArchetype.write(data: data, at: newArchetype.count - 1)
            
            remove(entity: entity.id, from: oldArchetype, at: oldIndex)
            entities[entity.id] = (archetype: newArchetype, index: newIndex)
        } else {
            remove(entity: entity.id, from: oldArchetype, at: oldIndex)
            entities.removeValue(forKey: entity.id)
        }
    }
    
    func has<T: Component>(_ type: T.Type, for entity: Entity) -> Bool {
        guard isAlive(entity), let (archetype, _) = entities[entity.id] else { return false }
        return archetype.contains(T.self)
    }
    
    func get<T: Component>(_ type: T.Type, for entity: Entity) -> UnsafeMutablePointer<T>? {
        guard isAlive(entity), let (archetype, index) = entities[entity.id], archetype.contains(T.self)
        else { return nil }
        return archetype.pointer(for: T.self).advanced(by: index)
    }
    
    func archetypes<each T: Component>(containing types: repeat (each T).Type) -> Set<Archetype> {
        var archetypes: [Set<Archetype>] = []
        var minimumIndex: Int?
        for type in repeat (each T).self {
            guard let set = groups[ComponentID(type.self)] else { return [] }
            archetypes.append(set)
            if minimumIndex == nil || set.count < archetypes[minimumIndex!].count {
                minimumIndex = archetypes.count - 1
            }
        }
        guard let minimumIndex else { return [] }
        archetypes.swapAt(0, minimumIndex)
        var result = archetypes[0]
        for i in 1..<archetypes.count {
            result.formIntersection(archetypes[i])
        }
        return result
    }
    
    func forEach<each T: Component>(
        _ types: repeat (each T).Type,
        body: ((repeat UnsafeMutablePointer<each T>) throws -> Void)
    ) rethrows {
        let archetypes = archetypes(containing: repeat (each T).self)
        for archetype in archetypes {
            var pointers = archetype.pointers(for: repeat (each T).self)
            for _ in 0..<archetype.count {
                try body(repeat each pointers)
                pointers = (repeat (each pointers).advanced(by: 1))
            }
        }
    }
}

private extension World {
    func archetype(_ schema: ArchetypeSchema) -> Archetype {
        if let archetype = archetypes[schema.id] {
            return archetype
        }
        let archetype = Archetype(schema: schema)
        archetypes[schema.id] = archetype
        for id in archetype.schema.id {
            groups[id, default: []].insert(archetype)
        }
        return archetype
    }
    
    func remove(entity: EntityID, from archetype: Archetype, at index: Int) {
        guard let last = archetype.entities.last else  { return }
        if last != entity {
            archetype.moveLastEntity(to: index)
            entities[last] = (archetype: archetype, index: index)
        }
        archetype.removeLast()
        if archetype.count == 0 {
            archetypes.removeValue(forKey: archetype.schema.id)
            for id in archetype.schema.id {
                groups[id]?.remove(archetype)
            }
        }
    }
}

