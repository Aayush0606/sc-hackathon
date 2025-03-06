import 'dart:typed_data';

class CroppedImage {
  final String filename;
  final Uint8List data;

  CroppedImage({required this.filename, required this.data});
}
