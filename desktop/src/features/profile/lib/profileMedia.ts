export function validateProfileModel(bytes: Uint8Array): void {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (
    bytes.length < 20 ||
    bytes.length > 50 * 1024 * 1024 ||
    view.getUint32(0, true) !== 0x46546c67 ||
    view.getUint32(4, true) !== 2 ||
    view.getUint32(8, true) !== bytes.length ||
    view.getUint32(16, true) !== 0x4e4f534a
  ) {
    throw new Error("Choose a valid GLB 2.0 model (up to 50 MB).");
  }
  const length = view.getUint32(12, true);
  if (length % 4 !== 0 || length > bytes.length - 20)
    throw new Error("The GLB model is incomplete.");
  const document = JSON.parse(
    new TextDecoder().decode(bytes.subarray(20, 20 + length)),
  );
  if (
    document.asset?.version !== "2.0" ||
    !Array.isArray(document.meshes) ||
    !document.meshes.length
  )
    throw new Error("Choose a GLB model with a mesh.");
  if (
    [
      ...(document.extensionsUsed ?? []),
      ...(document.extensionsRequired ?? []),
    ].some((name: string) =>
      [
        "KHR_draco_mesh_compression",
        "EXT_meshopt_compression",
        "KHR_texture_basisu",
      ].includes(name),
    )
  )
    throw new Error("Export the GLB without mesh or texture compression.");
  for (const item of [
    ...(document.buffers ?? []),
    ...(document.images ?? []),
  ]) {
    if (
      item.uri !== undefined &&
      (typeof item.uri !== "string" || !item.uri.startsWith("data:"))
    )
      throw new Error("Use a GLB model with embedded textures and buffers.");
  }
}
