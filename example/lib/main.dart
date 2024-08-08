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

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String geofenceState = 'N/A';
  List<String> registeredGeofences = [];
  double latitude = 37.419851;
  double longitude = -122.078818;
  double radius = 1.0;

  double regLat = 0;
  double regLng = 0;

  ReceivePort port = ReceivePort();
  final List<GeofenceEvent> triggers = <GeofenceEvent>[
    GeofenceEvent.enter,
    GeofenceEvent.dwell,
    GeofenceEvent.exit
  ];

  final AndroidGeofencingSettings androidSettings = AndroidGeofencingSettings(
      initialTrigger: <GeofenceEvent>[
        GeofenceEvent.enter,
        GeofenceEvent.exit,
        GeofenceEvent.dwell
      ],
      loiteringDelay: 1000 * 60);

  @override
  void initState() {
    super.initState();
    IsolateNameServer.registerPortWithName(
        port.sendPort, 'geofencing_send_port');
    port.listen((dynamic data) {
      print('Event: $data');
      setState(() {
        geofenceState = data;
      });
    });
    initPlatformState();

    updateCurrentLocation();
  }

  void updateCurrentLocation() {
    LocationService().getCurrentLocation().then((pos) {
      setState(() {
        latitude = pos.latitude;
        longitude = pos.longitude;
      });
    });
    Future.delayed(Duration(seconds: 10), updateCurrentLocation);
  }

  static void callback(List<String> ids, Location l, GeofenceEvent e) async {
    print('Fences: $ids Location $l Event: $e');
    final send = IsolateNameServer.lookupPortByName('geofencing_send_port');
    send?.send(e.toString());
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

  double calculateDistanceFromCenter() {
    return calculateDistance(latitude, longitude, regLat, regLng);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Flutter Geofencing Example'),
        ),
        body: Container(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text('Current state: $geofenceState'),
              Center(
                child: ElevatedButton(
                  child: const Text('Register'),
                  onPressed: () {
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
                          });
                        });
                      },
                    );
                  },
                ),
              ),
              Text('Registered Geofences: $registeredGeofences'),
              Text('Geofence center: ($regLat, $regLng)'),
              Center(
                child: ElevatedButton(
                  child: const Text('Unregister'),
                  onPressed: () =>
                      GeofencingManager.removeGeofenceById('mtv').then((_) {
                    GeofencingManager.getRegisteredGeofenceIds().then((value) {
                      setState(() {
                        registeredGeofences = value;
                      });
                    });
                  }),
                ),
              ),
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Latitude',
                ),
                keyboardType: TextInputType.number,
                controller: TextEditingController(text: latitude.toString()),
                onChanged: (String s) {
                  latitude = double.tryParse(s) ?? 0.0;
                },
                onTapOutside: (event) {
                  FocusManager.instance.primaryFocus?.unfocus();
                },
              ),
              TextField(
                decoration: const InputDecoration(hintText: 'Longitude'),
                keyboardType: TextInputType.number,
                controller: TextEditingController(text: longitude.toString()),
                onChanged: (String s) {
                  longitude = double.tryParse(s) ?? 0.0;
                },
                onTapOutside: (event) {
                  FocusManager.instance.primaryFocus?.unfocus();
                },
              ),
              TextField(
                decoration: const InputDecoration(hintText: 'Radius'),
                keyboardType: TextInputType.number,
                controller: TextEditingController(text: radius.toString()),
                onChanged: (String s) {
                  radius = double.tryParse(s) ?? 0.0;
                },
                onTapOutside: (event) {
                  FocusManager.instance.primaryFocus?.unfocus();
                },
              ),
              Text("Distance: ${calculateDistanceFromCenter()} m"),
            ],
          ),
        ),
      ),
    );
  }
}
