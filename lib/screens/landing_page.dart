import 'package:flutter/material.dart';
import 'detection_screen.dart';
import 'package:google_fonts/google_fonts.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({Key? key}) : super(key: key);

  @override
  _LandingPageState createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage>
    with TickerProviderStateMixin {
  late AnimationController _gradientController;
  late Animation<Color?> _colorAnimation1;
  late Animation<Color?> _colorAnimation2;

  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();

    _gradientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _colorAnimation1 =
        ColorTween(begin: Colors.deepPurple, end: Colors.blueAccent)
            .animate(_gradientController);
    _colorAnimation2 =
        ColorTween(begin: Colors.purple, end: Colors.lightBlueAccent)
            .animate(_gradientController);

    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _bounceAnimation = Tween<double>(begin: 0, end: -20).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _gradientController.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  void _handleSwipe(DragEndDetails details) {
    if (details.velocity.pixelsPerSecond.dy < -300) {
      Navigator.push(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 600),
          pageBuilder: (context, animation, secondaryAnimation) =>
              const DetectionScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const begin = Offset(0, 1);
            const end = Offset.zero;
            final tween = Tween(begin: begin, end: end)
                .chain(CurveTween(curve: Curves.easeInOut));
            return SlideTransition(
              position: animation.drive(tween),
              child: child,
            );
          },
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _gradientController,
      builder: (context, child) {
        return Scaffold(
          body: GestureDetector(
            onVerticalDragEnd: _handleSwipe,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _colorAnimation1.value ?? Colors.deepPurple,
                    _colorAnimation2.value ?? Colors.deepPurpleAccent,
                  ],
                ),
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _bounceAnimation,
                        builder: (context, child) {
                          return Transform.translate(
                            offset: Offset(0, _bounceAnimation.value),
                            child: child,
                          );
                        },
                        child: Image.asset(
                          'assets/images/159078.png',
                          height: 48,
                          width: 48,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        "Merch-Eye",
                        style: GoogleFonts.oswald(
                          textStyle: const TextStyle(
                            fontSize: 52,
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        "Merchandising will not be the same\n Welcome to the world of AI",
                        style: GoogleFonts.oswald(
                          textStyle: const TextStyle(
                            fontSize: 20,
                            color: Colors.white70,
                          ),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 40),
                      AnimatedBuilder(
                        animation: _bounceAnimation,
                        builder: (context, child) {
                          return Transform.translate(
                            offset: Offset(0, _bounceAnimation.value),
                            child: child,
                          );
                        },
                        child: const Icon(
                          Icons.keyboard_arrow_up,
                          size: 48,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
