# Emitter params — spec

Scope: `Emitter` and `Emitter2D`. Editing through the new inspector only (edit2 / HideKit). Colors (particle shader color curves, emitter random color / gradient) keep their current model.

## Terms

- **Particle curve**: a curve over the life of a particle, time in [0, 1]. Edited inline in the inspector, never shown in the timeline.
- **Animation curve**: a curve over the FX time. Shown and edited in the timeline.

## Param groups

| Group | Params | Modes | Timeline |
|---|---|---|---|
| Emitter | emission settings (rate, burst count, angle, shape dimensions...) | Constant | animatable ones take an animation curve |
| Spawn | lifetime, start speed, start world speed | Constant, Range | `value` / `min` / `max` take an animation curve, read when the particle spawns |
| Particle | speed, world speed, acceleration, world acceleration, orbit speed, dampen, max velocity, scale, stretch, stretch velocity, rotation, pivot, offset; particle shader params | all | — |
| Multipliers | scale multiplier, orbit speed multiplier | Constant | take an animation curve, read every frame |

Vector params have one mode per component.

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
- A param references its animation curves by path, like particle curves; curve names carry no meaning. The upgrade binds each param to its existing curve, under its old name.

## Storage

- Params are stored under their plain name (`scale`, `startSpeed`...), each component with its mode and fields.
- Old files are upgraded on load and saved upgraded.

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
| emitter object transform curves | animation curves, re-baked to override the transform |
| particle shader float `c·k` | Curve `c`, from 0, to `k` |
| particle shader vector, some components animated | animated components: Curve; the others: Constant 0 |

Validation: a batch run over the games' .fx, outside the repo, that prints each param as a canonical formula before and after the upgrade and compares them (constants rounded, randoms compared by structure).

## UI

- Each param (or component) has a mode dropdown, restricted to the modes of its group.
- Curve modes show their particle curves in an inline curve editor. Random Curve: `from` fields at the bottom, `to` fields at the top, the shape at mid range as a solid line, the two extremes dashed. Keys are edited in display space.
- Curve Range: two stacked curve editors.
- In the FX editor, animated properties are marked in the inspector, Blender-like.
