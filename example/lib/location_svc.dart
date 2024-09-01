import 'dart:math' as math;
import 'package:location/location.dart';

class LocationService {
  LocationService._privateConstructor();
  static final LocationService _instance =
      LocationService._privateConstructor();
  factory LocationService() {
    return _instance;
  }

  // Determine the current position of the device.
  // When the location services are not enabled or permissions
  // are denied the `Future` will return an error.
  Future<LocationData?> getCurrentLocation() async {
    final location = Location();

    // Test if location services are enabled.
    final serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled don't continue
      // accessing the position and request users of the
      // App to enable the location services.
      return Future.error("Location services are disabled.");
    }

    // Check if permission is granted
    var permission = await location.hasPermission();
    if (permission == PermissionStatus.denied) {
      // If denied, then request permission
      permission = await location.requestPermission();
      if (permission == PermissionStatus.denied) {
        // If denied, then show error
        return Future.error("Location permissions are denied");
      }
    }

    if (permission == PermissionStatus.deniedForever) {
      // Permissions are denied forever, handle appropriately.
      return Future.error(
          "Location permissions are permanently denied, we cannot request permissions.");
    }

    try {
      return await location.getLocation();
    } catch (e) {
      return Future.error("Error getting location: $e");
    }
  }

  // Calculate distance between 2 latitude-longitude points
  double calculateDistance(lat1, lng1, lat2, lng2) {
    const r = 6371; // km
    const p = math.pi / 180;

    final a = 0.5 -
        math.cos((lat2 - lat1) * p) / 2 +
        math.cos(lat1 * p) *
            math.cos(lat2 * p) *
            (1 - math.cos((lng2 - lng1) * p)) /
            2;

    return 1000 * 2 * r * math.asin(math.sqrt(a)); // in meters
  }
}
