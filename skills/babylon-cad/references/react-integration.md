# React Integration for Babylon.js 8

Babylon owns imperative, disposable GPU resources; React owns declarative UI. The entire discipline of integration is keeping those two worlds from leaking into each other. This chapter is the standard pattern for production React apps.

## The Core Rules

1. **Babylon objects live in refs, never in React state.** `Engine`, `Scene`, `Mesh`, `Material`, `Observable` observers — all of them. Putting them in state causes stale closures and double-creation.
2. **Create once, dispose once.** Engine/scene creation belongs in an effect with an empty dependency array. The cleanup function must dispose everything, in reverse order of creation.
3. **React state drives Babylon only through effects.** A prop/state change that should affect the scene (color, visibility, selected part) goes through an effect that mutates Babylon objects imperatively. Never rebuild the scene because React state changed.
4. **Babylon events drive React only through stable callbacks.** Inside `onPointerObservable` etc., call stable `useCallback`/`useRef`-held functions that `setState`. Never let a Babylon observer closure capture stale state — read latest values via refs.

## Canonical Hook

```tsx
import { useEffect, useRef } from "react";
import { Engine } from "@babylonjs/core/Engines/engine";
import { Scene } from "@babylonjs/core/scene";

export function useBabylon(canvasRef: React.RefObject<HTMLCanvasElement>) {
  const engineRef = useRef<Engine | null>(null);
  const sceneRef = useRef<Scene | null>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    // StrictMode mounts effects twice in dev — always create fresh,
    // always dispose in cleanup, and the second mount wins.
    const engine = new Engine(canvas, true);
    const scene = new Scene(engine);
    engineRef.current = engine;
    sceneRef.current = scene;

    engine.runRenderLoop(() => scene.render());
    const onResize = () => engine.resize();
    window.addEventListener("resize", onResize);

    return () => {
      window.removeEventListener("resize", onResize);
      engine.stopRenderLoop();
      scene.dispose();   // disposes meshes, materials, textures in the scene
      engine.dispose();
      engineRef.current = null;
      sceneRef.current = null;
    };
  }, []); // empty: engine/scene are created exactly once per canvas lifetime

  return { engineRef, sceneRef };
}
```

## StrictMode Double-Mount

React 18 dev mode mounts → unmounts → remounts every component. Symptoms when the pattern is wrong: two render loops fighting, blank canvas, WebGL context leaks, "context lost" warnings.

- The cleanup above already handles it: first mount's engine is fully disposed before the second is created.
- **Never** guard with a module-level `if (engine) return` singleton — it defeats the disposal path and leaks the first canvas.
- Avoid `engine.dispose()` without `scene.dispose()` first; reverse-creation order is mandatory.

## Observers: the Stale-Closure Trap

```tsx
const selectedRef = useRef<string | null>(null);
selectedRef.current = selectedId; // keep in sync every render

useEffect(() => {
  const scene = sceneRef.current;
  if (!scene) return;
  const observer = scene.onPointerObservable.add((info) => {
    if (info.type === PointerEventTypes.POINTERPICK) {
      // read via ref, never via captured state
      const prev = selectedRef.current;
      onPick(info.pickInfo?.pickedMesh?.name ?? null, prev);
    }
  });
  return () => { scene.onPointerObservable.remove(observer); };
}, [onPick]); // re-subscribe only when the stable callback changes
```

Every `observable.add()` must have a matching `remove(observer)` in cleanup — Babylon holds observers on the scene, so a leaked observer survives the component and calls dead `setState`s.

## State → Scene Updates

```tsx
// prop change → imperative mutation, no rebuild
useEffect(() => {
  const mesh = sceneRef.current?.getMeshByName(partId);
  if (mesh) mesh.visibility = highlighted ? 1 : 0.3;
}, [partId, highlighted]);
```

Rebuild geometry only when the parameter set actually changes (CAD param edits), and dispose the old mesh in the same effect before creating the new one.

## Render Loop Ownership

Exactly one `runRenderLoop` per engine. Per-frame logic (idle rotation, animations driven by time) goes inside that single loop or on `scene.onBeforeRenderObservable` — never in `requestAnimationFrame` alongside Babylon's loop.

## Interaction with State Machines

If interaction logic is orchestrated by XState, the Babylon side stays dumb: observers only **send events** (`actor.send({ type: 'POINTER_DOWN', point })`), and effects only **apply snapshots** (actor state → camera/material/mesh changes). No business logic in observers, no Babylon API calls inside machine guards. See the `xstate` skill for the actor-side pattern.

## Common Mistakes

1. `const [scene, setScene] = useState()` — state-held scene → double creation, stale closures.
2. Missing `remove(observer)` — leaked observers accumulate across mounts and fire multiple times.
3. Mutating Babylon objects during render (outside effects) — breaks under concurrent rendering.
4. Rebuilding the whole scene on every param change instead of disposing/replacing only the affected mesh.
5. `canvas` sizing: set `width/height` via CSS plus `engine.resize()` — never stretch via CSS alone without resize, or picking coordinates drift.
