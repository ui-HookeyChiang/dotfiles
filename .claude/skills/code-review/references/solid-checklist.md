# SOLID Smell Prompts

## SRP (Single Responsibility)
Principle: coding-guidelines §2

- File owns unrelated concerns (e.g., HTTP + DB + domain rules in one file)
- Large class/module with low cohesion or multiple reasons to change
- Functions that orchestrate many unrelated steps
- God objects that know too much about the system
- **Ask**: "What is the single reason this module would change?"

## OCP (Open/Closed)

- Adding a new behavior requires editing many switch/if blocks
- Feature growth requires modifying core logic rather than extending
- No plugin/strategy/hook points for variation
- **Ask**: "Can I add a new variant without touching existing code?"

## LSP (Liskov Substitution)

- Subclass checks for concrete type or throws for base method
- Overridden methods weaken preconditions or strengthen postconditions
- Subclass ignores or no-ops parent behavior
- **Ask**: "Can I substitute any subclass without the caller knowing?"

## ISP (Interface Segregation)

- Interfaces with many methods, most unused by implementers
- Callers depend on broad interfaces for narrow needs
- Empty/stub implementations of interface methods
- **Ask**: "Do all implementers use all methods?"

## DIP (Dependency Inversion)

- High-level logic depends on concrete IO, storage, or network types
- Hard-coded implementations instead of abstractions or injection
- Import chains that couple business logic to infrastructure
- **Ask**: "Can I swap the implementation without changing business logic?"

---

Source: https://github.com/sanyuan0704/sanyuan-skills/tree/main/skills/code-review-expert (MIT License)
