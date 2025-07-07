public struct View<each T: Component>: Sendable {
    private var archetypes: [Int] = []
    private let included: Set<ComponentID>
    private let excluded: Set<ComponentID>
    private var worldID: UInt
    private var version: UInt

    public init(world: World, included: Set<ComponentID>, excluded: Set<ComponentID>) {
        var included = included
        for type in repeat (each T).self {
            included.insert(ComponentID(type.self))
        }
        Self.build(
            archetypes: &archetypes,
            from: world,
            including: included,
            excluding: excluded
        )
        self.included = included
        self.excluded = excluded
        worldID = world.id
        version = world.groupsVersion
    }

    public func isValid(for world: World) -> Bool {
        worldID == world.id && version == world.groupsVersion
    }

    public mutating func rebuild(for world: World) {
        Self.build(
            archetypes: &archetypes,
            from: world,
            including: included,
            excluding: excluded
        )
        worldID = world.id
        version = world.groupsVersion
    }

    private static func build(
        archetypes: inout [Int],
        from world: World,
        including included: Set<ComponentID>,
        excluding excluded: Set<ComponentID>
    ) {
        archetypes.removeAll()
        var groups: [Set<Int>] = []
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

        for index in result {
            archetypes.append(index)
        }
    }

    public func forEach(
        in world: World,
        _ body: (repeat each T) throws -> Void
    ) rethrows {
        guard isValid(for: world) else { return }
        for i in archetypes {
            let count = world.archetypes[i].count
            var pointers: (repeat UnsafePointer<each T>)
            pointers = (repeat world.pointer(to: (each T).self, inArchetypeAt: i))
            for _ in 0..<count {
                try body(repeat (each pointers).pointee)
                pointers = (repeat (each pointers).advanced(by: 1))
            }
        }
    }

    public func forEach(
        in world: inout World,
        _ body: (repeat UnsafeMutablePointer<each T>) throws -> Void
    ) rethrows {
        guard isValid(for: world) else { return }
        for i in archetypes {
            let count = world.archetypes[i].count
            var pointers: (repeat UnsafeMutablePointer<each T>)
            pointers = (repeat world.pointer(to: (each T).self, inArchetypeAt: i))
            for _ in 0..<count {
                try body(repeat each pointers)
                pointers = (repeat (each pointers).advanced(by: 1))
            }
        }
    }
}

public struct ViewBuilder<each T: Component>: Sendable {
    private let included: Set<ComponentID>
    private let excluded: Set<ComponentID>

    public init(included: Set<ComponentID> = [], excluded: Set<ComponentID> = []) {
        self.included = included
        self.excluded = excluded
    }

    public func including<each U: Component>(_ type: repeat (each U).Type) -> Self {
        var included = included
        for type in repeat (each U).self {
            included.insert(ComponentID(type.self))
        }
        return Self(included: included, excluded: excluded)
    }

    public func excluding<each U: Component>(_ type: repeat (each U).Type) -> Self {
        var excluded = excluded
        for type in repeat (each U).self {
            excluded.insert(ComponentID(type.self))
        }
        return Self(included: included, excluded: excluded)
    }

    public func view(into world: World) -> View<repeat each T> {
        View(world: world, included: included, excluded: excluded)
    }
}
