import Testing

@testable import Ecs

struct Health: Component { var hp: Int }
struct TagA: Component {}
struct TagB: Component {}

@Suite
struct EcsTests {
    let world = World()

    @Test
    func massiveMutationAndRemoval() {
        struct Position { var x: Int }
        struct Velocity { var dx: Int }

        var entities: [Entity] = []

        for i in 0..<1000 {
            let e = world.create()
            if i % 2 == 0 { world.insert(Position(x: i), for: e) }
            if i % 3 == 0 { world.insert(Velocity(dx: i * 2), for: e) }
            entities.append(e)
        }

        // Update all Position components
        world.query(Position.self).forEach { (p: Position) in
            #expect(p.x % 2 == 0)
        }

        // Remove Velocity from every third
        for i in stride(from: 0, to: 1000, by: 3) {
            world.remove(Velocity.self, for: entities[i])
        }

        // Ensure Velocity is gone from those
        for i in stride(from: 0, to: 1000, by: 3) {
            #expect(!world.has(Velocity.self, for: entities[i]))
        }

        // Clean up
        for e in entities { world.destroy(e) }
    }

    @Test
    func componentInsertReinsertEdgeCases() {
        struct Flag { var value: Bool }

        let e1 = world.create()
        let e2 = world.create()

        world.insert(Flag(value: false), for: e1)
        world.insert(Flag(value: true), for: e2)

        #expect(world.get(Flag.self, for: e1)?.value == false)
        #expect(world.get(Flag.self, for: e2)?.value == true)

        // Re-insert component
        world.insert(Flag(value: true), for: e1)
        #expect(world.get(Flag.self, for: e1)?.value == true)

        // Update flag using `update`
        world.update(Flag.self, for: e2) { $0.value = false }
        #expect(world.get(Flag.self, for: e2)?.value == false)

        world.destroy(e1)
        world.destroy(e2)
    }

    @Test
    func archetypeTransitioningBulk() {
        struct A { var x: Int }
        struct B { var y: Int }

        var entities: [Entity] = []

        for i in 0..<500 {
            let e = world.create()
            world.insert(A(x: i), for: e)
            if i % 2 == 0 { world.insert(B(y: i * 10), for: e) }
            entities.append(e)
        }

        // Remove and re-add B to force archetype transitions
        for e in entities where world.has(B.self, for: e) {
            world.remove(B.self, for: e)
            world.insert(B(y: 999), for: e)
            #expect(world.get(B.self, for: e)?.y == 999)
        }

        for e in entities { world.destroy(e) }
    }

    @Test
    func queryWithExclusionAndInclusion() {
        struct A { var a: Int }
        struct B { var b: Int }
        struct C { var c: Int }

        var entities: [Entity] = []

        for i in 0..<100 {
            let e = world.create()
            world.insert(A(a: i), for: e)
            if i % 2 == 0 { world.insert(B(b: i), for: e) }
            if i % 3 == 0 { world.insert(C(c: i), for: e) }
            entities.append(e)
        }

        var count = 0
        world.query(A.self, B.self)
            .excluding(C.self)
            .forEach { (a: A, b: B) in
                #expect(a.a == b.b)
                #expect(a.a % 2 == 0)
                #expect(a.a % 3 != 0)
                count += 1
            }

        let expected = (0..<100).filter { $0 % 2 == 0 && $0 % 3 != 0 }.count
        #expect(count == expected)  // evens minus multiples of 6

        for e in entities { world.destroy(e) }
    }

    @Test
    func pointerMutationWithForEachPtr() {
        struct HP { var value: Int }

        var entities: [Entity] = []

        for i in 0..<200 {
            let e = world.create()
            world.insert(HP(value: i), for: e)
            entities.append(e)
        }

        // Mutate in-place
        world.query(HP.self).forEachPtr { (hp: UnsafeMutablePointer<HP>) in
            hp.pointee.value *= 2
        }

        for e in entities {
            let v = world.get(HP.self, for: e)?.value
            #expect(v == e.id * 2)
            world.destroy(e)
        }
    }

    @Test
    func gravitySample() {
        struct Position {
            var x: Float
            var y: Float
        }

        struct Velocity {
            var dx: Float
            var dy: Float
        }

        struct Grounded {}

        let entities = (0..<10).map { _ in world.create() }
        for (i, entity) in entities.enumerated() {
            world.insert(Position(x: Float(i + 1) * 10, y: Float(i + 1) * 2), for: entity)
            world.insert(Velocity(dx: 0, dy: -1), for: entity)
        }

        let update = {
            var grounded: [Entity] = []
            world.query(Position.self, Velocity.self).excluding(Grounded.self).forEachPtr {
                pos, vel in
                pos.pointee.x += vel.pointee.dx
                pos.pointee.y += vel.pointee.dy
            }

            world.query(Position.self, Entity.self).excluding(Grounded.self).forEach {
                pos, entity in
                if pos.y <= 0 {
                    grounded.append(entity)
                }
            }

            for entity in grounded {
                world.insert(Grounded(), for: entity)
            }
        }

        for _ in 0..<10 { update() }

        var groundedCount = 0
        world.query(Grounded.self).forEach { _ in groundedCount += 1 }
        #expect(groundedCount == 5)

        for _ in 0..<10 { update() }

        groundedCount = 0
        world.query(Grounded.self).forEach { _ in groundedCount += 1 }
        #expect(groundedCount == 10)

        for entity in entities {
            world.destroy(entity)
        }
    }

}
