import 'package:flutter/material.dart';
import '../screens/second_page.dart';
import '../screens/setlist_page.dart';
import '../screens/options_page.dart'; // Aggiungi questa import

class AppNavigationRail extends StatelessWidget {
  final int selectedIndex;

  const AppNavigationRail({super.key, required this.selectedIndex});

  void _navigate(BuildContext context, int index) {
    if (index == selectedIndex) return;

    Widget destination;
    switch (index) {
      case 0:
        destination = const SecondPage();
        break;
      case 1:
        destination = const SetListPage();
        break;
      case 2: // Aggiungi Options
        destination = const OptionsPage();
        break;
      default:
        destination = const SecondPage();
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => destination),
    );
  }

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: (i) => _navigate(context, i),
      labelType: NavigationRailLabelType.all,
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: Text('Home'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.photo_album_outlined),
          selectedIcon: Icon(Icons.photo_album),
          label: Text('SetList'),
        ),
        NavigationRailDestination( // Aggiungi Options
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: Text('Options'),
        ),
      ],
    );
  }
}