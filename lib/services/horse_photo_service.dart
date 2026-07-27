import 'package:flutter/services.dart';

class HorsePhotoService {
  static const MethodChannel _channel = MethodChannel('intakt_app/horse_photo');

  static Future<String?> pickHorsePhoto() async {
    final path = await _channel.invokeMethod<String>('pickHorsePhoto');
    return path;
  }
}
