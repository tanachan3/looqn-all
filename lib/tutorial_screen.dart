import 'package:flutter/material.dart';
import 'package:introduction_screen/introduction_screen.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class TutorialScreen extends StatelessWidget {
  final VoidCallback onFinish;

  const TutorialScreen({Key? key, required this.onFinish}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return IntroductionScreen(
      pages: [
        PageViewModel(
          title: loc.tutorialTitle1,
          body: loc.tutorialBody1,
          image: Center(child: Icon(Icons.map, size: 120, color: Colors.blue)),
        ),
        PageViewModel(
          title: loc.tutorialTitle2,
          body: loc.tutorialBody2,
          image: Center(
              child: Icon(Icons.access_time, size: 120, color: Colors.orange)),
        ),
        PageViewModel(
          title: loc.tutorialTitle3,
          body: loc.tutorialBody3,
          image: Center(
              child: Icon(Icons.location_on, size: 120, color: Colors.green)),
        ),
        PageViewModel(
          title: loc.tutorialTitle4,
          body: loc.tutorialBody4,
          image: Center(
              child: Icon(Icons.touch_app, size: 120, color: Colors.purple)),
        ),
      ],
      onDone: onFinish,
      showSkipButton: true,
      skip: Text(loc.tutorialSkip),
      next: Text(loc.tutorialNext),
      done:
          Text(loc.tutorialDone, style: TextStyle(fontWeight: FontWeight.w600)),
      dotsDecorator: const DotsDecorator(
        activeColor: Colors.blue,
      ),
      curve: Curves.fastOutSlowIn,
    );
  }
}
