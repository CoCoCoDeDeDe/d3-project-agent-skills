# Keyboard Shortcuts

CAD users live on the keyboard. Shortcuts in a Babylon app have two recurring traps: where to listen, and focus.

## Where to Listen: scene.onKeyboardObservable

Prefer Babylon's keyboard observable over `window.addEventListener("keydown", ...)`:

```typescript
import { KeyboardEventTypes } from "@babylonjs/core/Events/keyboardEvents";

const kbObserver = scene.onKeyboardObservable.add((info) => {
  if (info.type !== KeyboardEventTypes.KEYDOWN) return;
  const e = info.event;
  const mod = e.ctrlKey || e.metaKey; // macOS Cmd arrives as metaKey

  if (mod && e.key.toLowerCase() === "z" && !e.shiftKey) { /* undo command */ e.preventDefault(); }
  else if ((mod && e.key.toLowerCase() === "y") || (mod && e.shiftKey && e.key.toLowerCase() === "z")) { /* redo command */ e.preventDefault(); }
  else if (e.key === "Delete" || e.key === "Backspace") { /* delete-selection command */ }
  else if (e.key === "Escape") { /* cancel gesture / clear selection */ }
});
// teardown: scene.onKeyboardObservable.remove(kbObserver)
```

Why: the observable is managed by the engine — it is removed automatically when the scene disposes, and it routes through the same input pipeline as pointer events. Raw `window` listeners outlive the canvas, accumulate across React StrictMode remounts, and are the usual source of "undo fires twice" bugs.

## Focus Traps

- **Typing in inputs must not trigger scene shortcuts.** Check the event target before acting:

```typescript
const t = e.target as HTMLElement | null;
if (t instanceof HTMLInputElement || t instanceof HTMLTextAreaElement || t?.isContentEditable) return;
```

- **The canvas needs keyboard focus.** Babylon attaches its keyboard listener to the window, so shortcuts fire globally — but if you ever switch to canvas-level listeners, the canvas requires `canvas.tabIndex = 0` and a click to focus. Know which model you are on; mixing both double-fires.
- **In React**, attach the observer from the same effect that owns the scene (or a dedicated hook with a cleanup), never from a component that unmounts while the scene lives on. A handler registered by an unmounted component either leaks or disappears mid-session.
- Call `e.preventDefault()` **only when the shortcut matched** — swallowing Ctrl+R or F12 because the handler runs unconditionally breaks the browser for the user.

## Modifier-Key Conventions

Match mainstream CAD / editor conventions so users do not have to learn your app:

| Shortcut | Action |
|---|---|
| Ctrl/Cmd+Z | Undo |
| Ctrl/Cmd+Y or Ctrl/Cmd+Shift+Z | Redo |
| Delete / Backspace | Delete selected parts (a command) |
| Ctrl/Cmd+D | Duplicate selection |
| Ctrl/Cmd+A | Select all parts |
| Esc | Cancel current gesture, then clear selection |
| Ctrl/Cmd+C / V | Copy / paste (if the document model supports it) |

Rules:

- Always treat `ctrlKey` and `metaKey` as one modifier — macOS users press Cmd.
- Match on `e.key` (case-normalized), not `e.code`, so layouts (AZERTY, Dvorak) behave; use `e.code` only when the physical position matters (rare in CAD).
- One gesture, one meaning: if Ctrl+Z undoes, no other combo may also undo — duplicate bindings desync user muscle memory and documentation.

## Shortcuts Produce Commands

A shortcut handler constructs a command and hands it to the stack (or sends an XState event that does). It never mutates the scene directly:

```typescript
// inside the keyboard observable — WRONG:
// scene.getMeshByUniqueId(id)?.dispose();

// RIGHT: route through the same write path as every other interaction
commandStack.push(new DeletePartsCommand([...selectionIds]));
```

This keeps undo coherent: a deletion by Delete key, by toolbar button, and by context menu are indistinguishable in the history. It also keeps the handler trivial to test — assert the command it produces, not the scene diff.

---

Back to [SKILL.md](../SKILL.md)
