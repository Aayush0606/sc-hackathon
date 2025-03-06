import 'package:flutter/material.dart';
import 'screens/landing_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YOLO Detection',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const LandingPage(),
    );
  }
}
