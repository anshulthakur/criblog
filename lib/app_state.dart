import 'package:flutter/foundation.dart';

class AppState extends ChangeNotifier {
  void notifyDatabaseChanged() {
    notifyListeners();
  }
}