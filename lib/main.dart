import 'package:flutter/material.dart';
import 'screens/second_page.dart';
import 'services/storage_service.dart'; // Assicurati che questo percorso sia corretto
import 'services/image_cache_service.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ImageCacheService().initialize();
  // Migra i dati esistenti alla nuova struttura
  final storage = StorageService();
  await storage.migrateExistingData();
  
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Desktop Modular Album App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const SecondPage(),
    );
  }
}