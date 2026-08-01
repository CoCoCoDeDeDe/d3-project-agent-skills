# Rendering Troubleshooting — Field-Debugged Failure Patterns

Symptom-first catalog of non-obvious Babylon.js rendering failures. Each entry: symptom → root cause → fix. For color/brightness problems see `rendering-color-management.md`; for generic z-fighting see `depth-precision.md`.

## Only back faces render after window resize

**Symptom:** Scene looks "inside-out" (normals appear flipped, you see interior surfaces) after maximizing/restoring the window. Opening browser devtools (which triggers another resize) mysteriously fixes it. No console errors.

**Root cause:** A `RenderTargetTexture` used as a post-process input lost its **depth attachment** when the engine recreated framebuffers on resize. Without depth, the mask/occlusion pass degrades and geometry renders with reversed face visibility. Devtools "fixing" it = the extra resize recreated the buffer again.

**Fix:** When a post-process or custom RTT needs depth, ensure the RTT is created with a depth/stencil attachment (`generateDepthBuffer` / `depthStencilTexture` options) and that it is recreated (not just resized) when the canvas size changes. Bisect first with kill-switches: disable post-processes one at a time (`?postprocess=0` style query flags) until the artifact disappears — that isolates which RTT is stale.

## Transparent mesh shows "shattered" flickering triangles on a contact plane

**Symptom:** After making a mesh semi-transparent (hover/ghost highlight), faces that touch another surface (model bottom coplanar with a build plate) show exploding/shattered triangles that flicker as the camera moves. Opaque rendering was fine.

**Root cause:** Transparency exposes interior surfaces that depth-testing used to discard. Coplanar faces (within one depth step of each other) now both have an audience and z-fight per-pixel.

**Fix (two complementary tools):**

```typescript
material.needDepthPrePass = true; // per-pixel, only the nearest layer of THIS mesh blends
material.zOffsetUnits = -2;       // gl.polygonOffset units: pull mesh 2 depth steps toward camera
```

- `needDepthPrePass` wins within the mesh (multiple layers, duplicate coplanar faces, self-interior). Only affects alpha-blended materials.
- `zOffsetUnits` wins between two objects (contact plane at grazing angles). Units are depth steps, spatially invisible; don't crank them up.
- Cache and restore `alpha`, `zOffset`, `zOffsetUnits`, `needDepthPrePass` together when the highlight is temporary, and only when each mesh owns its material (clone shared materials first).

## WebGL warnings: "no texture bound to target" (texImage2D / generateMipmap / texParameter)

**Symptom:** A burst of `INVALID_OPERATION: no texture bound to target` warnings on startup, sometimes followed by broken environment lighting or a stuck "compiling effect" loop. Happens in React apps, intermittently.

**Root cause:** React **StrictMode double-mounts** the component: first mount starts an async texture load (e.g. cubemap/IBL), cleanup synchronously disposes the scene/engine, then the in-flight load completes and still runs its texture-upload sequence against the disposed context.

**Fix:** Defer the async apply past the synchronous cleanup and gate it with a disposed flag:

```typescript
let sceneDisposed = false;
const timer = setTimeout(() => {
  if (!sceneDisposed) applyEnvironmentTexture(scene);
}, 0);
return () => {
  sceneDisposed = true;
  clearTimeout(timer);
  scene.dispose();
};
```

The `setTimeout(0)` moves the upload after the first mount's cleanup has run, so only the surviving (second) mount's work lands.

## UMD decoder/library breaks under native ESM: "does not provide an export named 'default'"

**Symptom:** Page dies at module evaluation with `The requested module '...js' does not provide an export named 'default'` — typically an Emscripten-built decoder (Draco, meshopt) imported with a static `import`.

**Root cause:** The UMD bundle has no ESM exports. Under bundlers it hits the CJS branch and works; served as native ESM (vite dev serving source) there is nothing to import.

**Fix — split by runtime:**

```typescript
// Browser: inject a classic <script> — UMD top-level var lands on globalThis
await injectScriptOnce(decoderUrl);
const factory = (globalThis as any).DracoDecoderModule;
// Node (unit tests): dynamic import hits the UMD CJS branch
const factory = (await import('./draco_decoder.js')).default;
```

Branch on `typeof document === 'undefined'`. Never statically import the UMD file from application code.

## Debugging tactics that worked

- **Kill-switch query params** (`?postprocess=0&stencil=0&aa=0`): binary-search which pipeline stage produces the artifact before reading any code.
- **Devtools changing behavior is a clue, not noise:** open/closed devtools toggles canvas size → resize-dependent bugs (stale framebuffers) show up as "works with devtools open".
- **Symptom first, tool second:** identify *which two surfaces* are fighting before reaching for polygonOffset — the wrong tool (offset vs. pre-pass) changes nothing.
