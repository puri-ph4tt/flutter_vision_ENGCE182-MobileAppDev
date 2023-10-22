import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_vision/flutter_vision.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_tts/flutter_tts.dart';

//{ none, imagev5, imagev8, imagev8seg, frame, tesseract, vision }

late List<CameraDescription> cameras;
main() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  runApp(
    const MaterialApp(
      home: MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late FlutterVision vision;
  //Options option = Options.none;
  int _selectedIndex = 0;
  List<Widget> _widgetOptions = [];

  @override
  void initState() {
    super.initState();
    vision = FlutterVision();
    _widgetOptions = [
      const Center(child: Text("Choose Task")),
      TesseractImage(vision: vision),
      YoloImageV5(vision: vision),
      YoloImageV8Seg(vision: vision),
    ];
  }

  @override
  void dispose() async {
    super.dispose();
    await vision.closeTesseractModel();
    await vision.closeYoloModel();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter Vision'),
      ),
      body: _widgetOptions.elementAt(_selectedIndex),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.text_snippet_outlined),
            label: 'Tesseract',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.camera),
            label: 'YoloV5',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.camera),
            label: 'YoloV8seg',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blue[800],
        onTap: _onItemTapped,
      ),
    );
  }
}

// -------------------------------------------YoloImageV5-------------------------------------------
class YoloImageV5 extends StatefulWidget {
  final FlutterVision vision;
  const YoloImageV5({Key? key, required this.vision}) : super(key: key);

  @override
  State<YoloImageV5> createState() => _YoloImageV5State();
}

class _YoloImageV5State extends State<YoloImageV5> {
  late List<Map<String, dynamic>> yoloResults;
  File? imageFile;
  int imageHeight = 1;
  int imageWidth = 1;
  bool isLoaded = false;
  List<String> resultTags = [];
  List<String> positionX = [];
  List<String> positionY = [];
  FlutterTts flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    loadYoloModel().then((value) {
      setState(() {
        yoloResults = [];
        isLoaded = true;
      });
    });
  }

  @override
  void dispose() async {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    if (!isLoaded) {
      return const Scaffold(
        body: Center(
          child: Text("Model not loaded, waiting for it"),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        imageFile != null ? Image.file(imageFile!) : const SizedBox(),
        Align(
          alignment: Alignment.bottomCenter,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Display the object counts
              Column(
                children: resultTags
                    .toSet()
                    .map((tag) {
                      int count = resultTags.where((t) => t == tag).length;
                      List<String> tags = resultTags.where((t) => t == tag).toList();
                      return Card(
                        child: ListTile(
                          title: Text(
                            '$tag ($count)',
                            style: const TextStyle(fontSize: 20),
                          ),
                        ),
                      );
                    })
                    .toList(),
              ),

              //  -------------------------forDebug-------------------------
              //Text('X: ${positionX.join(', ')}', style: const TextStyle(fontSize: 16)),
              //Text('Y: ${positionY.join(', ')}', style: const TextStyle(fontSize: 16)),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: pickImage,
                    child: const Text("Pick image"),
                  ),
                  ElevatedButton(
                    onPressed: yoloOnImage,
                    child: const Text("Detect"),
                  )
                ],
              ),
            ],
          ),
        ),
        ...displayBoxesAroundRecognizedObjects(size),
      ],
    );
  }

  // TTS
  Future<void> speakRecognizedObjects(List<Map<String, dynamic>> objects, int imageWidth) async {
  await flutterTts.setLanguage("en-US"); // Set the desired language
  await flutterTts.setPitch(1.0); // Adjust pitch as needed

  // Sort objects by x-position
  objects.sort((a, b) {
    final double xPosA = (a['box'][0] as double);
    final double xPosB = (b['box'][0] as double);
    return xPosA.compareTo(xPosB);
  });

  for (var object in objects) {
    final String tag = object['tag'] ?? 'Unknown'; // Get the "tag" property or use 'Unknown' if it's null
    final double xPos = (object['box'][0] as double);
    String positionDescription = '';

    // Calculate the center of the image
    final double xPosPercentage = (xPos / imageWidth) * 100.0;

    // Calculate the relative position
    if (xPosPercentage < 40.0) {
      positionDescription = 'on the left';
    } else if (xPosPercentage >= 40.0 && xPosPercentage <= 60.0) {
      positionDescription = 'in the front';
    } else {
      positionDescription = 'on the right';
    }

    final String fullDescription = '$tag $positionDescription';
    await flutterTts.speak(fullDescription);
    await Future.delayed(Duration(seconds: 2)); // Wait for a moment before speaking the next object
  }
}



  String getObjectCounts(List<String> tags) {
    Map<String, int?> objectCounts = {}; // Make the value type nullable

    for (var tag in tags) {
      objectCounts[tag] = (objectCounts[tag] ?? 0) + 1; // Use null-aware operator and default to 0
    }

    List<String> formattedCounts = objectCounts.entries
        .map((entry) => '${entry.key} (${entry.value ?? 0})')
        .toList();

    return formattedCounts.join('\n');
  }

  Future<void> loadYoloModel() async {
    await widget.vision.loadYoloModel(
        labels: 'assets/labels.txt',
        modelPath: 'assets/yolov5n.tflite',
        modelVersion: "yolov5",
        quantization: false,
        numThreads: 2,
        useGpu: true);
    setState(() {
      isLoaded = true;
    });
  }

  Future<void> pickImage() async {
    final ImagePicker picker = ImagePicker();
    // Capture a photo
    final XFile? photo = await picker.pickImage(source: ImageSource.gallery);
    if (photo != null) {
      setState(() {
        imageFile = File(photo.path);
      });
    }
  }

  yoloOnImage() async {
    yoloResults.clear();
    Uint8List byte = await imageFile!.readAsBytes();
    final image = await decodeImageFromList(byte);
    imageHeight = image.height;
    imageWidth = image.width;
    final result = await widget.vision.yoloOnImage(
        bytesList: byte,
        imageHeight: image.height,
        imageWidth: image.width,
        iouThreshold: 0.8,
        confThreshold: 0.4,
        classThreshold: 0.5);
    if (result.isNotEmpty) {
      setState(() {
        yoloResults = result;
        resultTags = result.map((item) => "${item['tag']}").toList();
        positionX = result
            .map((item) => double.parse("${item['box'][0]}").toStringAsFixed(2))
            .toList();
        positionY = result
            .map((item) => double.parse("${item['box'][1]}").toStringAsFixed(2))
            .toList();
      });
      speakRecognizedObjects(yoloResults, imageWidth);
    }
  }

  List<Widget> displayBoxesAroundRecognizedObjects(Size screen) {
    if (yoloResults.isEmpty) return [];

    double factorX = screen.width / (imageWidth);
    double imgRatio = imageWidth / imageHeight;
    double newWidth = imageWidth * factorX;
    double newHeight = newWidth / imgRatio;
    double factorY = newHeight / (imageHeight);

    double pady = (screen.height - newHeight) / 2.66;

    Color colorPick = const Color.fromARGB(255, 50, 233, 30);
    return yoloResults.map((result) {
      return Positioned(
        left: result["box"][0] * factorX,
        top: result["box"][1] * factorY + pady,
        width: (result["box"][2] - result["box"][0]) * factorX,
        height: (result["box"][3] - result["box"][1]) * factorY,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(10.0)),
            border: Border.all(color: Colors.pink, width: 2.0),
          ),
          child: Text(
            "${result['tag']} ${(result['box'][4] * 100).toStringAsFixed(0)}%",
            style: TextStyle(
              background: Paint()..color = colorPick,
              color: Colors.white,
              fontSize: 18.0,
            ),
          ),
        ),
      );
    }).toList();
  }
}

