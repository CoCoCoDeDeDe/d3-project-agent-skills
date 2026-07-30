# Depth Precision & Z-Fighting

Z-fighting (flickering surfaces, shimmer on coplanar geometry, distant parts punching through each other) is a depth-buffer precision problem. In a 3D-printing CAD — millimeter-scale parts sitting on a meter-scale grid — it is not an edge case, it is the default. The fixes, in the order you should reach for them:

## 1. Camera near/far Discipline (Fix This First)

A 24-bit depth buffer distributes precision proportionally to **1/z** — most of it lands near `minZ`. The usable range is governed by the **ratio** `maxZ / minZ`, not by absolute distances:

```typescript
camera.minZ = 0.001; // 1 mm, if your smallest visible feature is ~mm scale
camera.maxZ = 50;    // the furthest thing actually in the scene — not "just in case" 10000
```

Rules:

- **`minZ` as LARGE as the scene allows.** Halving `minZ` costs more precision than doubling `maxZ`. LLM-generated code loves `minZ = 0.0001` — that single number can make an entire scene shimmer.
- Keep `maxZ / minZ` within roughly 10⁴–10⁵ for a 24-bit buffer. `minZ 0.1 / maxZ 10000` (a common default-ish pair) is already borderline.
- Both are plain camera properties in Babylon — changing them takes effect on the next frame, no rebuild needed.

## 2. Unit Scale Drives the Ratio

Depth precision is a second-order reason to pick scene units deliberately:

- Choose units so a typical part spans ~1–1000 units (for print CAD, **1 unit = 1 mm** works well: parts land at 10–500 units, `minZ 0.1` = 0.1 mm, `maxZ 5000` covers a large build plate at ratio 5×10⁴).
- A scene authored in meters showing 0.001-size parts forces an extreme near plane; a scene in millimeters showing kilometers forces an extreme far plane. Both destroy the ratio.
- Unit choice also decides export conversions later — STL is unit-less and conventionally read as millimeters, so the scene unit and the export pipeline must agree (the print-export work tracks this separately).

## 3. Coplanar Geometry: zOffset

Decals, dimension annotations on faces, grid lines lying on the ground — anything sharing a plane with another surface — will z-fight no matter how good the ratio is. Use material depth offset:

```typescript
gridMaterial.zOffset = -2;       // pull toward camera in depth-test units
gridMaterial.zOffsetUnits = -2;  // same idea in absolute (non-sloped) units
```

- Negative values win the depth test against the coplanar surface beneath.
- `zOffset` scales with polygon slope; `zOffsetUnits` is constant. For ground grids and face decals, `zOffsetUnits` is usually the predictable one.
- Do NOT fix coplanar fighting by nudging positions (`mesh.position.y += 0.001`) — the gap becomes visible geometry at glancing angles and breaks print-accurate measurements.

## 4. Logarithmic Depth (Last Resort, WebGL)

When the ratio genuinely cannot be reduced (huge scenes with tiny details), Babylon offers per-material logarithmic depth:

```typescript
material.useLogarithmicDepth = true;
```

Costs and constraints — read these before enabling:

- **Per material**, and it must be applied to **every** material whose meshes interleave in depth — mixed log/linear materials compare depths in different spaces and produce worse artifacts than the original fighting.
- Disables early-z rejection (depth computed in the fragment shader) — measurably slower on fill-bound scenes.
- Custom shaders and Node Materials do not support it automatically.
- On WebGL1 it needs the `EXT_frag_depth` extension; on WebGL2 it just works.

It is a legitimate tool for solar-system-scale scenes. For a desktop CAD viewport, fixing the near/far ratio (steps 1–2) almost always makes it unnecessary.

## 5. Reverse Depth Buffer (WebGPU Only)

`engine.useReverseDepthBuffer = true` flips the depth range (near → 1, far → 0) and gives far geometry better distribution. Babylon team guidance: it only pays off with **WebGPU** — on WebGL, use logarithmic depth instead. Relevant if your app already targets WebGPU; otherwise skip.

## Diagnostic Quick Check

When a scene shimmers: print `camera.minZ / camera.maxZ` and the ratio first. If the ratio is > 10⁵, fix the planes. If the fighting is between two surfaces at the same depth, use `zOffset`. Only reach for logarithmic depth when neither applies.

## Related

- Camera types and defaults: [core-concepts.md](core-concepts.md) § Cameras
- Material properties including `zOffset`: [materials.md](materials.md)

---

Back to [SKILL.md](../SKILL.md)
