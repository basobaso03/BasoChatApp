import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'chat_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  static const String _onboardingSeenKey = 'onboarding_seen';

  final PageController _pageController = PageController();
  late final AnimationController _backgroundController;
  late final AnimationController _floatController;

  int _currentPage = 0;
  bool _isFinishing = false;

  static const List<_OnboardingSlideData> _slides = [
    _OnboardingSlideData(
      eyebrow: 'BASOBASO SOFTWARE',
      title: 'A sharper way to learn, research, and think clearly.',
      description:
          'BasoChat App combines deep teaching, grounded academic help, and practical reasoning in one workspace designed to help users understand topics, not just receive short answers.',
      icon: Icons.auto_awesome_rounded,
      accent: Color(0xFF00C9A7),
      panels: [
        _OnboardingPanelData('Deep explanations', 'Step-by-step teaching that builds real understanding.'),
        _OnboardingPanelData('Clean interface', 'Focused design for reading, thinking, and asking better questions.'),
      ],
    ),
    _OnboardingSlideData(
      eyebrow: 'ACADEMIC POWER',
      title: 'Grounded research when the answer needs real evidence.',
      description:
          'The assistant can decide when to use the academic web tool, gather scholarly sources, build literature reviews, verify claims, and clearly show when evidence was used.',
      icon: Icons.library_books_outlined,
      accent: Color(0xFF64D2FF),
      panels: [
        _OnboardingPanelData('Web tool awareness', 'Visible indicators show when external evidence supported a response.'),
        _OnboardingPanelData('Reference workflow', 'Saved sources, citations, evidence cards, and export options stay close to the conversation.'),
      ],
    ),
    _OnboardingSlideData(
      eyebrow: 'STUDY MODES',
      title: 'Move from quick help to serious study without changing apps.',
      description:
          'Switch between explanation, exam preparation, research assistance, academic writing, literature review, and life guidance modes based on what the user actually needs.',
      icon: Icons.tune_rounded,
      accent: Color(0xFF8FDCC7),
      panels: [
        _OnboardingPanelData('Flexible input', 'Use text, voice, and file attachments inside the same chat workflow.'),
        _OnboardingPanelData('Detailed teaching', 'Normal explanations are now structured to teach in depth instead of collapsing into summaries.'),
      ],
    ),
    _OnboardingSlideData(
      eyebrow: 'LIFE GUIDANCE',
      title: 'Bring real-life situations and get calm, analyzed guidance.',
      description:
          'Users can describe uncertainty, dilemmas, planning problems, or personal situations and receive balanced analysis, options, tradeoffs, and next steps designed to be genuinely useful.',
      icon: Icons.psychology_alt_rounded,
      accent: Color(0xFFFFC36B),
      panels: [
        _OnboardingPanelData('Built by BASOBASO SOFTWARE', 'Designed for real users who need clarity in both academic and everyday decisions.'),
        _OnboardingPanelData('Contact', 'basobasosoftwares@gmail.com'),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat(reverse: true);
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _backgroundController.dispose();
    _floatController.dispose();
    super.dispose();
  }

  Future<void> _nextPage() async {
    if (_currentPage >= _slides.length - 1) {
      await _finishOnboarding();
      return;
    }

    await _pageController.nextPage(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _previousPage() async {
    if (_currentPage <= 0) {
      return;
    }
    await _pageController.previousPage(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _contactCompany() async {
    const email = 'basobasosoftwares@gmail.com';
    final uri = Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: <String, String>{
        'subject': 'BasoChat App Inquiry',
      },
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    await Clipboard.setData(const ClipboardData(text: email));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Email copied: basobasosoftwares@gmail.com'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _finishOnboarding() async {
    if (_isFinishing) {
      return;
    }
    setState(() => _isFinishing = true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingSeenKey, true);

    if (!mounted) {
      return;
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => const ChatScreen(),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 650),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slide = _slides[_currentPage];
    final isLast = _currentPage == _slides.length - 1;

    return Scaffold(
      backgroundColor: const Color(0xFF080C14),
      body: AnimatedBuilder(
        animation: Listenable.merge([_backgroundController, _floatController]),
        builder: (context, _) {
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF060B12),
                  Color.lerp(const Color(0xFF0C1625), slide.accent.withOpacity(0.22), 0.35)!,
                  const Color(0xFF09111C),
                ],
              ),
            ),
            child: Stack(
              children: [
                const Positioned.fill(child: _OnboardingGrid()),
                Positioned(
                  top: -80 + (_backgroundController.value * 18),
                  left: -40,
                  child: _GlowOrb(color: slide.accent.withOpacity(0.22), size: 220),
                ),
                Positioned(
                  bottom: -100 + (_floatController.value * 26),
                  right: -30,
                  child: _GlowOrb(color: const Color(0xFF64D2FF).withOpacity(0.16), size: 260),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: LinearGradient(
                                  colors: [slide.accent, const Color(0xFF0097A7)],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: slide.accent.withOpacity(0.3),
                                    blurRadius: 24,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'BasoChat App',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'by BASOBASO SOFTWARE',
                                    style: TextStyle(
                                      color: Color(0xFF8BA3B0),
                                      fontSize: 11,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${_currentPage + 1}/${_slides.length}',
                              style: const TextStyle(color: Color(0xFF8BA3B0), fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        Expanded(
                          child: PageView.builder(
                            controller: _pageController,
                            itemCount: _slides.length,
                            onPageChanged: (value) => setState(() => _currentPage = value),
                            itemBuilder: (context, index) {
                              final item = _slides[index];
                              return TweenAnimationBuilder<double>(
                                key: ValueKey(index),
                                duration: const Duration(milliseconds: 500),
                                tween: Tween(begin: 0.92, end: 1),
                                curve: Curves.easeOutCubic,
                                builder: (context, value, child) {
                                  return Opacity(
                                    opacity: value,
                                    child: Transform.translate(
                                      offset: Offset(0, (1 - value) * 36),
                                      child: child,
                                    ),
                                  );
                                },
                                child: _OnboardingSlide(
                                  data: item,
                                  floatValue: _floatController.value,
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: List.generate(
                            _slides.length,
                            (index) => AnimatedContainer(
                              duration: const Duration(milliseconds: 260),
                              margin: const EdgeInsets.only(right: 8),
                              width: index == _currentPage ? 30 : 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: index == _currentPage ? slide.accent : const Color(0xFF203346),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: Colors.white.withOpacity(0.08)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isLast
                                    ? 'You are ready to start using BasoChat App.'
                                    : 'Slide ${_currentPage + 1} of ${_slides.length}. Swipe or use the buttons to continue.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: const Color(0xFF8BA3B0),
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (_currentPage > 0)
                                    SizedBox(
                                      height: 54,
                                      child: OutlinedButton(
                                        onPressed: _previousPage,
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.white,
                                          side: BorderSide(color: Colors.white.withOpacity(0.14)),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.arrow_back_rounded, size: 18),
                                            SizedBox(width: 8),
                                            Text('Back'),
                                          ],
                                        ),
                                      ),
                                    ),
                                  if (isLast)
                                    SizedBox(
                                      height: 54,
                                      child: OutlinedButton(
                                        onPressed: _contactCompany,
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.white,
                                          side: BorderSide(color: slide.accent.withOpacity(0.42)),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.mail_outline_rounded, size: 18),
                                            SizedBox(width: 8),
                                            Text('Contact'),
                                          ],
                                        ),
                                      ),
                                    ),
                                  SizedBox(
                                    height: 54,
                                    child: ElevatedButton(
                                      onPressed: _isFinishing ? null : (isLast ? _finishOnboarding : _nextPage),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 22),
                                        backgroundColor: slide.accent,
                                        foregroundColor: const Color(0xFF061014),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (_isFinishing)
                                            const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          else
                                            Text(
                                              isLast ? 'Start' : 'Next',
                                              style: const TextStyle(fontWeight: FontWeight.w800),
                                            ),
                                          if (!_isFinishing) ...[
                                            const SizedBox(width: 8),
                                            Icon(isLast ? Icons.rocket_launch_rounded : Icons.arrow_forward_rounded),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _OnboardingSlide extends StatelessWidget {
  const _OnboardingSlide({
    required this.data,
    required this.floatValue,
  });

  final _OnboardingSlideData data;
  final double floatValue;

  @override
  Widget build(BuildContext context) {
    final yShift = (floatValue - 0.5) * 16;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: data.accent.withOpacity(0.14),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: data.accent.withOpacity(0.26)),
            ),
            child: Text(
              data.eyebrow,
              style: TextStyle(
                color: data.accent,
                fontSize: 11,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            data.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              height: 1.08,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            data.description,
            style: const TextStyle(
              color: Color(0xFFC7D6E0),
              fontSize: 15,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 28),
          Transform.translate(
            offset: Offset(0, yShift),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.06),
                    data.accent.withOpacity(0.16),
                    const Color(0xFF102033),
                  ],
                ),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
                boxShadow: [
                  BoxShadow(
                    color: data.accent.withOpacity(0.12),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                children: [
                  _OnboardingHeroArt(data: data),
                  const SizedBox(height: 22),
                  ...data.panels.map(
                    (panel) => Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0E1A29).withOpacity(0.82),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.06)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            margin: const EdgeInsets.only(top: 6),
                            decoration: BoxDecoration(color: data.accent, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  panel.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  panel.description,
                                  style: const TextStyle(
                                    color: Color(0xFF9AB0BF),
                                    height: 1.45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingSlideData {
  const _OnboardingSlideData({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
    required this.panels,
  });

  final String eyebrow;
  final String title;
  final String description;
  final IconData icon;
  final Color accent;
  final List<_OnboardingPanelData> panels;
}

class _OnboardingPanelData {
  const _OnboardingPanelData(this.title, this.description);

  final String title;
  final String description;
}

class _OnboardingHeroArt extends StatelessWidget {
  const _OnboardingHeroArt({required this.data});

  final _OnboardingSlideData data;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 216,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 8,
            left: 18,
            child: Transform.rotate(
              angle: -0.08,
              child: _heroSurface(
                width: 160,
                height: 84,
                color: Colors.white.withOpacity(0.06),
                border: Colors.white.withOpacity(0.08),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 54,
                      height: 8,
                      decoration: BoxDecoration(
                        color: data.accent.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: 96,
                      height: 8,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6E8295).withOpacity(0.6),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 72,
                      height: 8,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6E8295).withOpacity(0.35),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 8,
            right: 4,
            child: Transform.rotate(
              angle: 0.06,
              child: _heroSurface(
                width: 168,
                height: 104,
                color: data.accent.withOpacity(0.1),
                border: data.accent.withOpacity(0.16),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 140,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: data.accent,
                              ),
                              child: Icon(data.icon, color: const Color(0xFF061014), size: 16),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'CREATOR',
                                style: TextStyle(
                                  color: data.accent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.9,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'BASOBASO SOFTWARE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Clarity for learning, research, and real-life guidance',
                          style: TextStyle(
                            color: const Color(0xFFD3E0E8).withOpacity(0.88),
                            fontSize: 9.8,
                            height: 1.18,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [data.accent, const Color(0xFF0097A7)]),
              boxShadow: [
                BoxShadow(
                  color: data.accent.withOpacity(0.3),
                  blurRadius: 28,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(data.icon, color: Colors.white, size: 36),
          ),
        ],
      ),
    );
  }

  Widget _heroSurface({
    required double width,
    required double height,
    required Color color,
    required Color border,
    required Widget child,
  }) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: border),
      ),
      child: child,
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withOpacity(0)],
          ),
        ),
      ),
    );
  }
}

class _OnboardingGrid extends StatelessWidget {
  const _OnboardingGrid();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _OnboardingGridPainter(),
    );
  }
}

class _OnboardingGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF183043).withOpacity(0.18)
      ..strokeWidth = 1;

    const gap = 32.0;
    for (double x = 0; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}