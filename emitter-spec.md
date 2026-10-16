# Emitter params — spec

Scope: `Emitter` and `Emitter2D`. Editing through the new inspector only (edit2 / HideKit), in the JS editor (hide_js); HideHL is dropped. Colors (particle shader color curves, emitter random color / gradient) keep their current model.

## Terms

- **Particle curve**: a curve over the life of a particle, time in [0, 1]. Edited inline in the inspector, shown in the timeline only when it is selected.
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
| unset | Default value | — | default value of the param |
| `Constant` | Constant | `value` | `value` |
| `Range` | Range | `min`, `max` | `lerp(min, max, u)` |
| `Curve` | Curve | `shape`, `from`, `to` | `lerp(from, to, s(t))` |
| `RandomCurve` | Random Curve | `shape`, `from: {min, max}`, `to: {min, max}` | `lerp(lerp(from.min, from.max, u), lerp(to.min, to.max, u), s(t))` |
| `CurveRange` | Curve Range | `a`, `b`, each `{shape, from, to}`, two plain curves | `lerp(a(t), b(t), u)` |

- `t`: particle life in [0, 1]. `s(t)`: the shape evaluated at `t`.
- `u`: a random in [0, 1], one draw per particle and per param component, keyed by the param. Every random field of a mode uses the same draw.
- `from` / `to` default to 0 / 1.
- Unset and the default value are the same: an unset param shows its default value grayed out, editing it sets it, and a constant set back to its default (by hand or by a reset) is unset.

## Shapes

A shape is either:

- a **curve**: a reference, by path, to a curve prefab in the hierarchy. A curve is one of: plain keys (with loop); a blend of two plain curves by an FX parameter; plain keys remapped by an FX parameter (read at its value instead of the time); a reference to one of these (resolved when the values are built, its scale and offset folded into the range).
- an **easing**: an enum, `Linear` and `{Sine, Quad, Cubic, Quart, Quint, Expo, Circ, Back, Elastic, Bounce} × {In, Out, InOut}`. Not in Curve Range.

The range (`from` / `to`) belongs to the param; a reference shares the shape only.
Rejected when the values are built (an error), and not offered by the curve inspector: a remap by another curve, a remapped blend or reference, a blend of curves that are not plain, an easing or a curve by a parameter in Curve Range.

## Animation curves

- They set the animated value directly.
- They hold plain keys: no range, no random. Constants of the old data are baked into the keys. They take the same curve forms as the shapes, over the FX time, and a random between two plain curves (Random Blend, on Emitter and Spawn `value` fields).
- A Spawn param is read when the particle spawns: its value, or a random between its `min` and `max`, both at the FX time.
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
| curve blend / time remap by a parameter / loop | kept on the curve |
| time remap by another curve, remapped blend or reference, blend of curves that are not plain | migration error |
| lifetime + lifetime random | Spawn, Range |
| start speed curves (FX time) | animation curves on its Spawn fields, baked |
| scale / orbit speed over time | Multipliers, Constant or animation curve |
| emitter param `k·c` | animation curve, `k` baked |
| object transform curves | animation curves overriding the transform, exact affine bakes of the old ones (rotation curves in turns become degrees): the base rotation folded into the euler angles (from another euler triple of the same rotation, then stored on the object), the animated scale moved before the base rotation (components permuted); a rotation the euler curves cannot follow gets a parent object with the original name, which takes the animation as it is, the object keeping its base transform as `<name>_base`, which the look at and constraint targets now name; a scale the base rotation shears, and such a rotation on an object that cannot get a parent (a look at with a lock axis, a billboard, an emitter, a swarm, the direct children of a shader target, swarm or GPU emitter, an object that would become a leaf of a local animation), are sampled to what the old runtime showed (`setTransform`: the shear dropped, the quaternion normalized, the previous rotation kept while a scale is 0), with a migration warning |
| orbit speed (radians per second) | degrees per second |
| particle shader float `c·k` | Curve `c`, from 0, to `k` |
| particle shader vector, some components animated | animated components: Curve; the others: Constant 0 |

Validation (fxbench, outside the repo): old hide on the old files against new hide on the migrated files, over the games' .fx: param values as canonical formulas (constants rounded, randoms compared by structure), animation curves sampled over time, object transforms simulated over time, and rendered sheets.

## UI

- The right click menu of a param component (on its field, or on the label of its line) switches its mode, restricted to the modes of its group, and removes it (**Remove X**) or the whole param (**Remove all**). The components of a vector are on one line while they are all constant or unset.
- The shape dropdown: **New curve**, **Reference** (the curves under the emitter), **Easing** (with thumbnails; Quart and Quint are not offered, they stay shown where they are used).
- A curve mode made from a constant, a range or nothing goes from 0 to 1.
- Curve modes show their particle curves in an inline curve editor. Below the editor, on one line, the `from` fields at the left (the birth of the particle) and the `to` ones at the right (its death), a button between them swapping them. Random Curve: the shape at mid range as a solid line, the two extremes dashed. Keys are edited in display space, as in the timeline curve editor: key modes (Aligned, Free, Linear, Constant) and tangent handles, Ctrl + click adds a key, Delete removes it, right click for the key menu, double click for its time and value. The editor has a labelled Y grid in integer steps (0 stronger) and shows at least 0 to 1: framed on the curve when built or with F, zoomed vertically around its center with its +/- buttons or Shift + wheel.
- Curve Range: two stacked curve editors.
- The FX timeline shows the animation curves only, and a particle curve when it is selected (over the particle life, 0 to 1).
- In the FX editor, animated properties are marked in the inspector, Blender-like; the right click menu of an animatable field animates it and inserts or removes keys.