// -------------------------------------------YoloImageV8Seg-------------------------------------------
class YoloImageV8Seg extends StatefulWidget {
  final FlutterVision vision;
  const YoloImageV8Seg({Key? key, required this.vision}) : super(key: key);

  @override
  State<YoloImageV8Seg> createState() => _YoloImageV8SegState();
}

class _YoloImageV8SegState extends State<YoloImageV8Seg> {
  late List<Map<String, dynamic>> yoloResults;
  File? imageFile;
  int imageHeight = 1;
  int imageWidth = 1;
  bool isLoaded = false;

  @override
  void initState() {
    super.initState();
    loadYoloModel().then((value) {
      setState(() {
        yoloResults = [];
        isLoaded = true;
      });
    });
  }

  @override
  void dispose() async {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    if (!isLoaded) {
      return const Scaffold(
        body: Center(
          child: Text("Model not loaded, waiting for it"),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        imageFile != null ? Image.file(imageFile!) : const SizedBox(),
        Align(
          alignment: Alignment.bottomCenter,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: pickImage,
                child: const Text("Pick image"),
              ),
              ElevatedButton(
                onPressed: yoloOnImage,
                child: const Text("Detect"),
              )
            ],
          ),
        ),
        ...displayBoxesAroundRecognizedObjects(size),
      ],
    );
  }

  Future<void> loadYoloModel() async {
    await widget.vision.loadYoloModel(
        labels: 'assets/labels.txt',
        modelPath: 'assets/yolov8n-seg.tflite',
        modelVersion: "yolov8seg",
        quantization: false,
        numThreads: 2,
        useGpu: true);
    setState(() {
      isLoaded = true;
    });
  }

  Future<void> pickImage() async {
    final ImagePicker picker = ImagePicker();
    // Capture a photo
    final XFile? photo = await picker.pickImage(source: ImageSource.gallery);
    if (photo != null) {
      setState(() {
        imageFile = File(photo.path);
      });
    }
  }

  yoloOnImage() async {
    yoloResults.clear();
    Uint8List byte = await imageFile!.readAsBytes();
    final image = await decodeImageFromList(byte);
    imageHeight = image.height;
    imageWidth = image.width;
    final result = await widget.vision.yoloOnImage(
        bytesList: byte,
        imageHeight: image.height,
        imageWidth: image.width,
        iouThreshold: 0.8,
        confThreshold: 0.4,
        classThreshold: 0.5);
    if (result.isNotEmpty) {
      setState(() {
        yoloResults = result;
      });
    }
  }

  List<Widget> displayBoxesAroundRecognizedObjects(Size screen) {
    if (yoloResults.isEmpty) return [];

    double factorX = screen.width / (imageWidth);
    double imgRatio = imageWidth / imageHeight;
    double newWidth = imageWidth * factorX;
    double newHeight = newWidth / imgRatio;
    double factorY = newHeight / (imageHeight);

    double pady = (screen.height - newHeight) / 2.66;

    Color colorPick = const Color.fromARGB(255, 50, 233, 30);
    return yoloResults.map((result) {
      return Stack(children: [
        Positioned(
          left: result["box"][0] * factorX,
          top: result["box"][1] * factorY + pady,
          width: (result["box"][2] - result["box"][0]) * factorX,
          height: (result["box"][3] - result["box"][1]) * factorY,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(Radius.circular(10.0)),
              border: Border.all(color: Colors.pink, width: 2.0),
            ),
            child: Text(
              "${result['tag']} ${(result['box'][4] * 100).toStringAsFixed(0)}%",
              style: TextStyle(
                background: Paint()..color = colorPick,
                color: Colors.white,
                fontSize: 18.0,
              ),
            ),
          ),
        ),
        Positioned(
            left: result["box"][0] * factorX,
            top: result["box"][1] * factorY + pady,
            width: (result["box"][2] - result["box"][0]) * factorX,
            height: (result["box"][3] - result["box"][1]) * factorY,
            child: CustomPaint(
              painter: PolygonPainter(
                  points: (result["polygons"] as List<dynamic>).map((e) {
                Map<String, double> xy = Map<String, double>.from(e);
                xy['x'] = (xy['x'] as double) * factorX;
                xy['y'] = (xy['y'] as double) * factorY;
                return xy;
              }).toList()),
            )),
      ]);
    }).toList();
  }
}

