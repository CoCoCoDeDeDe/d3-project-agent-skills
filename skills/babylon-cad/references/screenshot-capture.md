# Screenshots & Offscreen Rendering

Capturing the canvas — user-triggered screenshots, share previews, part-library thumbnails — looks trivial and fails in three specific ways: timing (black image), orientation (flipped Y), and alpha (black background instead of transparent). This file covers all three plus a thumbnail pipeline.

## The Two Capture APIs

```typescript
import { Tools } from "@babylonjs/core/Misc/tools";

// Simple path: re-renders the scene to an internal target, hands back a data URL
Tools.CreateScreenshot(engine, camera, { width: 1024, height: 1024 }, (data) => {
  // data is a base64 data URL — assign to <img>, download link, or upload
}, "image/png");

// Promise variants exist for both APIs:
// await Tools.CreateScreenshotAsync(engine, camera, size, "image/png")
```

- `CreateScreenshot` / `CreateScreenshotAsync` — one-off captures at an arbitrary resolution. Simple, but re-renders synchronously on the calling frame.
- `CreateScreenshotUsingRenderTarget` — same result through an explicit render-target path; historically more reliable for large sizes and antialiasing. Use it when the simple API gives artifacts at big resolutions.
- Both take the **camera** as an argument — the capture uses that camera's view, not necessarily the active one.

## Timing: Never Capture Before a Frame Has Rendered

The #1 bug: calling `CreateScreenshot` right after scene construction (or right after a state change) and getting a black image. The scene must have completed at least one render with the final content:

```typescript
scene.executeWhenReady(() => {
  scene.onAfterRenderObservable.addOnce(() => {
    Tools.CreateScreenshot(engine, camera, 512, (data) => { /* ... */ });
  });
});
```

In React, this means "not in the mount effect." Trigger captures from user actions, or chain them after the observable confirms content is on screen. Mutations made in the same frame as the capture call are not guaranteed to be visible — wait one render.

## Y-Flip: Only When You Read Pixels Yourself

`CreateScreenshot` returns correctly-oriented images. The vertical flip bites only when you bypass it and read the framebuffer directly:

```typescript
// engine.readPixels returns rows BOTTOM-TO-TOP (WebGL convention)
const pixels = engine.readPixels(0, 0, width, height); // Uint8Array, row 0 = bottom row
// flip the rows yourself before putting them into ImageData / a 2D canvas
```

Rule: use `CreateScreenshot` for user-facing captures; handle `readPixels` only inside pipelines (thumbnails below), where you control the flip.

## Transparent-Background Captures

A PNG with real transparency needs three settings to agree — miss one and you get black or a halo:

```typescript
import { Color4 } from "@babylonjs/core/Maths/math.color";

// 1. Engine creation: premultipliedAlpha OFF (do this once, at engine init)
const engine = new Engine(canvas, true, { premultipliedAlpha: false, preserveDrawingBuffer: true });

// 2. Scene: fully transparent clear color
scene.clearColor = new Color4(0, 0, 0, 0);

// 3. Capture as PNG (JPEG has no alpha channel — it will come out black)
Tools.CreateScreenshot(engine, camera, 512, cb, "image/png");
```

`preserveDrawingBuffer: true` is also required if you ever read the canvas directly (`canvas.toDataURL()`) instead of going through Babylon's APIs — without it the buffer may already be cleared.

## Part Thumbnail Pipeline (Offscreen)

Thumbnails should not disturb the main viewport: render the part with a dedicated camera into a `RenderTargetTexture`, read it back, convert to a blob.

```typescript
import { RenderTargetTexture } from "@babylonjs/core/Materials/Textures/renderTargetTexture";
import { Vector3 } from "@babylonjs/core/Maths/math.vector";

const rtt = new RenderTargetTexture("thumb", 256, scene); // 256x256 offscreen target
rtt.renderList = [partMesh];                              // ONLY the part — no grid, no gizmos
rtt.refreshRate = RenderTargetTexture.REFRESHRATE_RENDER_ONCE;

// Dedicated camera, framed on the part's bounding sphere
const thumbCam = new ArcRotateCamera("thumbCam", Math.PI / 4, Math.PI / 3, 1, Vector3.Zero(), scene);
const sphere = partMesh.getBoundingInfo().boundingSphere;
thumbCam.target = sphere.centerWorld;
thumbCam.radius = sphere.radiusWorld * 2.2;               // zoom-to-fit with margin
rtt.activeCamera = thumbCam;                              // capture uses THIS camera

rtt.onAfterRenderObservable.addOnce(async () => {
  const pixels = await rtt.readPixels() as Uint8Array;    // bottom-to-top rows!
  // flip rows → ImageData → OffscreenCanvas/canvas2d → toBlob("image/png")
});
scene.customRenderTargets.push(rtt);                      // engine renders it next frame
// after readback: scene.customRenderTargets.pop(); rtt.dispose();
```

Checklist for this pipeline:

- `renderList` contains **only** the part — helper meshes, grids, and gizmos must stay out (another reason helpers get `isPickable = false`-style quarantine discipline).
- Frame from `boundingSphere`, never a hardcoded radius — parametric parts vary in size.
- Read pixels after `onAfterRenderObservable`, not immediately after construction.
- Dispose the RTT and camera after the batch; thumbnail generation in a loop leaks GPU textures fast.
- Set the RTT clear color to transparent (`rtt.clearColor = new Color4(0,0,0,0)`) for catalog-style images on colored backgrounds.

## Related

- Zoom-to-fit framing math and bounding info: [meshes.md](meshes.md) § Bounding Info
- Making the capture look right (tone mapping applies to screenshots too): [rendering-color-management.md](rendering-color-management.md)

---

Back to [SKILL.md](../SKILL.md)
