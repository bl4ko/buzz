import 'dart:convert';
import 'dart:typed_data';

void validateProfileModel(Uint8List bytes) {
  if (bytes.length < 20 || bytes.length > 20 * 1024 * 1024) {
    throw const FormatException('Choose a GLB model up to 20 MB.');
  }
  final data = ByteData.sublistView(bytes);
  if (data.getUint32(0, Endian.little) != 0x46546c67 ||
      data.getUint32(4, Endian.little) != 2 ||
      data.getUint32(8, Endian.little) != bytes.length ||
      data.getUint32(16, Endian.little) != 0x4e4f534a) {
    throw const FormatException('Choose a valid GLB 2.0 model.');
  }
  final length = data.getUint32(12, Endian.little);
  if (length % 4 != 0 || length > bytes.length - 20) {
    throw const FormatException('The GLB model is incomplete.');
  }
  final document =
      jsonDecode(utf8.decode(bytes.sublist(20, 20 + length)))
          as Map<String, dynamic>;
  if (document['asset']?['version'] != '2.0' ||
      document['meshes'] is! List ||
      (document['meshes'] as List).isEmpty) {
    throw const FormatException('Choose a GLB model with a mesh.');
  }
  if ([
    ...(document['extensionsUsed'] as List? ?? []),
    ...(document['extensionsRequired'] as List? ?? []),
  ].any(
    (name) => [
      'KHR_draco_mesh_compression',
      'EXT_meshopt_compression',
      'KHR_texture_basisu',
    ].contains(name),
  )) {
    throw const FormatException(
      'Export the GLB without mesh or texture compression.',
    );
  }
  for (final item in [
    ...(document['buffers'] as List? ?? []),
    ...(document['images'] as List? ?? []),
  ]) {
    final uri = (item as Map)['uri'];
    if (uri != null && (uri is! String || !uri.startsWith('data:'))) {
      throw const FormatException('Use embedded textures and buffers.');
    }
  }
}
