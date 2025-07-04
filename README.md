# Ecs
A lightweight and minimalistic Entity-Component-System (ECS) framework written in Swift. It uses an archetype-based design to organize components efficiently and allows for fast and flexible iteration over entities.

This project was built as an exploration of how an ECS could look and feel in native Swift. It’s not designed to be better than any other existing engine and focuses more on minimalism and simplicity, aiming to provide a clean and natural Swift experience.

### Features

- Archetype-based storage for dense, cache-friendly layout.
- Uses plain bitwise-copyable structs as components.
- Parameter pack–based queries for expressive and type-safe iteration.
- No component registration, macros or extra boilerplate.
- Minimalistic and flexible API that allows for further expansion.

### Usage

```swift
struct Position: Component { var x: Float, y: Float }
struct Velocity: Component { var x: Float, y: Float }

let world = World()

let entity = world.create()

world.insert(Position(x: 0, y: 0), for: entity)
world.insert(Velocity(x: 1, y: 1), for: entity)

world.forEach(Position.self, Velocity.self) { pos, vel in
    pos.pointee.x += vel.pointee.x
    pos.pointee.y += vel.pointee.y
}

world.remove(Position.self, for: entity)
world.destroy(entity)
```
