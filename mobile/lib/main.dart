import 'package:flutter/material.dart';

import 'auth/session.dart';
import 'tracking/host.dart';
import 'ui/home_screen.dart';
import 'ui/login_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await TrackerHost.instance.init();
  final session = await SessionStore.load();
  runApp(RadianDriverApp(initialSession: session));
}

class RadianDriverApp extends StatefulWidget {
  const RadianDriverApp({super.key, this.initialSession});

  final Session? initialSession;

  @override
  State<RadianDriverApp> createState() => _RadianDriverAppState();
}

class _RadianDriverAppState extends State<RadianDriverApp> {
  late Session? _session = widget.initialSession;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Radian Driver',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: _session == null
          ? LoginScreen(onSignedIn: (s) => setState(() => _session = s))
          : HomeScreen(
              session: _session!,
              onSignedOut: () => setState(() => _session = null),
            ),
    );
  }
}
