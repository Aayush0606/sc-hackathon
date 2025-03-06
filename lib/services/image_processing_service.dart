import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../models/cropped_image.dart';

class ImageProcessingService {
  Future<List<CroppedImage>> cropDetectedObjects(
    File imageFile,
    List<Map<String, dynamic>> yoloResults,
  ) async {
    final bytes = await imageFile.readAsBytes();
    final decodedImage = img.decodeImage(bytes);
    if (decodedImage == null) return [];

    List<CroppedImage> croppedImages = [];
    for (int i = 0; i < yoloResults.length; i++) {
      final detection = yoloResults[i];
      List<dynamic> box = detection["box"];
      int x = box[0].toInt();
      int y = box[1].toInt();
      int width = (box[2] - box[0]).toInt();
      int height = (box[3] - box[1]).toInt();

      if (x < 0) x = 0;
      if (y < 0) y = 0;
      if (x + width > decodedImage.width) width = decodedImage.width - x;
      if (y + height > decodedImage.height) height = decodedImage.height - y;

      final cropped = img.copyCrop(decodedImage, x, y, width, height);
      final croppedBytes = Uint8List.fromList(img.encodePng(cropped));
      croppedImages.add(CroppedImage(filename: "image$i.png", data: croppedBytes));
    }
    return croppedImages;
  }
}
