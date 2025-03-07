import 'package:camera/camera.dart';

class CameraService {
  late List<CameraDescription> cameras;
  CameraController? controller;

  Future<void> initialize() async {
    cameras = await availableCameras();
    controller = CameraController(cameras[0], ResolutionPreset.ultraHigh);
    await controller!.initialize();
  }

  Future<XFile> captureImage() async {
    if (controller != null && controller!.value.isInitialized) {
      return await controller!.takePicture();
    }
    throw Exception("Camera not initialized");
  }

  void dispose() {
    controller?.dispose();
  }
}
