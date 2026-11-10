# Emitter params — spec

Scope: `Emitter` and `Emitter2D`. Editing through the new inspector only (edit2 / HideKit), in the JS editor (hide_js); HideHL is dropped. Particle shader color curves keep their current model.

## Terms

- **Param curve**: the curve of a param in a curve mode, named after the param component. Over the life of a particle (time in [0, 1]) for the Particle params, over the emitter time for the Spawn and Emission ones. Edited inline in the inspector; the particle curves are shown in the timeline only when selected, the others always.
- **Animation curve**: a curve over the FX time, or over the emitter time for the properties of an emitter. Shown and edited in the timeline.
- **Emitter time**: the FX time minus the start delay of the emitter, scaled by its time scale, plus its warm up.

## Param groups

| Kind | Params | Read | Random |
|---|---|---|---|
| Particle | speed, world speed, acceleration, world acceleration, orbit speed, dampen, max speed, offset, pivot, rotation, scale, stretch, stretch by velocity | each tick, over the particle life | per particle |
| Spawn | lifetime, start speed, start world speed | once, when the particle spawns, at the emitter time | per particle |
| Emission | rate, particles per burst | each tick (the rate) or each burst, at the emitter time | drawn by the emitter: the rate goes to a new random value every Rate Change Time, a burst draws its count (for a Range, an integer between the bounds, both included); the random of each step is a hash of the seed, the same whatever the ticks |
| Particle shader params | params of the shaders applied to the particles | each tick, over the particle life | Constant and Curve only |

Every emitter param kind takes every mode. The emitter properties (`@:s`: shape, emit type, scale / orbit speed multipliers...) are plain values; the animatable ones take an animation curve, read once per tick.

Vector params have one mode per component. Rotations are in degrees, rotation speeds (orbit speed) in degrees per second.
Particle shaders get their per-particle randomness on the GPU, from the emitter's `particleRandom`.
A shader under an emitter saves the modes of its params read over the particle life in `particleParams`, by param name, as the params of an emitter (`{ alpha: { mode: "Curve" }, UVOffset: { y: { mode: "Curve" } } }`); their curve is the one of the shader named after the param component (`alpha`, `UVOffset:y`); a component without mode keeps the prop.

## Modes

| Mode | Label | Saved | Value |
|---|---|---|---|
| unset | Default value | — | default value of the param |
| `Constant` | Constant | `value` | `value` |
| `Range` | Range | `min`, `max` | `lerp(min, max, u)` |
| `Curve` | Curve | — | `c(t)` |
| `RandomCurve` | Random Curve | `spreadMin`, `spreadMax` | `v ± spread(v)`, `v = c(t)`: the spread follows the value of the curve, `spreadMin` at its lowest value, `spreadMax` at its highest |
| `CurveRange` | Curve Range | — | `lerp(a(t), b(t), u)`, `a` and `b` the two datas of its curve |

- `t`: the particle life in [0, 1] for a Particle param, the emitter time for the others. `c`: the param curve, its keys the values.
- `u`: a random in [0, 1]: per particle and per param component for the Particle and Spawn params, drawn by the emitter for the Emission ones. Every random field of a mode uses the same draw.
- Unset and the default value are the same: an unset param shows its default value grayed out, editing it sets it, and a constant set back to its default (by hand or by a reset) is unset.

## Param curves

A param curve is the child curve of the owner named after the param component (`partScale`, `partRotation:z`, `startSpeed:x`, `emitRate`), the first enabled one, as every curve of an emitter. A curve is one of: plain keys (with loop); a blend of two plain curves by an FX parameter; plain keys remapped by an FX parameter (read at its value instead of the time); a reference to one of these (resolved when the values are built). A Curve Range reads a curve of two datas (blend mode Range), each one plain keys.
Rejected when the values are built (an error), and not offered by the curve inspector: a remap by another curve, a remapped blend or reference, a blend of curves that are not plain.

## Animation curves

- They set the animated value directly, their keys the values.
- Targets: transforms, shader params outside emitters, the animatable properties of an emitter.
- They are children of the animated prefab, found by name (the property name, `:x` / `:y` / `:z` per component, e.g. `position:x`, `scaleMultiplier`), the first enabled one. The inspector marks properties that have one.

## Storage

- Params are stored directly on the emitter, under their field name, like the properties. The name tells the clock of the curve: the Particle params, read over the particle life, are prefixed with `part` (`partScale`, `partRotation`); the Spawn params and the properties, read over the emitter time, are not (`lifeTime`, `startSpeed`, `emitRate`). A param is a mode, or for a vector an object of the modes of its components (`x`, `y`, `z`, an unset one left out). A curve mode stores no curve, its curve is the one of its name; a curve mode whose curve was deleted is not saved (the param goes back to its default).
- Old files are converted once by a migration tool in `hide/tools`, run over a whole project: it rewrites every old-format file, updates the files that override or point at what it changes, only touches the nodes it changes, and is idempotent. Loading an old-format file still works as a fallback: the same migration code upgrades it in memory, alone (no fixes in other files), with a warning recommending the tool.
- Every FX file carries a format `version` at its root (no version = 0, the old format); everything inside the file, including its Reference overrides, follows it. Upgrade steps are keyed by version. A project is always migrated as a whole.

## Runtime

