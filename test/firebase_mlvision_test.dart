import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_mlvision/firebase_mlvision.dart';

void main() {
  const MethodChannel channel = MethodChannel('firebase_mlvision');

  setUp(() {
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      return '42';
    });
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });

  test('getPlatformVersion', () async {
    expect(await FirebaseMlvision.platformVersion, '42');
  });
}
