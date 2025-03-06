import 'dart:io';
import 'package:camera/camera.dart';
import 'package:camera_yolov5_app/constants/constants.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/camera_service.dart';
import '../services/vision_service.dart';
import '../services/image_processing_service.dart';
import '../models/cropped_image.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class DetectionScreen extends StatefulWidget {
  const DetectionScreen({Key? key}) : super(key: key);

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen> {
  final CameraService _cameraService = CameraService();
  final VisionService _visionService = VisionService();
  final ImageProcessingService _imageProcessingService =
      ImageProcessingService();

  File? _imageFile;
  List<Map<String, dynamic>> _yoloResults = [];
  List<CroppedImage> _croppedImages = [];
  bool _isLoaded = false;
  bool _isProcessing = false;
  int _imageHeight = 1;
  int _imageWidth = 1;
  List<String> _redImageNames = [];

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  @override
  void dispose() {
    _visionService.dispose();
    _cameraService.dispose();
    super.dispose();
  }

  Future<void> _initializeServices() async {
    await _cameraService.initialize();
    await _visionService.loadModel();
    setState(() {
      _isLoaded = true;
    });
  }

  Future<void> _captureImage() async {
    if (_imageFile != null) {
      setState(() {
        _imageFile = null;
        _croppedImages = [];
        _yoloResults = [];
        _redImageNames = [];
      });
      await Future.delayed(const Duration(milliseconds: 100));
      return;
    }

    if (_cameraService.controller == null ||
        !_cameraService.controller!.value.isInitialized) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final imageXFile = await _cameraService.captureImage();
      await _processImage(File(imageXFile.path));
    } catch (e) {
      debugPrint("Error capturing image: $e");
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final XFile? photo = await picker.pickImage(source: ImageSource.gallery);
    if (photo != null) {
      setState(() {
        _isProcessing = true;
      });
      await _processImage(File(photo.path));
    }
  }

  Future<void> _processImage(File imageFile) async {
    setState(() {
      _imageFile = imageFile;
      _yoloResults = [];
      _croppedImages = [];
      _redImageNames = [];
      _isProcessing = true;
    });

    final bytes = await imageFile.readAsBytes();
    final image = await decodeImageFromList(bytes);
    setState(() {
      _imageHeight = image.height;
      _imageWidth = image.width;
    });

    _yoloResults = await _visionService.runDetection(
      bytes: bytes,
      imageHeight: image.height,
      imageWidth: image.width,
    );

    if (_yoloResults.isNotEmpty) {
      _croppedImages = await _imageProcessingService.cropDetectedObjects(
          imageFile, _yoloResults);
    }

    await _uploadImages();

    setState(() {
      _isProcessing = false;
    });
  }

  List<Widget> _displayBoxes(Size previewSize) {
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
            borderRadius: BorderRadius.circular(10.0),
            border: Border.all(color: Colors.pink, width: 2.0),
          ),
        ),
      );
    }).toList();
  }

  Future<void> _uploadImages() async {
    if (_croppedImages.isEmpty) return;

    final url = Uri.parse(uploadEndpoint);
    final request = http.MultipartRequest("POST", url);

    for (final croppedImage in _croppedImages) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'files',
          croppedImage.data,
          filename: croppedImage.filename,
          contentType: MediaType('image', 'png'),
        ),
      );
    }

    try {
      final response = await request.send();
      final responseString = await response.stream.bytesToString();
      final responseData = json.decode(responseString);

      List<String> redImages = [];
      for (var result in responseData["results"]) {
        if (result["product"] == false) {
          redImages.add(result["filename"]);
        }
      }
      setState(() {
        _redImageNames = redImages;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text("Upload successful. Red images: ${redImages.join(', ')}")),
      );
    } catch (e) {
      debugPrint("Error during upload: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error during upload. Please try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    if (!_isLoaded ||
        _cameraService.controller == null ||
        !_cameraService.controller!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final double previewWidth = size.width;
    final double previewHeight =
        size.width * _cameraService.controller!.value.aspectRatio;
    final Size previewSize = Size(previewWidth, previewHeight);

    return Scaffold(
      appBar: AppBar(title: const Text("YOLO Detection")),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              width: previewWidth,
              height: previewHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _imageFile != null
                      ? Image.file(_imageFile!, fit: BoxFit.fill)
                      : CameraPreview(_cameraService.controller!),
                  if (_imageFile != null) ..._displayBoxes(previewSize),
                  if (_isProcessing)
                    Container(
                      color: Colors.black.withOpacity(0.3),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _captureImage,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text("Take Photo"),
                ),
                ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _pickImage,
                  icon: const Icon(Icons.photo_library),
                  label: const Text("Pick Image"),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
