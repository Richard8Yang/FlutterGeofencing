import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class MapAuthInfo {
  final String? apiKey;
  final String? appId;
  final String? appCode;

  get authRequired => apiKey != null || appId != null || appCode != null;

  MapAuthInfo({this.apiKey, this.appId, this.appCode});
}

class MapTileProvider extends Object {
  final String name;
  final String attribution;
  final String htmlAttribution;
  final String url;
  final int maxZoom;
  final int minZoom;
  final MapAuthInfo authInfo;

  MapTileProvider({
    required this.name,
    required this.attribution,
    required this.htmlAttribution,
    required this.url,
    required this.authInfo,
    required this.maxZoom,
    required this.minZoom,
  });
}

class MapProvider {
  // Available map tile providers are listed in below link:
  // https://github.com/JuliaGeo/TileProviders.jl/blob/main/src/leaflet-providers-parsed.json
  final String srcProvidersUrl =
      'https://raw.githubusercontent.com/JuliaGeo/TileProviders.jl/main/src/leaflet-providers-parsed.json';
  final String srcProvidersAsset = 'assets/maptile_providers.json';

  final availableProviders = <MapTileProvider>[];

  List<MapTileProvider> get providersList => availableProviders;

  String get currentProvider =>
      availableProviders.isEmpty ? "" : availableProviders.first.name;

  String? findProviderByName(String name) {
    for (final provider in availableProviders) {
      if (provider.name == name) {
        return provider.url;
      }
    }
    return null;
  }

  Future<void> loadProviders({fromAsset = true}) async {
    availableProviders.clear();
    if (fromAsset) {
      // Load the JSON file from the assets folder
      rootBundle.loadString(srcProvidersAsset).then((String jsonStr) {
        final jsonData = json.decode(jsonStr);
        // Process the JSON data as needed
        _parseProviders(jsonData);
      });
    } else {
      // Load the JSON file from the network
      final response = await http.get(Uri.parse(srcProvidersUrl));
      if (response.statusCode == 200) {
        // Parse the JSON data
        final jsonData = json.decode(response.body);
        // Process the JSON data as needed
        _parseProviders(jsonData);
      } else {
        throw Exception('Failed to load providers');
      }
    }
  }

  void _parseProviders(Map jsonData) {
    for (final providerKey in jsonData.keys) {
      if (jsonData[providerKey] is Map) {
        var provider = jsonData[providerKey] as Map;
        if (!provider.containsKey('url')) {
          _parseProviders(provider);
        } else {
          final name = provider['name'] as String;
          final url = provider['url'] as String;
          final attribution = provider['attribution'] as String;
          final htmlAttribution = provider['html_attribution'] as String;
          final maxZoom = provider['max_zoom'] as int? ?? 22;
          final minZoom = provider['min_zoom'] as int? ?? 0;

          final apiKey = provider['apiKey'] as String?;
          final appId = provider['app_id'] as String?;
          final appCode = provider['app_code'] as String?;
          final authInfo = MapAuthInfo(
            apiKey: apiKey,
            appId: appId,
            appCode: appCode,
          );

          availableProviders.add(MapTileProvider(
            name: name,
            url: url,
            attribution: attribution,
            htmlAttribution: htmlAttribution,
            maxZoom: maxZoom,
            minZoom: minZoom,
            authInfo: authInfo,
          ));
        }
      }
    }
  }
}
