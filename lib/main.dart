import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_pytorch/flutter_pytorch.dart';
import 'package:flutter_pytorch/pigeon.dart';
import 'package:image/image.dart' as img; // For image processing (cropping)

void main() {
  runApp(const MyApp());
}

/// Main Application Widget
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YOLOv5 Detection',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomeScreen(),
    );
  }
}

/// HomeScreen: Captures an image, runs object detection, crops out each detected object,
/// and displays both the processed image with bounding boxes and the cropped detections.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late ModelObjectDetection _objectModel;
  File? _image;
  final ImagePicker _picker = ImagePicker();
  List<ResultObjectDetection?> objDetect = [];
  List<Uint8List> _croppedImages = [];
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    loadModel();
  }

  /// Load the YOLOv5 model from assets.
  Future<void> loadModel() async {
    String modelPath = "assets/models/yolov5s.torchscript";
    try {
      _objectModel = await FlutterPytorch.loadObjectDetectionModel(
        modelPath,
        80, // Number of classes (adjust if necessary)
        640, // Input width
        640, // Input height
        labelPath: "assets/labels/labels.txt",
      );
    } catch (e) {
      if (e is PlatformException) {
        debugPrint("PlatformException: $e");
      } else {
        debugPrint("Error loading model: $e");
      }
    }
  }

  /// Crop each detected object from the image using the detection's rect properties.
  Future<List<Uint8List>> cropDetectedObjects(
      File imageFile, List<ResultObjectDetection?> detections) async {
    // Read the image file as bytes and decode it.
    final bytes = await imageFile.readAsBytes();
    final decodedImage = img.decodeImage(bytes);
    if (decodedImage == null) return [];

    List<Uint8List> croppedImages = [];
    for (final detection in detections) {
      if (detection == null) continue;

      // Multiply normalized coordinates by the image dimensions.
      int x = (detection.rect.left * decodedImage.width).toInt();
      int y = (detection.rect.top * decodedImage.height).toInt();
      int width = (detection.rect.width * decodedImage.width).toInt();
      int height = (detection.rect.height * decodedImage.height).toInt();

      // Ensure the crop region stays within the image boundaries.
      if (x < 0) x = 0;
      if (y < 0) y = 0;
      if (x + width > decodedImage.width) width = decodedImage.width - x;
      if (y + height > decodedImage.height) height = decodedImage.height - y;

      // Crop the image based on the bounding box.
      final cropped = img.copyCrop(decodedImage, x, y, width, height);
      // Convert the cropped image to PNG bytes.
      final croppedBytes = Uint8List.fromList(img.encodePng(cropped));
      croppedImages.add(croppedBytes);
    }
    return croppedImages;
  }

  /// Capture an image from the camera, run detection, and crop out the detected objects.
  Future<void> runObjectDetection() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (image == null) return;

    setState(() {
      _isProcessing = true;
    });

    File imgFile = File(image.path);

    // Run inference on the captured image.
    List<ResultObjectDetection?> detections =
        await _objectModel.getImagePrediction(
      await imgFile.readAsBytes(),
      minimumScore: 0.1,
      IOUThershold: 0.3,
    );

    // Crop the detected objects from the image.
    List<Uint8List> cropped = await cropDetectedObjects(imgFile, detections);

    setState(() {
      _image = imgFile;
      objDetect = detections;
      _croppedImages = cropped;
      _isProcessing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("YOLOv5 Detection"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Display the processed image with bounding boxes.
            _image != null && objDetect.isNotEmpty
                ? SizedBox(
                    height: 300,
                    width: 300,
                    child: _objectModel.renderBoxesOnImage(_image!, objDetect),
                  )
                : const Text("No image processed yet."),
            const SizedBox(height: 20),
            // Display each cropped detected object.
            _croppedImages.isNotEmpty
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Detected Objects:",
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _croppedImages.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Image.memory(_croppedImages[index]),
                          );
                        },
                      )
                    ],
                  )
                : const SizedBox(),
            const SizedBox(height: 20),
            // Button to capture image and run detection.
            _isProcessing
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: runObjectDetection,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(150, 50),
                    ),
                    child: const Icon(Icons.camera_alt),
                  ),
          ],
        ),
      ),
    );
  }
}
