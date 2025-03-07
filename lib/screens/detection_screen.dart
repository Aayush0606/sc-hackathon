import 'dart:io';
import 'package:camera/camera.dart';
import 'package:team_rocket/constants/constants.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/camera_service.dart';
import '../services/vision_service.dart';
import '../services/image_processing_service.dart';
import '../models/cropped_image.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

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
  Map<String, dynamic> _uploadResults = {};

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
        _uploadResults = {};
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
      _uploadResults = {};
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
        _uploadResults[result["filename"]] = result;
        if (result["product"] == false) {
          redImages.add(result["filename"]);
        }
      }
      setState(() {
        _redImageNames = redImages;
      });
    } catch (e) {
      debugPrint("Error during upload: $e");
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text("Upload Error"),
            content: Text(e.toString()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("OK"),
              ),
            ],
          );
        },
      );
      // ScaffoldMessenger.of(context).showSnackBar(
      //   const SnackBar(content: Text("Error during upload. Please try again.")),
      // );
    }
  }

  void _showSkuDialog(String filename) {
    final result = _uploadResults[filename];
    if (result == null || result["product"] != true) return;

    List<dynamic> matchedSku = result["matched_sku"] ?? [];
    List<String> skuCodes = [];
    for (var sku in matchedSku) {
      skuCodes.add(sku["sku_code"].toString());
    }

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Matched SKU Codes",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const Divider(color: Colors.grey, thickness: 1.5),
                const SizedBox(height: 10),
                skuCodes.isNotEmpty
                    ? Column(
                        children: skuCodes
                            .map((code) => ListTile(
                                  leading: Icon(Icons.label,
                                      color: Colors.blueAccent),
                                  title: Text(
                                    code,
                                    style: TextStyle(
                                        fontSize: 16, color: Colors.black87),
                                  ),
                                ))
                            .toList(),
                      )
                    : Text("No SKU codes available.",
                        style: TextStyle(fontSize: 16, color: Colors.black54)),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                  child: Text("Close", style: TextStyle(fontSize: 16)),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAnalysisBottomSheet() {
    int total = _uploadResults.length;
    int success = _uploadResults.values
        .where((result) => result["product"] == true)
        .length;
    int failure = _uploadResults.values
        .where((result) => result["product"] == false)
        .length;
    double successPercentage = total > 0 ? (success / total * 100) : 0.0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.55,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 10,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          colors: [Colors.blueAccent, Colors.lightBlueAccent],
                        ).createShader(bounds),
                        child: Text(
                          "Upload Analysis",
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      SizedBox(height: 20),
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              spreadRadius: 0,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  width: 140,
                                  height: 140,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      PieChart(
                                        PieChartData(
                                          borderData: FlBorderData(show: false),
                                          sectionsSpace: 2,
                                          centerSpaceRadius: 30,
                                          sections: [
                                            PieChartSectionData(
                                              color: Color(0xFF4CAF50),
                                              value: success.toDouble(),
                                              radius: 45,
                                              showTitle: false,
                                            ),
                                            PieChartSectionData(
                                              color: Color(0xFFE53935),
                                              value: failure.toDouble(),
                                              radius: 40,
                                              showTitle: false,
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            "${successPercentage.toStringAsFixed(1)}%",
                                            style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.black87,
                                            ),
                                          ),
                                          Text(
                                            "Success",
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.black54,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildStatItem(
                                          Icons.image,
                                          "Total Images",
                                          "$total",
                                          Colors.blueAccent),
                                      SizedBox(height: 12),
                                      _buildStatItem(
                                          Icons.check_circle_outline,
                                          "Success",
                                          "$success",
                                          Color(0xFF4CAF50)),
                                      SizedBox(height: 12),
                                      _buildStatItem(
                                          Icons.error_outline,
                                          "Failed",
                                          "$failure",
                                          Color(0xFFE53935)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(Icons.close, color: Colors.white),
                          label: Text(
                            "Close",
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            padding: EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                      SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatItem(
      IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.black54,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCoolLoader() {
    return Center(
      child: SpinKitFadingCircle(
        color: Colors.white,
        size: 50.0,
      ),
    );
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
      appBar: AppBar(
        title: const Text("SKU Detection"),
      ),
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
                      child: _buildCoolLoader(),
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
                        final bool isFailure =
                            _redImageNames.contains(croppedImage.filename);
                        final Color borderColor =
                            isFailure ? Colors.red : Colors.green;
                        Widget imageWidget = Container(
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
                        if (_uploadResults[croppedImage.filename]?["product"] ==
                            true) {
                          return GestureDetector(
                            onTap: () => _showSkuDialog(croppedImage.filename),
                            child: imageWidget,
                          );
                        }
                        return imageWidget;
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
            Center(
              child: ElevatedButton.icon(
                onPressed:
                    _uploadResults.isEmpty ? null : _showAnalysisBottomSheet,
                icon: const Icon(Icons.analytics),
                label: const Text("Analysis"),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
