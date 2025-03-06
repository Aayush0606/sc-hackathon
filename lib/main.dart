import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_vision/flutter_vision.dart';
import 'package:image/image.dart' as img; // For image processing (cropping)

late List<CameraDescription> cameras;

/// A model class to store cropped image data along with a filename.
class CroppedImage {
  final String filename;
  final Uint8List data;
  CroppedImage({required this.filename, required this.data});
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  cameras = await availableCameras();
  runApp(const MyApp());
}

/// Main Application Widget.
class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YOLO Detection',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomeScreen(),
    );
  }
}

/// HomeScreen: Captures an image, runs object detection, crops the detected objects,
/// displays the processed image with bounding boxes, and simulates an upload that marks
/// some images with a red border and others with a green border.
class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late FlutterVision _vision;
  CameraController? _cameraController;
  File? _imageFile;
  List<Map<String, dynamic>> _yoloResults = [];
  List<CroppedImage> _croppedImages = [];
  bool _isLoaded = false;
  bool _isProcessing = false;
  int _imageHeight = 1;
  int _imageWidth = 1;
  // List of image filenames that should be marked with a red border.
  List<String> _redImageNames = [];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _vision = FlutterVision();
    _loadYoloModel();
  }

  @override
  void dispose() {
    _vision.closeYoloModel();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    _cameraController = CameraController(cameras[0], ResolutionPreset.medium);
    await _cameraController!.initialize();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadYoloModel() async {
    try {
      await _vision.loadYoloModel(
        labels: 'assets/labels/labels.txt',
        modelPath:
            'assets/models/bestv8.tflite', // Use your preferred model here.
        modelVersion: "yolov8", // Change to "yolov5" if using a YOLOv5 model.
        numThreads: 2,
        useGpu: false,
      );
      setState(() {
        _isLoaded = true;
      });
    } catch (e) {
      debugPrint("Error loading model: $e");
    }
  }

  /// Capture an image. If an image is already displayed, clear it to show the live camera preview.
  Future<void> _captureImage() async {
    if (_imageFile != null) {
      // Clear the current image and related state.
      setState(() {
        _imageFile = null;
        _croppedImages = [];
        _yoloResults = [];
        _redImageNames = [];
      });
      // Allow time for the UI to update.
      await Future.delayed(const Duration(milliseconds: 100));
      return;
    }

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final XFile imageFile = await _cameraController!.takePicture();
      await _processImage(File(imageFile.path));
    } catch (e) {
      debugPrint("Error capturing image: $e");
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? photo = await picker.pickImage(source: ImageSource.gallery);

    if (photo != null) {
      setState(() {
        _isProcessing = true;
      });

      await _processImage(File(photo.path));

      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _processImage(File imageFile) async {
    setState(() {
      _imageFile = imageFile;
      _yoloResults = [];
      _croppedImages = [];
      _redImageNames = [];
    });

    // Run YOLO detection on the image.
    await _runDetection(imageFile);

    // Crop the detected objects.
    if (_yoloResults.isNotEmpty) {
      await _cropDetectedObjects(imageFile);
    }
  }

  Future<void> _runDetection(File imageFile) async {
    Uint8List bytes = await imageFile.readAsBytes();
    final image = await decodeImageFromList(bytes);

    setState(() {
      _imageHeight = image.height;
      _imageWidth = image.width;
    });

    final result = await _vision.yoloOnImage(
      bytesList: bytes,
      imageHeight: image.height,
      imageWidth: image.width,
      iouThreshold: 0.4,
      confThreshold: 0.4,
      classThreshold: 0.4,
    );

    if (result.isNotEmpty) {
      setState(() {
        _yoloResults = result;
      });
    }
  }

  /// Crop the detected objects and return a list of CroppedImage objects.
  Future<void> _cropDetectedObjects(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final decodedImage = img.decodeImage(bytes);
    if (decodedImage == null) return;

    List<CroppedImage> croppedImages = [];

    // Use index so each image gets a filename like "image0.png", "image1.png", etc.
    for (int i = 0; i < _yoloResults.length; i++) {
      final detection = _yoloResults[i];
      List<dynamic> box = detection["box"];
      int x = box[0].toInt();
      int y = box[1].toInt();
      int width = (box[2] - box[0]).toInt();
      int height = (box[3] - box[1]).toInt();

      // Ensure the crop region stays within image boundaries.
      if (x < 0) x = 0;
      if (y < 0) y = 0;
      if (x + width > decodedImage.width) width = decodedImage.width - x;
      if (y + height > decodedImage.height) height = decodedImage.height - y;

      final cropped = img.copyCrop(decodedImage, x, y, width, height);
      final croppedBytes = Uint8List.fromList(img.encodePng(cropped));
      croppedImages
          .add(CroppedImage(filename: "image$i.png", data: croppedBytes));
    }

    setState(() {
      _croppedImages = croppedImages;
    });
  }

  /// Calculate and return positioned bounding boxes relative to the preview container.
  List<Widget> _displayBoxesAroundRecognizedObjects(Size previewSize) {
    if (_yoloResults.isEmpty) return [];

    double factorX = previewSize.width / _imageWidth;
    double factorY = previewSize.height / _imageHeight;

    return _yoloResults.map((result) {
      List<dynamic> box = result["box"];
      double left = box[0] * factorX;
      double top = box[1] * factorY;
      double width = (box[2] - box[0]) * factorX;
      double height = (box[3] - box[1]) * factorY;

      return Positioned(
        left: left,
        top: top,
        width: width,
        height: height,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(10.0)),
            border: Border.all(color: Colors.pink, width: 2.0),
          ),
        ),
      );
    }).toList();
  }

  /// Simulate an API call to upload images.
  /// In this fake response, images at odd indices are marked for a red border.
  Future<void> _uploadImages() async {
    if (_croppedImages.isEmpty) return;

    setState(() {
      _isProcessing = true;
    });

    // Simulate a network delay.
    await Future.delayed(const Duration(seconds: 2));

    List<String> fakeRedImages = [];
    for (int i = 0; i < _croppedImages.length; i++) {
      if (i % 2 == 1) {
        fakeRedImages.add("image$i.png");
      }
    }

    setState(() {
      _redImageNames = fakeRedImages;
      _isProcessing = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text("Upload simulated. Red images: ${fakeRedImages.join(', ')}")));
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;

    if (!_isLoaded ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Define the preview container dimensions based on screen width and camera aspect ratio.
    final double previewWidth = size.width;
    final double previewHeight =
        size.width * _cameraController!.value.aspectRatio;
    final Size previewSize = Size(previewWidth, previewHeight);

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Preview area: shows the captured image with bounding boxes or live camera feed.
            Container(
              width: previewWidth,
              height: previewHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _imageFile != null
                      ? Image.file(_imageFile!, fit: BoxFit.fill)
                      : CameraPreview(_cameraController!),
                  if (_imageFile != null)
                    ..._displayBoxesAroundRecognizedObjects(previewSize),
                  if (_isProcessing)
                    Container(
                      color: Colors.black.withOpacity(0.3),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Display cropped images in a horizontal list with colored borders.
            if (_croppedImages.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      "Detected Objects",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 150,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _croppedImages.length,
                      itemBuilder: (context, index) {
                        final croppedImage = _croppedImages[index];
                        // Determine border color: red if the filename is in the fake API response; otherwise, green.
                        final Color borderColor =
                            _redImageNames.contains(croppedImage.filename)
                                ? Colors.red
                                : Colors.green;
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8.0),
                          decoration: BoxDecoration(
                            border: Border.all(color: borderColor, width: 3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(croppedImage.data,
                                fit: BoxFit.cover),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 20),
            // Action buttons: Take Photo, Pick Image, and Upload Cropped Images.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _captureImage,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text("Take Photo"),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _pickImage,
                  icon: const Icon(Icons.photo_library),
                  label: const Text("Pick Image"),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_croppedImages.isNotEmpty)
              ElevatedButton.icon(
                onPressed: _isProcessing ? null : _uploadImages,
                icon: const Icon(Icons.cloud_upload),
                label: const Text("Upload Images"),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
