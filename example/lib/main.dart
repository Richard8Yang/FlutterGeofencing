// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:isolate';
import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:geofencing/geofencing.dart';
import 'package:geofencing_example/location_svc.dart';
import 'package:geofencing_example/map_provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final AndroidGeofencingSettings androidSettings = AndroidGeofencingSettings(
    initialTrigger: <GeofenceEvent>[
      GeofenceEvent.enter,
      GeofenceEvent.exit,
      GeofenceEvent.dwell
    ],
    loiteringDelay: 1000 * 60,
  );

  double latitude = 37.419851;
  double longitude = -122.078818;
  ReceivePort port = ReceivePort();
  double radius = 200;
  double regLat = 0;
  double regLng = 0;
  List<String> registeredGeofences = [];
  final List<GeofenceEvent> triggers = <GeofenceEvent>[
    GeofenceEvent.enter,
    GeofenceEvent.dwell,
    GeofenceEvent.exit
  ];

  String? currentMapProviderName;
  final mapProvider = MapProvider();
  late Polyline polyline;

  List<String> logs = [];

  @pragma('vm:entry-point')
  @override
  void initState() {
    super.initState();
    bool succ = IsolateNameServer.registerPortWithName(
        port.sendPort, 'geofencing_send_port');
    if (!succ) {
      IsolateNameServer.removePortNameMapping('geofencing_send_port');
      succ = IsolateNameServer.registerPortWithName(
          port.sendPort, 'geofencing_send_port');
      if (!succ) {
        print('Failed to register isolate name server!');
      }
    }
    port.listen((data) {
      setState(() {
        updateCurrentLocation();
        // get current time
        final now = DateTime.now();
        final ids = data['ids']; // as List<String>;
        final event = data['event'] as String;
        //latitude = data['latitude'] as double;
        //longitude = data['longitude'] as double;
        final distance =
            calculateDistanceFromCenter(loc: LatLng(latitude, longitude));
        if (event == GeofenceEvent.enter.toString()) {
          logs.add(
              "[$now] Enter fence ${ids} [$latitude,$longitude] $distance");
        } else if (event == GeofenceEvent.exit.toString()) {
          logs.add(
              "[$now] Leave fence ${ids} [$latitude,$longitude] $distance");
        } else if (event == GeofenceEvent.dwell.toString()) {
          logs.add(
              "[$now] Stay in fence ${ids} [$latitude,$longitude] $distance");
        }
      });
    });
    initPlatformState();

    mapProvider.loadProviders().then((val) {
      setState(() {
        currentMapProviderName = "OpenStreetMap.CH";
      });
    });

    polyline = Polyline(
      points: <LatLng>[],
      strokeWidth: 4.0,
      color: Colors.blue,
      pattern: const StrokePattern.solid(
          //spacingFactor: 2,
          ),
      borderStrokeWidth: 2,
      borderColor: Colors.blue.withOpacity(0.5),
    );

    updateCurrentLocation();
  }

  void updateCurrentLocation() {
    LocationService().getCurrentLocation().then((pos) {
      setState(() {
        latitude = pos.latitude;
        longitude = pos.longitude;
        if (registeredGeofences.isNotEmpty) {
          polyline.points.add(LatLng(latitude, longitude));
          print(
              "[${DateTime.now()}] distance: ${calculateDistanceFromCenter()}");
        }
      });
      //Future.delayed(Duration(seconds: 10), updateCurrentLocation);
    });
  }

  @pragma('vm:entry-point')
  static void callback(List<String> ids, Location l, GeofenceEvent e) async {
    print('Fences: $ids Location $l Event: $e');
    final send = IsolateNameServer.lookupPortByName('geofencing_send_port');
    final data = {
      'ids': List.from(ids),
      'latitude': l.latitude,
      'longitude': l.longitude,
      'event': e.toString(),
    };
    send?.send(data);
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    print('Initializing...');
    await GeofencingManager.initialize();
    print('Initialization done');
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

  double calculateDistanceFromCenter({LatLng? loc}) {
    return loc != null
        ? calculateDistance(loc.latitude, loc.longitude, regLat, regLng)
        : calculateDistance(latitude, longitude, regLat, regLng);
  }

  @override
  Widget build(BuildContext context) {
    final curProv = currentMapProviderName != null
        ? mapProvider.findProviderByName(currentMapProviderName!)
        : null;
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Flutter Geofencing Example'),
        ),
        body: Container(
          padding: const EdgeInsets.all(10.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              DropdownButton(
                isExpanded: true,
                value:
                    currentMapProviderName ?? mapProvider.currentProviderName,
                items: mapProvider.providersList
                    .map(
                      (e) => DropdownMenuItem<String>(
                        value: e.name,
                        child: Text(
                          e.name,
                          style: TextStyle(
                              color:
                                  e.auth.isNotEmpty ? Colors.red : Colors.green,
                              backgroundColor: e.name == currentMapProviderName
                                  ? Colors.blueGrey
                                  : Colors.transparent),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (String? name) {
                  setState(() {
                    if (name == null) return;
                    currentMapProviderName = name;
                  });
                },
              ),
              if (currentMapProviderName != null && curProv != null)
                Expanded(
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(latitude, longitude),
                      initialZoom: 15,
                      interactionOptions: InteractionOptions(),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: curProv.url,
                        userAgentPackageName: 'com.rpy.app',
                        additionalOptions: curProv.params,
                      ),
                      PolylineLayer(polylines: [polyline]),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(latitude, longitude),
                            width: 24,
                            height: 24,
                            alignment: Alignment.topCenter,
                            child: Icon(
                              Icons.arrow_downward_rounded,
                              color: Colors.redAccent,
                            ),
                          ),
                          Marker(
                            point: LatLng(regLat, regLng),
                            width: 24,
                            height: 24,
                            alignment: Alignment.topCenter,
                            child: Icon(
                              Icons.arrow_downward_rounded,
                              color: Colors.greenAccent,
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Text("Radius: "),
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(hintText: 'Radius'),
                        keyboardType: TextInputType.number,
                        controller: TextEditingController(
                            text: radius.toInt().toString()),
                        onChanged: (String s) {
                          radius = double.tryParse(s) ?? 0.0;
                        },
                        onTapOutside: (event) {
                          FocusManager.instance.primaryFocus?.unfocus();
                        },
                      ),
                    ),
                    Text(" m  "),
                    ElevatedButton(
                      child: const Icon(Icons.gps_fixed),
                      onPressed: () => updateCurrentLocation(),
                    ),
                    ElevatedButton(
                      child: const Icon(Icons.login), //Text('Register'),
                      onPressed: () {
                        LocationService().getCurrentLocation().then((pos) {
                          regLat = latitude;
                          regLng = longitude;
                          GeofencingManager.registerGeofence(
                                  GeofenceRegion(
                                      'mtv', regLat, regLng, radius, triggers,
                                      androidCfg: androidSettings),
                                  callback)
                              .then(
                            (_) {
                              GeofencingManager.getRegisteredGeofenceIds()
                                  .then((value) {
                                setState(() {
                                  registeredGeofences = value;
                                  polyline.points.clear();
                                  logs.add(
                                      "[${DateTime.now()}] Register fence $value [$regLat,$regLng] $radius");
                                });
                              });
                            },
                          );
                        });
                      },
                    ),
                    ElevatedButton(
                      child: const Icon(Icons.logout), //Text('Unregister'),
                      onPressed: () =>
                          GeofencingManager.removeGeofenceById('mtv').then((_) {
                        GeofencingManager.getRegisteredGeofenceIds()
                            .then((value) {
                          setState(() {
                            registeredGeofences = value;
                            logs.add(
                                "[${DateTime.now()}] Unregister fence mtv");
                          });
                        });
                      }),
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.black,
                    style: BorderStyle.solid,
                    width: 1.0,
                  ),
                  //color: Color(0xFFF05A22),
                  borderRadius: BorderRadius.circular(5.0),
                ),
                height: 250,
                child: ListView.builder(
                  padding: EdgeInsets.all(0.0),
                  itemExtent: 20,
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    return ListTile(
                      title: Text(
                        logs[index],
                        style: TextStyle(fontSize: 8),
                        //maxLines: 1,
                      ),
                    );
                  },
                ),
              ),
              SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
