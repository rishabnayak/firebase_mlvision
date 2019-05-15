import 'dart:async';

import 'package:flutter/services.dart';

class FirebaseMlvision {
  static const MethodChannel _channel =
      const MethodChannel('firebase_mlvision');

  static Future<String> get platformVersion async {
    final String version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }
}
