import 'package:geohash_plus/geohash_plus.dart';

class GeohashUtil {
  static String encode(double latitude, double longitude, {int precision = 5}) {
    return GeoHash.encode(latitude, longitude, precision: precision).hash;
  }

  static List<String> getGeohashBox(
    double southLat,
    double westLng,
    double northLat,
    double eastLng,
    int precision,
  ) {
    final geohashes = <String>{};
    final latStep = (northLat - southLat) / 8;
    final lngStep = (eastLng - westLng) / 8;
    for (double lat = southLat; lat <= northLat; lat += latStep) {
      for (double lng = westLng; lng <= eastLng; lng += lngStep) {
        geohashes.add(GeoHash.encode(lat, lng, precision: precision).hash);
      }
    }
    return geohashes.toList();
  }
}
