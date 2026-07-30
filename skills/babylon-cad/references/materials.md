# Babylon.js Materials

## Table of Contents
- [PBRMaterial](#pbrmaterial)
- [StandardMaterial](#standardmaterial)
- [Material Common Properties](#material-common-properties)
- [Textures](#textures)
- [Environment & HDR](#environment--hdr)
- [Node Material](#node-material)
- [Shader Material](#shader-material)

## PBRMaterial

The recommended material for physically-based rendering. Two workflows:

### Metallic-Roughness Workflow (preferred)
```typescript
import { PBRMaterial } from "@babylonjs/core/Materials/PBR/pbrMaterial";
import { Color3 } from "@babylonjs/core/Maths/math.color";

const pbr = new PBRMaterial("pbr", scene);
pbr.albedoColor = new Color3(1.0, 0.766, 0.336);  // base color
pbr.metallic = 1.0;      // 0 = dielectric, 1 = metal
pbr.roughness = 0.4;     // 0 = mirror, 1 = matte

// Textures
pbr.albedoTexture = new Texture("albedo.png", scene);
pbr.metallicTexture = new Texture("metallic-roughness.png", scene);
// metallicTexture: blue channel = metallic, green channel = roughness
pbr.bumpTexture = new Texture("normal.png", scene);
pbr.ambientTexture = new Texture("ao.png", scene);

// Environment reflection (required for realistic PBR)
pbr.reflectionTexture = hdrTexture;
```

### Specular-Glossiness Workflow
```typescript
const pbr = new PBRMaterial("pbr", scene);
pbr.albedoColor = new Color3(1, 1, 1);
pbr.reflectivityColor = new Color3(0.9, 0.9, 0.9);  // specular color
pbr.microSurface = 0.8;  // glossiness (inverse of roughness)
```

### PBR Sub-features
```typescript
// Emissive
pbr.emissiveColor = new Color3(0, 0, 0);
pbr.emissiveTexture = new Texture("emissive.png", scene);
pbr.emissiveIntensity = 1.0;

// Clear coat
pbr.clearCoat.isEnabled = true;
pbr.clearCoat.intensity = 0.5;
pbr.clearCoat.roughness = 0.1;

// Sub-surface (refraction, translucency)
pbr.subSurface.isRefractionEnabled = true;
pbr.subSurface.indexOfRefraction = 1.5;
pbr.subSurface.tintColor = Color3.Teal();

// Anisotropy
pbr.anisotropy.isEnabled = true;
pbr.anisotropy.intensity = 1.0;
pbr.anisotropy.direction = new Vector2(1, 0);

// Sheen (fabric-like)
pbr.sheen.isEnabled = true;
pbr.sheen.intensity = 0.5;
pbr.sheen.color = new Color3(0.8, 0.1, 0.1);
```

## StandardMaterial

Simpler, non-physically-based. Uses diffuse/specular/emissive/ambient model.

```typescript
import { StandardMaterial } from "@babylonjs/core/Materials/standardMaterial";

const mat = new StandardMaterial("mat", scene);
mat.diffuseColor = new Color3(1, 0, 0);     // base color
mat.specularColor = new Color3(0.5, 0.5, 0.5); // highlight color
mat.emissiveColor = new Color3(0, 0, 0);    // self-illumination
mat.ambientColor = new Color3(0.1, 0.1, 0.1);

// Textures
mat.diffuseTexture = new Texture("texture.png", scene);
mat.specularTexture = new Texture("spec.png", scene);
mat.emissiveTexture = new Texture("emissive.png", scene);
mat.bumpTexture = new Texture("normal.png", scene);
mat.opacityTexture = new Texture("opacity.png", scene);

// Specular power (shininess)
mat.specularPower = 64;  // higher = tighter highlights

mesh.material = mat;
```

## Material Common Properties

```typescript
// Transparency
mat.alpha = 0.5;  // 0 = invisible, 1 = opaque
mat.transparencyMode = Material.MATERIAL_ALPHABLEND;
// MATERIAL_OPAQUE, MATERIAL_ALPHATEST, MATERIAL_ALPHABLEND, MATERIAL_ALPHATESTANDBLEND

// Texture alpha
mat.diffuseTexture.hasAlpha = true;
mat.useAlphaFromDiffuseTexture = true;

// Backface culling
mat.backFaceCulling = true;  // default: true
mat.sideOrientation = Material.ClockWiseSideOrientation;

// Wireframe
mat.wireframe = true;

// Z-offset (prevent z-fighting)
mat.zOffset = -1;

// Disable lighting
mat.disableLighting = true;

// Freeze for performance (no shader recompilation)
mat.freeze();
mat.unfreeze();
```

## Textures

```typescript
import { Texture } from "@babylonjs/core/Materials/Textures/texture";
import { CubeTexture } from "@babylonjs/core/Materials/Textures/cubeTexture";
import { DynamicTexture } from "@babylonjs/core/Materials/Textures/dynamicTexture";

// Standard texture
const tex = new Texture("path.png", scene);
tex.uScale = 2;  // tile horizontally
tex.vScale = 2;  // tile vertically
tex.uOffset = 0.5;
tex.vOffset = 0.5;
tex.wrapU = Texture.WRAP_ADDRESSMODE;  // WRAP, CLAMP, MIRROR
tex.wrapV = Texture.WRAP_ADDRESSMODE;

// Dynamic texture (canvas-based, draw with 2D context)
const dynTex = new DynamicTexture("dyn", { width: 512, height: 256 }, scene);
const ctx = dynTex.getContext();
ctx.fillStyle = "red";
ctx.fillRect(0, 0, 512, 256);
dynTex.update();

// Draw text on dynamic texture
dynTex.drawText("Hello", null, null, "bold 48px Arial", "white", "transparent", true);

// Cube texture (skybox/reflection)
const cubeTex = CubeTexture.CreateFromPrefilteredData("env.env", scene);
scene.environmentTexture = cubeTex;
```

## Environment & HDR

```typescript
import { CubeTexture } from "@babylonjs/core/Materials/Textures/cubeTexture";
import { HDRCubeTexture } from "@babylonjs/core/Materials/Textures/hdrCubeTexture";

// .env file (recommended - prefiltered, compact)
const envTex = CubeTexture.CreateFromPrefilteredData("environment.env", scene);
scene.environmentTexture = envTex;

// .hdr file (runtime processing, needs WebGL2)
const hdrTex = new HDRCubeTexture("environment.hdr", scene, 128);
scene.environmentTexture = hdrTex;

// Quick default environment
scene.createDefaultEnvironment();

// Skybox from environment texture
scene.createDefaultSkybox(envTex, true, 1000);
```

For tone mapping, exposure, and texture color spaces (the "model is black / washed out" half of the pipeline), see [rendering-color-management.md](rendering-color-management.md).

## Node Material

Visual shader graph compiled to GLSL/WGSL - no hand-written shader code. Which material to pick:

- **PBRMaterial / StandardMaterial**: default choice when a built-in lighting model is enough - least code, best tooling.
- **Node Material**: custom effects (gradients, masks, dissolves, UV tricks) that non-programmers should tweak - NME gives live preview and shareable snippets.
- **ShaderMaterial**: only when you need full manual control (custom attributes, non-standard pipelines); you own all shader code and lighting.

### Approach 1 (recommended): Node Material Editor + snippet

Build the graph visually at https://nme.babylonjs.com/, save it, then load by snippet id:

```typescript
import { NodeMaterial } from "@babylonjs/core/Materials/Node/nodeMaterial";
import { Color3 } from "@babylonjs/core/Maths/math.color";

// Pass the snippet id only (from the NME save dialog), NOT the full URL; append "#n" to pin a revision.
const nodeMat = await NodeMaterial.ParseFromSnippetAsync("2F999G", scene);
mesh.material = nodeMat;

// Or from a .json graph on your server: NodeMaterial.ParseFromFileAsync("myMat", "materials/myMat.json", scene)

// Runtime-tweak a named uniform input (give the block a name in NME first)
const tint = nodeMat.getInputBlockByPredicate((b) => b.name === "tintColor");
if (tint) tint.value = new Color3(1, 0, 0);
```

### Approach 2: build the graph in code

Verbose and harder to maintain - prefer Approach 1 unless the graph must be generated dynamically. Minimal complete example: grayscale gradient driven by world-space Y:

```typescript
import { NodeMaterial } from "@babylonjs/core/Materials/Node/nodeMaterial";
import { InputBlock } from "@babylonjs/core/Materials/Node/Blocks/Input/inputBlock";
import { TransformBlock } from "@babylonjs/core/Materials/Node/Blocks/transformBlock";
import { VertexOutputBlock } from "@babylonjs/core/Materials/Node/Blocks/Vertex/vertexOutputBlock";
import { FragmentOutputBlock } from "@babylonjs/core/Materials/Node/Blocks/Fragment/fragmentOutputBlock";
import { VectorSplitterBlock } from "@babylonjs/core/Materials/Node/Blocks/vectorSplitterBlock";
import { RemapBlock } from "@babylonjs/core/Materials/Node/Blocks/remapBlock";
import { NodeMaterialSystemValues } from "@babylonjs/core/Materials/Node/Enums/nodeMaterialSystemValues";
import { Vector2 } from "@babylonjs/core/Maths/math.vector";

const nodeMat = new NodeMaterial("yGradient", scene);

// Vertex: position -> world -> clip space
const positionInput = new InputBlock("position");
positionInput.setAsAttribute("position");
const worldInput = new InputBlock("world");
worldInput.setAsSystemValue(NodeMaterialSystemValues.World);
const worldPos = new TransformBlock("worldPos");
positionInput.connectTo(worldPos);  // auto-wires .output -> .vector
worldInput.connectTo(worldPos);     // auto-wires .output -> .transform
const viewProjection = new InputBlock("viewProjection");
viewProjection.setAsSystemValue(NodeMaterialSystemValues.ViewProjection);
const clipPos = new TransformBlock("clipPos");
worldPos.connectTo(clipPos);
viewProjection.connectTo(clipPos);
const vertexOutput = new VertexOutputBlock("vertexOutput");
clipPos.connectTo(vertexOutput);
nodeMat.addOutputNode(vertexOutput);

// Fragment: remap world Y into 0..1 grayscale
const splitter = new VectorSplitterBlock("splitter");
worldPos.xyz.connectTo(splitter.xyzIn);
const remap = new RemapBlock("remap");
remap.sourceRange = new Vector2(0, 10);  // world-Y range of your mesh
remap.targetRange = new Vector2(0, 1);
splitter.y.connectTo(remap.input);
const fragmentOutput = new FragmentOutputBlock("fragmentOutput");
remap.output.connectTo(fragmentOutput.rgb);
nodeMat.addOutputNode(fragmentOutput);
nodeMat.build(true);  // true = log generated shaders to console
mesh.material = nodeMat;
```

### Useful API

```typescript
import { NodeMaterialModes } from "@babylonjs/core/Materials/Node/Enums/nodeMaterialModes";

nodeMat.build();                        // compile graph into shaders; throws on error
nodeMat.getBlockByName("myBlock");      // any block by its name
nodeMat.getInputBlocks();               // all InputBlocks (uniform/attribute inputs)
nodeMat.attachedBlocks;                 // every block in the graph
nodeMat.mode = NodeMaterialModes.Material;  // default; also .PostProcess, .Particle, .ProceduralTexture
```

Node Material Editor (NME): https://nme.babylonjs.com/

## Shader Material

Custom GLSL/WGSL shaders:

```typescript
import { ShaderMaterial } from "@babylonjs/core/Materials/shaderMaterial";
import { Effect } from "@babylonjs/core/Materials/effect";

// Store shader code
Effect.ShadersStore["customVertexShader"] = `
  precision highp float;
  attribute vec3 position;
  uniform mat4 worldViewProjection;
  void main() {
    gl_Position = worldViewProjection * vec4(position, 1.0);
  }
`;
Effect.ShadersStore["customFragmentShader"] = `
  precision highp float;
  uniform vec3 color;
  void main() {
    gl_FragColor = vec4(color, 1.0);
  }
`;

const shaderMat = new ShaderMaterial("shader", scene, "custom", {
  attributes: ["position"],
  uniforms: ["worldViewProjection", "color"],
});
shaderMat.setColor3("color", new Color3(1, 0, 0));
```
