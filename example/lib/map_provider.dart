import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class MapTileProvider extends Object {
  final String name;
  final String url;
  final int maxZoom;
  final int minZoom;
  final Map<String, String> params;
  final Map<String, String> auth;

  MapTileProvider({
    required this.name,
    required this.url,
    required this.maxZoom,
    required this.minZoom,
    required this.params,
    required this.auth,
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

  String get currentProviderName =>
      availableProviders.isEmpty ? "" : availableProviders.first.name;

  MapTileProvider? findProviderByName(String name) {
    for (final provider in availableProviders) {
      if (provider.name == name) {
        return provider;
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
          final maxZoom = provider['max_zoom'] as int? ?? 22;
          final minZoom = provider['min_zoom'] as int? ?? 0;
          final params = Map<String, String>();
          final auth = Map<String, String>();

          const authFields = [
            'apiKey',
            'app_id',
            'app_code',
            'accessToken',
            'key'
          ];
          for (final field in authFields) {
            if (provider.containsKey(field)) {
              auth[field] = provider[field] as String;
            } else if (url.contains(field)) {
              auth[field] = "<insert your $field here>";
            }
          }
          for (final field in provider.keys) {
            if (field != 'name' && field != 'url') {
              if (authFields.contains(field)) {
                auth[field] = provider[field] as String;
              } else {
                params[field] = provider[field] is String
                    ? provider[field]
                    : provider[field].toString();
              }
            }
          }

          availableProviders.add(MapTileProvider(
            name: name,
            url: url,
            maxZoom: maxZoom,
            minZoom: minZoom,
            params: params,
            auth: auth,
          ));
        }
      }
    }

    availableProviders.sort((provider1, provider2) {
      final needSort = provider1.auth.isEmpty == provider2.auth.isEmpty;
      return needSort
          ? provider1.name.compareTo(provider2.name)
          : (provider2.auth.isEmpty ? 1 : -1);
    });
  }
}
