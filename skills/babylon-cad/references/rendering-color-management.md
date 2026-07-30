# Rendering Color Management & Environment Lighting

The classic Babylon failure mode — "the model is black / washed out / overexposed" — is almost never a bug in the mesh or the material. It is a color-management mismatch. This file covers the half of the pipeline that `materials.md` does not: tone mapping, exposure, and texture color spaces.

## The Image Processing Pipeline

Babylon applies an image-processing step (tone mapping, exposure, contrast, color grading) to **PBR-based materials only**. Control it at the scene level:

```typescript
import { ImageProcessingConfiguration } from "@babylonjs/core/Materials/imageProcessingConfiguration";

const ip = scene.imageProcessingConfiguration;
ip.toneMappingEnabled = true;
ip.toneMappingType = ImageProcessingConfiguration.TONEMAPPING_ACES; // filmic highlight rolloff
ip.exposure = 1.0;   // brightness multiplier — raise to lift, lower to tame blowout
ip.contrast = 1.0;   // >1 deepens shadows, <1 flattens
```

Key facts:

- **`TONEMAPPING_ACES` vs `TONEMAPPING_STANDARD`**: ACES compresses highlights smoothly (no clipped white blobs under strong IBL) but darkens/desaturates slightly; Standard is a plain clamp that keeps colors literal but blows out easily. Product viewers usually want ACES; technical/diagram renders may want Standard.
- **`StandardMaterial` ignores this pipeline.** If part of the scene uses PBR and part uses Standard, tone mapping changes appear to "only affect some meshes" — that is expected, not a bug. For consistent color management, use PBR throughout.
- Per-material override: a `PBRMaterial` gets its own `imageProcessingConfiguration` when you need one mesh to escape the scene settings — rare; prefer scene-level consistency.

## PBR + EnvironmentTexture Is a Pair

A metallic PBR surface with no environment texture has **nothing to reflect** and renders black no matter how many lights you add:

```typescript
import { CubeTexture } from "@babylonjs/core/Materials/Textures/cubeTexture";

scene.environmentTexture = CubeTexture.CreateFromPrefilteredData("environment.env", scene);
scene.environmentIntensity = 1.0; // master dimmer for IBL — lights stay untouched
```

(Loading variants — `.env` vs `.hdr` vs `createDefaultEnvironment()` — are covered in `materials.md` § Environment & HDR.)

Rules:

- Treat `environmentTexture` as **mandatory** in any PBR scene. It is both the reflection source and the ambient light.
- Tune brightness with `environmentIntensity` first, `exposure` second. Cranking exposure to fix a dim scene also amplifies every light and blows out highlights.
- Metallic parts are the canary: if metals look wrong, the environment is wrong. Check plastics second.

## Texture Color Spaces (sRGB vs Linear)

Color data and math data live in different spaces, and Babylon must be told which is which via `texture.gammaSpace`:

```typescript
import { Texture } from "@babylonjs/core/Materials/Textures/texture";

const albedo = new Texture("part_albedo.jpg", scene);   // gammaSpace defaults to true (sRGB) — correct
const normal = new Texture("part_normal.jpg", scene);
normal.gammaSpace = false;                               // data textures MUST be linear
const metallicRoughness = new Texture("part_mr.jpg", scene);
metallicRoughness.gammaSpace = false;
```

- **sRGB (`gammaSpace = true`, the default)**: albedo/base color, emissive — anything a human painted to be looked at.
- **Linear (`gammaSpace = false`)**: normal maps, metallic/roughness/AO maps — anything the shader reads as numbers.
- Symptom of getting it wrong: normals produce "waxy" or inverted lighting; metallic maps make everything chrome or nothing chrome.
- glTF assets need none of this — the loader assigns spaces per the spec. Hand-built `Texture` assignments do.

## Symptom Decision Tree

| Symptom | First thing to check |
|---|---|
| Model is **black**, especially metals | `scene.environmentTexture` missing or failed to load; then `environmentIntensity` |
| Scene **washed out / flat** | `exposure` > 1 or `environmentIntensity` too high; or tone mapping disabled with a strong IBL |
| **Overexposed** white blobs | `toneMappingEnabled = false`, or STANDARD tone mapping with HDR environment; enable ACES |
| Colors **shifted / waxy** | a data texture (normal/MR) left at `gammaSpace = true`, or an albedo forced to linear |
| Tone mapping "works on some meshes only" | those meshes use `StandardMaterial` — it ignores the image-processing pipeline |
| Looks right in the editor, wrong in the app | editor (Sandbox/Inspector) enables ACES + default environment; your scene must opt in explicitly |

## Related

- Texture loading, UV wrapping, PBR channel wiring: [materials.md](materials.md)
- Official docs on demand: [doc-urls.md](doc-urls.md)

---

Back to [SKILL.md](../SKILL.md)
