# 9. The irrigation system rename (D18)

Built 2026-11-23 on the branch `irrigation-systems`. Frozen once merged; what's current is in [CLAUDE.md](../../CLAUDE.md) (Vocabulary), [architecture.md](../architecture.md) and [decisions.md](../decisions.md) (D18).

`Pivot` in code meant any irrigation system; it's `IrrigationSystem` now, `system` for short.

- [x] **Names.** `Pivot` → `IrrigationSystem` (`irrigation_systems`), `PivotGroup` → `IrrigationGroup` (`irrigation_groups`); `pivot_id` → `system_id` on fields and plantings, `pivot_group_id` → `irrigation_group_id`. Everything else: `pivot` → `system` (`SystemsController`, `/systems/:id`, `system_irrigations`, `Systems/Show`, `SystemShape`, `MapSystem`, `lib/map/systems.ts`, `SYSTEM_IDS`); the serializers give the TypeScript types `IrrigationSystem` and `IrrigationGroup`. Associations name the class (`belongs_to :system, class_name: "IrrigationSystem"`, `has_many :fields, foreign_key: :system_id`); `Planting#system` reads its field's system when the field is loaded, else the association (`super`).
- [x] **Kept as "pivot"**, where it means a center pivot: the kind's name growers see (`KIND_NAMES`: "Pivot"), its words (the pivot point, "Pivot sweep", "Same as the pivot", the About page's kinds), grower-named systems in the demo and tests ("Home pivot"), and the legacy audit, the old migrations and the frozen plans. Geo's outline of a shape is `shapeOutline` (the map's `systemOutline` adds points' glyphs).
- [x] **Migration** (`RenamePivotsToIrrigationSystems`): renames the tables and columns (Rails renames their conventional indexes), the check constraints and the named foreign key, and rewrites the stored names: digest exclusions' `subject_type` `Pivot` → `IrrigationSystem`, activity days' area `pivot` → `system`. Reversible; instant on Postgres.
- [x] **No redirects** from `/pivots/…`: nobody but Ben had an account.
- [x] **Gone:** `spec/migrations/store_irrigation_per_planting_spec.rb`, which ran D15's migration against today's schema; the migration is unchanged and still runs in order before the rename.
- [x] `bin/ci`, `bin/e2e`.
