# Emitter params — spec

Scope: `Emitter` and `Emitter2D`. Editing through the new inspector only (edit2 / HideKit), in the JS editor (hide_js); HideHL is dropped. Colors (particle shader color curves, emitter random color / gradient) keep their current model.

## Terms

- **Particle curve**: a curve over the life of a particle, time in [0, 1]. Edited inline in the inspector, never shown in the timeline.
- **Animation curve**: a curve over the FX time. Shown and edited in the timeline.

## Param groups

| Group | Params | Modes | Timeline |
|---|---|---|---|
| Emitter | emission settings (rate, burst count, angle, shape dimensions...) | Constant | animatable ones take an animation curve |
| Spawn | lifetime, start speed, start world speed | Constant, Range | `value` / `min` / `max` take an animation curve, read when the particle spawns |
| Particle | speed, world speed, acceleration, world acceleration, orbit speed, dampen, max velocity, scale, stretch, stretch velocity, rotation, pivot, offset | all | — |
| Particle shader params | params of the shaders applied to the particles | Constant, Curve (random modes later) | — |
| Multipliers | scale multiplier, orbit speed multiplier | Constant | take an animation curve, read every frame |

Vector params have one mode per component. Rotations are in degrees, rotation speeds (orbit speed) in degrees per second.
Particle shaders get their per-particle randomness on the GPU, from the emitter's `particleRandom`.
A shader under an emitter stores its particle params on itself, in an optional field only used under an emitter: the same mode data as the emitter params, so the curve gives the value (shape: curve or easing, `from` / `to`).

## Modes

| Mode | Label | Fields | Value |
|---|---|---|---|
| unset | **+** | — | default value of the param |
| `Constant` | Constant | `value` | `value` |
| `Range` | Range | `min`, `max` | `lerp(min, max, u)` |
| `Curve` | Curve | `shape`, `from`, `to` | `lerp(from, to, s(t))` |
| `RandomCurve` | Random Curve | `shape`, `from: {min, max}`, `to: {min, max}` | `lerp(lerp(from.min, from.max, u), lerp(to.min, to.max, u), s(t))` |
| `CurveRange` | Curve Range | `a`, `b`, each `{shape, from, to}` | `lerp(a(t), b(t), u)` |

- `t`: particle life in [0, 1]. `s(t)`: the shape evaluated at `t`.
- `u`: a random in [0, 1], one draw per particle and per param component, keyed by the param. Every random field of a mode uses the same draw.
- `from` / `to` default to 0 / 1.
- Unset params show a **+** button; Constant offers a reset to the default value.

## Shapes

A shape is either:

- a **curve**: a reference, by path, to a curve prefab in the hierarchy. A curve keeps its own options: blend between two curves by an FX parameter, time remap (by an FX parameter or by another curve), loop.
- an **easing**: an enum, `Linear` and `{Sine, Quad, Cubic, Quart, Quint, Expo, Circ, Back, Elastic, Bounce} × {In, Out, InOut}`.

The range (`from` / `to`) belongs to the param; a reference shares the shape only.

## Animation curves

- They set the animated value directly.
- They hold plain keys: no range, no random. Constants of the old data are baked into the keys.
- Targets: transforms, shader params outside emitters, Emitter params, Spawn `value` / `min` / `max`, Multipliers.
- Animation curves are children of the animated prefab, found by name (the property name, `:x` / `:y` / `:z` per component, e.g. `position:x`, `emitRate`, `startSpeed:x:min`). The inspector marks properties that have one.

## Storage

- Params are stored under their plain name (`scale`, `startSpeed`...), each component with its mode and fields.
- Old files are converted once by a migration tool in `hide/tools`, run over a whole project: it rewrites every old-format file, updates the files that override or point at what it changes, only touches the nodes it changes, and is idempotent. Loading an old-format file still works as a fallback: the same migration code upgrades it in memory, alone (no fixes in other files), with a warning recommending the tool.
- Every FX file carries a format `version` at its root (no version = 0, the old format); everything inside the file, including its Reference overrides, follows it. Upgrade steps are keyed by version. A project is always migrated as a whole.

## Upgrade

Rule: runtime-equivalent whenever possible, while simplifying.

`k`: base value, `a`: random amount (`_rand`), `c`: curve.

| Old | New |
|---|---|
| `k` | Constant `k` |
| `k ± a` | Range `[k−a, k+a]` |
| `k·c` | Curve `c`, from 0, to `k` |
| `(k ± a)·c` | RandomCurve `c`, from `{0, 0}`, to `{k−a, k+a}` |
| `k ± a + c` (rotation, offset, pivot) | RandomCurve `c`, from `{k−a, k+a}`, to `{k−a+1, k+a+1}` |
| random between two curves | CurveRange, both curves with from 0, to 1 |
| curve blend / time remap / loop | kept on the curve |
| lifetime + lifetime random | Spawn, Range |
| start speed curves (FX time) | animation curves on its Spawn fields, baked |
| scale / orbit speed over time | Multipliers, Constant or animation curve |
| emitter param `k·c` | animation curve, `k` baked |
| object transform curves | animation curves overriding the transform, exact affine bakes of the old ones (rotation curves in turns become degrees), no sampling: the base rotation folded into the euler angles (from another euler triple of the same rotation, then stored on the object), the animated scale moved before the base rotation (components permuted); otherwise (a rotation the euler curves cannot follow, a scale the base rotation shears) a parent object with the original name takes the animation as it is and the object keeps its base transform as `<name>_base`, which the look at and constraint targets now name; a look at with a lock axis, a billboard, an emitter, a swarm, the direct children of a shader target, swarm or GPU emitter, and an object that would become a leaf of a local animation keep an approximation instead (the scale read from the largest components of the base rotation) |
| orbit speed (radians per second) | degrees per second |
| particle shader float `c·k` | Curve `c`, from 0, to `k` |
| particle shader vector, some components animated | animated components: Curve; the others: Constant 0 |

Validation (fxbench, outside the repo): old hide on the old files against new hide on the migrated files, over the games' .fx: param values as canonical formulas (constants rounded, randoms compared by structure), animation curves sampled over time, object transforms simulated over time, and rendered sheets.

## UI

- Each param (or component) has a mode dropdown, restricted to the modes of its group, shown as a caret (the mode in its tooltip). The components of a vector are on one line while they are all constant.
- A curve mode made from a constant, a range or nothing goes from 0 to 1.
- Curve modes show their particle curves in an inline curve editor. Random Curve: `from` fields at the bottom, `to` fields at the top, the shape at mid range as a solid line, the two extremes dashed. Keys are edited in display space. The editor has a Y grid (0 stronger) and shows at least 0 to 1: framed on the curve when built or with F, zoomed vertically by hand with its +/- buttons or Shift + wheel.
- Curve Range: two stacked curve editors.
- In the FX editor, animated properties are marked in the inspector, Blender-like.
