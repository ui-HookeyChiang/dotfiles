# Fowler Smell Baseline

Derived from Martin Fowler's _Refactoring_ (ch.3). Applies to all code review regardless of repo-specific standards. Repo standards override — where a documented standard endorses something the baseline would flag, suppress the smell.

Each smell is a heuristic ("possible X"), never a hard violation. Skip anything tooling already enforces.

| Smell | What it is | How to fix |
|-------|-----------|------------|
| Mysterious Name | name doesn't reveal what it does | rename; if no honest name, design is murky |
| Duplicated Code | same logic shape in >1 place in the diff | extract shared shape, call from both |
| Feature Envy | method reaches into another object's data more than its own | move method onto the data it envies |
| Data Clumps | same fields/params travel together | bundle into one type |
| Primitive Obsession | primitive standing in for domain concept | give it its own type |
| Repeated Switches | same switch/if-cascade recurs | polymorphism or one shared map |
| Shotgun Surgery | one logical change → scattered edits | gather what changes together |
| Divergent Change | one file edited for unrelated reasons | split by reason |
| Speculative Generality | abstraction for needs spec doesn't have | delete; inline until real need |
| Message Chains | long a.b().c().d() navigation | hide walk behind one method |
| Middle Man | class that mostly delegates | cut it, call real target |
| Refused Bequest | subclass ignores/overrides most of parent | drop inheritance, use composition |
