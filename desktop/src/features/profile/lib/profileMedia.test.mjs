import assert from "node:assert/strict";
import { test } from "node:test";
import { validateProfileModel } from "./profileMedia.ts";

function glb(document) {
  const json = new TextEncoder().encode(JSON.stringify(document));
  const length = Math.ceil(json.length / 4) * 4;
  const bytes = new Uint8Array(20 + length).fill(32);
  const view = new DataView(bytes.buffer);
  [0x46546c67, 2, bytes.length, length, 0x4e4f534a].forEach((v, i) => view.setUint32(i * 4, v, true));
  bytes.set(json, 20);
  return bytes;
}
const model = { asset: { version: "2.0" }, meshes: [{ primitives: [] }] };
test("profile models accept embedded GLB resources", () => {
  assert.doesNotThrow(() => validateProfileModel(glb({ ...model, images: [{ uri: "data:image/png;base64,aA==" }] })));
});
test("profile models reject external resources and decoder downloads", () => {
  for (const document of [
    { ...model, buffers: [{ uri: "https://example.com/model.bin" }] },
    { ...model, images: [{ uri: "../texture.png" }] },
    { ...model, extensionsUsed: ["KHR_draco_mesh_compression"] },
    { ...model, extensionsRequired: ["KHR_draco_mesh_compression"] },
  ]) assert.throws(() => validateProfileModel(glb(document)));
});
test("profile models reject corrupt headers and incomplete payloads", () => {
  const bytes = glb(model);
  bytes[0] = 0;
  assert.throws(() => validateProfileModel(bytes));
  assert.throws(() => validateProfileModel(glb(model).subarray(0, 20)));
  assert.throws(() => validateProfileModel(new Uint8Array(20 * 1024 * 1024 + 1)));
});
