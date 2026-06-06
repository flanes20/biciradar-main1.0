import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pages/auth_page.dart';
import 'services/cache_service.dart';
import 'services/connectivity_service.dart';
import 'services/notification_service.dart';
import 'services/ride_stats_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://kcyogbqdasmdedbpgsit.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtjeW9nYnFkYXNtZGVkYnBnc2l0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM4ODgxNzcsImV4cCI6MjA4OTQ2NDE3N30.QsW0-woPH6z71IetIvxhUWGy9tlnmO-TBEkEknHyNic',
  );

  await CacheService.init();
  await ConnectivityService.init();
  await NotificationService.instance.init();
  await RideStatsService.init();

  runApp(const BiciRadarApp());
}

class BiciRadarApp extends StatelessWidget {
  const BiciRadarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BiciRadar',
      theme: ThemeData(primarySwatch: Colors.green),
      home: const AuthPage(),
    );
  }
}
