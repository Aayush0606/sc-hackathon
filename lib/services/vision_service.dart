import 'dart:typed_data';
import 'package:flutter_vision/flutter_vision.dart';

class VisionService {
  final FlutterVision vision = FlutterVision();

  Future<void> loadModel() async {
    await vision.loadYoloModel(
      labels: 'assets/labels/labels.txt',
      modelPath: 'assets/models/bestv8.tflite',
      modelVersion: "yolov8",
      numThreads: 2,
      useGpu: false,
    );
  }

  Future<List<Map<String, dynamic>>> runDetection({
    required Uint8List bytes,
    required int imageHeight,
    required int imageWidth,
  }) async {
    return await vision.yoloOnImage(
      bytesList: bytes,
      imageHeight: imageHeight,
      imageWidth: imageWidth,
      iouThreshold: 0.4,
      confThreshold: 0.4,
      classThreshold: 0.4,
    );
  }

  void dispose() {
    vision.closeYoloModel();
  }
}