- The emitter object reads its settings from its prefab (`prefab`, the clone made for this instance), when it uses them. It holds only its evaluator (`EmitterEvaluator`, generated from the prefab: a `Value` per param and animated property, `emitRate`, `lifeTime`, `partScale`..., built by `makeEvaluator`) and its state (`emitScale`, `enable`, the particles).
- Game code overrides a built value on the object (`e.emitRate = VConst(10)`, which replaces its curve too), and changes a setting on the prefab (`e.prefab.emitDuration = 2`). A setting read at init (max count, sprite sheet, particle template) has no effect when changed after the make. A new `updateInstance` rebuilds the values, dropping their overrides.

## Colors

- The 3D emitter has two color settings, each a `RandomColorMode` (None, two colors, gradient), multiplying the pixel color alpha included: the **random color** (one per particle, the per-particle random of `BaseEmitter`) and the **fade color** (over the particle life, from a start color to an end color, or along a gradient). Their colors are ARGB ints. **Fade In** / **Fade Out** (parts of the particle life, 0 for none) fade its alpha in at its birth and out before its death, linearly, as `ParticleFade`.
- When one is set, the emitter adds a single `hrt.shader.ParticleShader` to its batch (no per-instance data beyond `BaseEmitter`). Its settings (modes, colors, gradients) are read at init. This shader is meant to take over the particle shaders (`ParticleColorRandom`, `ParticleColorLife`...).
- The 2D emitter colors are ARGB ints too, alpha read (its random color replaces the color of the particle). The inspector edits an int color with its alpha.

## Upgrade

Rule: runtime-equivalent whenever possible, while simplifying.

`k`: base value, `a`: random amount (`_rand`), `c`: curve.

| Old | New |
|---|---|
| `k` | Constant `k` |
| `k ± a` | Range `[k−a, k+a]` |
| `k·c` | Curve, `c` scaled by `k` |
| `(k ± a)·c` | RandomCurve, `c` scaled by `k`, the spread `a·c` |
| `k ± a + c` (rotation, offset, pivot) | RandomCurve, `c + k`, the spread `a`; a Curve Range when the curve is flat |
| random between two curves | Curve Range, the two curves its datas |
| curve blend / time remap by a parameter / loop | kept on the curve |
| time remap by another curve, remapped blend or reference, blend of curves that are not plain | migration error |
| lifetime + lifetime random | Spawn, Range |
| start speed curves (emitter time) | Spawn, the same as the particle params (Curve, RandomCurve, Curve Range) |
| scale / orbit speed over time | emitter properties, Constant or animation curve |
| emitter property `k·c` | animation curve, `k` baked |
| rate, particles per burst | Emission, Constant or Curve (`k` baked) |
| Infinity Random, rate min / max (and their curves) | Infinity, rate Range, or Curve Range when a bound has a curve; the ramp to the next random rate fixed (it went away from it), the rates the emit type did not read dropped |
| Duration | stops at its duration (it kept emitting at its last rate) |
| object transform curves | animation curves overriding the transform, exact affine bakes of the old ones (rotation curves in turns become degrees): the base rotation folded into the euler angles (from another euler triple of the same rotation, then stored on the object), the animated scale moved before the base rotation (components permuted); a rotation the euler curves cannot follow gets a parent object with the original name, which takes the animation as it is, the object keeping its base transform as `<name>_base`, which the look at and constraint targets now name; a scale the base rotation shears, and such a rotation on an object that cannot get a parent (a look at with a lock axis, a billboard, an emitter, a swarm, the direct children of a shader target, swarm or GPU emitter, an object that would become a leaf of a local animation), are sampled to what the old runtime showed (`setTransform`: the shear dropped, the quaternion normalized, the previous rotation kept while a scale is 0), with a migration warning |
| orbit speed (radians per second) | degrees per second |
| particle shader float `c·k` | Curve, `c` scaled by `k` |
| particle shader vector, some components animated | animated components: Curve; the others: Constant 0 |
| `ParticleFade` on the particles, the only one, static, power 1, not under a disabled or editor only prefab | the emitter Fade In / Fade Out, the shader removed (the others stay) |

Validation (fxbench, outside the repo): old hide on the old files against new hide on the migrated files, over the games' .fx: param values as canonical formulas (constants rounded, randoms compared by structure), animation curves sampled over time, object transforms simulated over time, and rendered sheets.

## UI

- The right click menu of a param component (on its field, or on the label of its line) switches its mode (Constant and Curve only for a particle shader param), and removes it (**Remove X**) or the whole param (**Remove all**). The components of a vector are on one line while they are all constant or unset.
- Switching to a curve mode makes the curve of the param component (or gives the existing one its new values), switching away from them removes it.
- A curve mode keeps the values of the mode it is made from: a constant gives a flat curve, a range a Curve Range of two flat curves.
- Curve modes show their particle curves in an inline curve editor. The curves of the Spawn and Emission params are over the emitter time, without a time limit. Random Curve: the shape at mid range as a solid line, the two extremes dashed. Keys are edited in display space, as in the timeline curve editor: key modes (Aligned, Free, Linear, Constant) and tangent handles, Ctrl + click adds a key, Delete removes it, right click for the key menu, double click for its time and value. The editor has a labelled Y grid in integer steps (0 stronger) and shows at least 0 to 1: framed on the curve when built or with F, zoomed vertically around its center with its +/- buttons or Shift + wheel.
- Curve Range: its two curves in one editor, the band between them.
- The FX timeline shows the animation curves and the param curves over the emitter time (each data of a Curve Range apart), and a particle curve when it is selected (over the particle life, 0 to 1).
- In the FX editor, animated properties are marked in the inspector, Blender-like; the right click menu of an animatable field animates it and inserts or removes keys.
