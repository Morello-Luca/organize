import 'package:flutter/material.dart';
import '../widgets/navigation_rail.dart';

class SecondPage extends StatelessWidget {
  const SecondPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: const [
          AppNavigationRail(selectedIndex: 0),
          VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: Center(
              child: Text(
                'Benvenuto nella Home Page (SecondPage)',
                style: TextStyle(fontSize: 24),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