class PolygonPainter extends CustomPainter {
  final List<Map<String, double>> points;

  PolygonPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color.fromARGB(129, 255, 2, 124)
      ..strokeWidth = 2
      ..style = PaintingStyle.fill;

    final path = Path();
    if (points.isNotEmpty) {
      path.moveTo(points[0]['x']!, points[0]['y']!);
      for (var i = 1; i < points.length; i++) {
        path.lineTo(points[i]['x']!, points[i]['y']!);
      }
      path.close();
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return false;
  }
}

// -------------------------------------------TesseractImage-------------------------------------------
class TesseractImage extends StatefulWidget {
  final FlutterVision vision;
  const TesseractImage({Key? key, required this.vision}) : super(key: key);

  @override
  State<TesseractImage> createState() => _TesseractImageState();
}

class _TesseractImageState extends State<TesseractImage> {
  late List<Map<String, dynamic>> tesseractResults = [];
  File? imageFile;
  bool isLoaded = false;

  @override
  void initState() {
    super.initState();
    loadTesseractModel().then((value) {
      setState(() {
        isLoaded = true;
        tesseractResults = [];
      });
    });
  }

  @override
  void dispose() async {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isLoaded) {
      return const Scaffold(
        body: Center(
          child: Text("Model not loaded, waiting for it"),
        ),
      );
    }
    return Center(
      child: SingleChildScrollView(
        child: Column(
          children: [
            imageFile != null ? Image.file(imageFile!) : const SizedBox(),
            tesseractResults.isEmpty
                ? const SizedBox()
                : Align(child: Text(tesseractResults[0]["text"])),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: pickImage,
                  child: const Text("Pick an image"),
                ),
                ElevatedButton(
                  onPressed: tesseractOnImage,
                  child: const Text("Get Text"),
                )
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> loadTesseractModel() async {
    await widget.vision.loadTesseractModel(
      args: {
        'psm': '11',
        'oem': '1',
        'preserve_interword_spaces': '1',
      },
      language: 'spa',
    );
    setState(() {
      isLoaded = true;
    });
  }

  Future<void> pickImage() async {
    final ImagePicker picker = ImagePicker();
    // Capture a photo
    final XFile? photo = await picker.pickImage(source: ImageSource.gallery);
    if (photo != null) {
      setState(() {
        imageFile = File(photo.path);
      });
    }
  }

  tesseractOnImage() async {
    tesseractResults.clear();
    Uint8List byte = await imageFile!.readAsBytes();
    final result = await widget.vision.tesseractOnImage(bytesList: byte);
    if (result.isNotEmpty) {
      setState(() {
        tesseractResults = result;
      });
    }
  }
}
