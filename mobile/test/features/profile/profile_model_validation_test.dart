import 'dart:convert';
import 'dart:typed_data';

import 'package:buzz/features/profile/profile_model_validation.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List model(Map<String, dynamic> metadata) {
  final json = utf8.encode(jsonEncode(metadata));
  final size = (json.length + 3) ~/ 4 * 4;
  final bytes = Uint8List(20 + size);
  final header = ByteData.sublistView(bytes);
  header.setUint32(0, 0x46546c67, Endian.little);
  header.setUint32(4, 2, Endian.little);
  header.setUint32(8, bytes.length, Endian.little);
  header.setUint32(12, size, Endian.little);
  header.setUint32(16, 0x4e4f534a, Endian.little);
  bytes.fillRange(20, bytes.length, 32);
  bytes.setRange(20, 20 + json.length, json);
  return bytes;
}

void main() {
  final metadata = <String, dynamic>{
    'asset': {'version': '2.0'},
    'meshes': [{}],
  };
  test('accepts a self-contained model', () {
    expect(() => validateProfileModel(model(metadata)), returnsNormally);
  });
  test('rejects external resources and decoder extensions', () {
    for (final patch in [
      {
        'buffers': [
          {'uri': 'https://example.com/model.bin'},
        ],
      },
      {
        'images': [
          {'uri': 'texture.png'},
        ],
      },
      {
        'extensionsRequired': ['KHR_draco_mesh_compression'],
      },
    ]) {
      expect(
        () => validateProfileModel(model({...metadata, ...patch})),
        throwsFormatException,
      );
    }
  });
  test('rejects incomplete payloads', () {
    final bytes = model(metadata);
    expect(
      () => validateProfileModel(bytes.sublist(0, bytes.length - 1)),
      throwsFormatException,
    );
  });
}
