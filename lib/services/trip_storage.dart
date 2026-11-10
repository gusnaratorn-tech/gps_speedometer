import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/trip_record.dart';

class TripStorageService {
  static const String _fileName = 'trip_history.json';

  static Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<List<TripRecord>> loadTrips() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final List<dynamic> list = jsonDecode(content) as List<dynamic>;
      return list.map((e) => TripRecord.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveTrip(TripRecord trip) async {
    try {
      final trips = await loadTrips();
      trips.insert(0, trip);
      final file = await _getFile();
      final jsonStr = jsonEncode(trips.map((e) => e.toJson()).toList());
      await file.writeAsString(jsonStr);
    } catch (_) {}
  }

  static Future<void> deleteTrip(String id) async {
    try {
      final trips = await loadTrips();
      trips.removeWhere((t) => t.id == id);
      final file = await _getFile();
      final jsonStr = jsonEncode(trips.map((e) => e.toJson()).toList());
      await file.writeAsString(jsonStr);
    } catch (_) {}
  }

  static Future<void> clearAll() async {
    try {
      final file = await _getFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
