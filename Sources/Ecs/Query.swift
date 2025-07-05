public final class Query<each T: Component> {
    private weak var world: World?
    private var included: Set<ComponentID> = []
    private var excluded: Set<ComponentID> = []
    private var archetypes: [Archetype] = []
    private var version: Int = -1

    init(world: World?) {
        self.world = world
        for type in repeat (each T).self {
            included.insert(ComponentID(type.self))
        }
    }

    public func including<each U: Component>(_ type: repeat (each U).Type) -> Query {
        for type in repeat (each U).self {
            let (inserted, _) = included.insert(ComponentID(type.self))
            if inserted {
                resetCache()
            }
        }
        return self
    }

    public func excluding<each U: Component>(_ type: repeat (each U).Type) -> Query {
        for type in repeat (each U).self {
            let (inserted, _) = excluded.insert(ComponentID(type.self))
            if inserted {
                resetCache()
            }
        }
        return self
    }

    public func update(_ body: (repeat UnsafeMutablePointer<each T>) throws -> Void) rethrows {
        prepare()
        for archetype in archetypes {
            var pointers = archetype.pointers(for: repeat (each T).self)
            for _ in 0..<archetype.count {
                try body(repeat each pointers)
                pointers = (repeat (each pointers).advanced(by: 1))
            }
        }
    }

    public func forEach(_ body: (repeat each T) throws -> Void) rethrows {
        try update { (pointers: repeat UnsafeMutablePointer<each T>) in
            let values = (repeat (each pointers).pointee)
            try body(repeat each values)
        }
    }

    public func resetCache() {
        archetypes.removeAll()
        version = -1
    }

    public func prepare() {
        guard let world else {
            resetCache()
            return
        }
        guard version != world.archetypesVersion else { return }

        archetypes.removeAll()
        version = world.archetypesVersion

        var groups: [Set<ArchetypeRef>] = []
        for id in included {
            if id == Entity.componentID && included.count > 1 {
                // can skip Entity because every Archetype has it anyways
                // unless Entity is the only component we're looking for
                continue
            }
            guard let group = world.groups[id], !group.isEmpty else { return }
            groups.append(group)
        }

        let minimum = groups.enumerated().min { $0.element.count < $1.element.count }
        guard let minimum else { return }
        groups.swapAt(0, minimum.offset)

        var result = groups[0]
        for i in 1..<groups.count {
            result.formIntersection(groups[i])
            if result.isEmpty { return }
        }

        for id in excluded {
            if let group = world.groups[id] {
                result.subtract(group)
                if result.isEmpty { return }
            }
        }

        for ref in result {
            archetypes.append(ref.archetype)
        }
    }
}
