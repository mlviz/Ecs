# Ecs
A lightweight and minimalistic Entity-Component-System (ECS) framework written in Swift. It uses an archetype-based design to organize components efficiently and allows for fast and flexible iteration over entities.

This project was built as an exploration of how an ECS could look and feel in native Swift. It’s not designed to be better than any other existing engine and focuses more on minimalism and simplicity, aiming to provide a clean and natural Swift experience.

### Features

- Archetype-based storage for dense and cache-friendly layout.
- Copy-on-write struct semantics for controllable mutations.
- Parameter packs for expressive and type-safe iteration.
- No component registration, macros or extra boilerplate.
- Built with Swift 6 strict concurrency in mind.

### Usage

You start by creating a `World`. It allows you to `create` and `destroy` entities.
```swift
var world = World()

let entity: Entity = world.create()

world.destroy(entity)
```

You can `insert` and `remove` components for a specific `Entity`. You can also `get` or `update` individual components.
```swift
struct Position { var x: Float, y: Float }
struct Velocity { var x: Float, y: Float }

world.insert(Position(x: 0, y: 0), for: entity)
world.insert(Velocity(x: 1, y: 5), for: entity)

if let velocity = world.get(Velocity.self, for: entity) {
    print(velocity)
    
    world.update(Position.self, for: entity) { position in
        position.x += velocity.x
        position.y += velocity.y
    }
}

world.remove(Position.self, for: entity)

let position = world.get(Position.self, for: entity) // nil
```

Pretty much any struct can be a component. The only requirement is to be `BitwiseCopyable`.

Technically, `Entity` itself is a component, which is useful in iterations. You can even `get` an `Entity`, but it has no real point. However, you're **not allowed** to use `update`, `insert` or `remove` with `Entity`. Doing this will trigger a runtime error.
```swift
if let other = world.get(Entity.self, for: entity) {
    // other is the same as entity 
}

// DON'T DO THIS
world.update(Entity.self, for: entity) { entity in }
world.insert(other, for: entity)
world.remove(Entity.self, for: entity)
```

To iterate over entities with specific components, use a `View` created by `ViewBuilder`.
```swift
ViewBuilder<Position, Velocity>()
    .view(into: world)
    .forEach(in: world) { position, velocity in
        print(position, velocity)
    }
```

Because `Entity` is treated as a component, you can add it to `ViewBuilder` parameters to access entities during iteration.
```swift
ViewBuilder<Entity, Position, Velocity>()
    .view(into: world)
    .forEach(in: world) { entity, position, velocity in
        print("\(entity) has \(position) and \(velocity))
    }
```

There's a mutable version of `forEach` which lets you modify components while iterating by giving you access to `UnsafeMutablePointer`. Unfortunately, Swift doesn't support `inout` with parameter packs (yet), so I had to go with pointers.

Mutable `forEach` captures `World` as `inout` to prevent external changes while iterating. 
```swift
ViewBuilder<Position, Velocity>()
    .view(into: world)
    .forEach(in: &world) { position, velocity in
        position.pointee.x += velocity.pointee.x
        position.pointee.y += velocity.pointee.y
    }
```

You only get access to the components included in `ViewBuilder` parameters, but you can `include` or `exclude` additional components.
```swift
ViewBuilder<Entity>()
    .including(Enemy.self)
    .excluding(Dead.self)
    .view(into: world)
    .forEach(in: world) { entity in
        print("\(entity) is an Enemy and isn't Dead")
    }
```

`View` caches the result of archetypes sets intersection, so you can (and probably should) store views to avoid recomputing them every time. If the `World` changes and the cache becomes invalid, you have to `rebuild` it. If a `View` is invalid, `forEach` will simply do nothing.
```swift
struct MovementSystem {
    var view: View<Position, Velocity>
    
    init(world: inout World) {
        view = ViewBuilder().view(into: world)
    }

    mutating func update(world: inout World) {
        if !view.isValid(for: world) {
            view.rebuild(for: world)
        }
        view.forEach(in: &world) { pos, vel in
            pos.pointee.x += vel.pointee.x
            pos.pointee.y += vel.pointee.y
        }
    }
}
```
