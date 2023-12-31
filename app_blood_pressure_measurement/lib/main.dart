// Copyright 2023, Charles Weinberger & Paul DeMarco.
// All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'screens/historical_blood_pressure.dart';
import 'screens/main_device_screen.dart';
import 'widgets.dart';

import 'models/deviceBloodPressure.dart';

final snackBarKeyA = GlobalKey<ScaffoldMessengerState>();
final snackBarKeyB = GlobalKey<ScaffoldMessengerState>();
final snackBarKeyC = GlobalKey<ScaffoldMessengerState>();
final Map<DeviceIdentifier, ValueNotifier<bool>> isConnectingOrDisconnecting = {};

void main() {
  if (Platform.isAndroid) {
    WidgetsFlutterBinding.ensureInitialized();
    [
      Permission.location,
      Permission.storage,
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan
    ].request().then((status) {
      runApp(const FlutterBlueApp());
    });
  } else {
    runApp(const FlutterBlueApp());
  }
}

class BluetoothAdapterStateObserver extends NavigatorObserver {
  StreamSubscription<BluetoothAdapterState>? _btStateSubscription;

  @override
  void didPush(Route route, Route? previousRoute) {
    super.didPush(route, previousRoute);
    if (route.settings.name == '/deviceScreen') {
      // Start listening to Bluetooth state changes when a new route is pushed
      _btStateSubscription ??= FlutterBluePlus.adapterState.listen((state) {
        if (state != BluetoothAdapterState.on) {
          // Pop the current route if Bluetooth is off
          navigator?.pop();
        }
      });
    }
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    super.didPop(route, previousRoute);
    // Cancel the subscription when the route is popped
    _btStateSubscription?.cancel();
    _btStateSubscription = null;
  }
}

class FlutterBlueApp extends StatelessWidget {
  const FlutterBlueApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.lightBlue,
      home: StreamBuilder<BluetoothAdapterState>(
          stream: FlutterBluePlus.adapterState,
          initialData: BluetoothAdapterState.unknown,
          builder: (c, snapshot) {
            final adapterState = snapshot.data;
            if (adapterState == BluetoothAdapterState.on) {
              return const FindDevicesScreen();
            } else {
              FlutterBluePlus.stopScan();
              return BluetoothOffScreen(adapterState: adapterState);
            }
          }),
      navigatorObservers: [BluetoothAdapterStateObserver()],
    );
  }
}

class BluetoothOffScreen extends StatelessWidget {
  const BluetoothOffScreen({Key? key, this.adapterState}) : super(key: key);

  final BluetoothAdapterState? adapterState;

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: snackBarKeyA,
      child: Scaffold(
        backgroundColor: Colors.lightBlue,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.bluetooth_disabled,
                size: 200.0,
                color: Colors.white54,
              ),
              Text(
                'Bluetooth Adapter is ${adapterState != null ? adapterState.toString().split(".").last : 'not available'}.',
                style: Theme.of(context).primaryTextTheme.titleSmall?.copyWith(color: Colors.white),
              ),
              if (Platform.isAndroid)
                ElevatedButton(
                  child: const Text('TURN ON'),
                  onPressed: () async {
                    try {
                      if (Platform.isAndroid) {
                        await FlutterBluePlus.turnOn();
                      }
                    } catch (e) {
                      final snackBar = snackBarFail(prettyException("Error Turning On:", e));
                      snackBarKeyA.currentState?.removeCurrentSnackBar();
                      snackBarKeyA.currentState?.showSnackBar(snackBar);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class FindDevicesScreen extends StatefulWidget {
  const FindDevicesScreen({Key? key}) : super(key: key);

  @override
  State<FindDevicesScreen> createState() => _FindDevicesScreenState();
}


class _FindDevicesScreenState extends State<FindDevicesScreen> {
  
  Widget get_list_of_devices(BuildContext context){

    Widget bluetoothDevices = StreamBuilder<List<BluetoothDevice>>(
                  stream: Stream.fromFuture(FlutterBluePlus.connectedSystemDevices),
                  initialData: const [],
                  builder: (c, snapshot) => Column(
                    children: (snapshot.data ?? [])
                        .map((d) => ListTile(
                              title: Text(d.localName),
                              subtitle: Text(d.remoteId.toString()),
                              trailing: StreamBuilder<BluetoothConnectionState>(
                                stream: d.connectionState,
                                initialData: BluetoothConnectionState.disconnected,
                                builder: (c, snapshot) {
                                  if (snapshot.data == BluetoothConnectionState.connected) {
                                    return ElevatedButton(
                                      child: const 
                                        Text('ABRIR',
                                          style: TextStyle(
                                            color: Color.fromARGB(255, 0, 0, 0)
                                          ),
                                        ),
                                      onPressed: () {
                                        DeviceBloodPressure.getInstance().setDeviceBloodPressure(d);
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (context) => MainDeviceScreen(
                                              //device: d,
                                              isConnectingOrDisconnecting : isConnectingOrDisconnecting,
                                              snackBarKeyA: snackBarKeyA,
                                              snackBarKeyB :snackBarKeyB, 
                                              snackBarKeyC: snackBarKeyC
                                            ),
                                            // builder:  (context) => DeviceScreen(device: d),
                                            settings: const RouteSettings(name: '/deviceScreen')
                                          )
                                        );
                                      }
                                    );
                                  }
                                  if (snapshot.data == BluetoothConnectionState.disconnected) {
                                    return ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color.fromARGB(255, 0, 0, 0),
                                        foregroundColor: const Color.fromARGB(255, 73, 2, 111), 
                                      ),
                                        child: const 
                                          Text('CONECTAR'),
                                        onPressed: () {
                                          Navigator.of(context).push(MaterialPageRoute(
                                              builder: (context) {
                                                isConnectingOrDisconnecting[d.remoteId] ??= ValueNotifier(true);
                                                isConnectingOrDisconnecting[d.remoteId]!.value = true;
                                                d.connect(timeout: const Duration(seconds: 35)).catchError((e) {
                                                  final snackBar = snackBarFail(prettyException("Connect Error:", e));
                                                  snackBarKeyC.currentState?.removeCurrentSnackBar();
                                                  snackBarKeyC.currentState?.showSnackBar(snackBar);
                                                }).then((v) {
                                                  isConnectingOrDisconnecting[d.remoteId] ??= ValueNotifier(false);
                                                  isConnectingOrDisconnecting[d.remoteId]!.value = false;
                                                });
                                                DeviceBloodPressure.getInstance().setDeviceBloodPressure(d);
                                                return MainDeviceScreen(
                                                  //device: d,
                                                  isConnectingOrDisconnecting : isConnectingOrDisconnecting,
                                                  snackBarKeyA: snackBarKeyA,
                                                  snackBarKeyB :snackBarKeyB, 
                                                  snackBarKeyC: snackBarKeyC
                                                );
                                                // return DeviceScreen(device: d);
                                              },
                                              settings: const RouteSettings(name: '/deviceScreen')));
                                        });
                                  }
                                  return Text(snapshot.data.toString().toUpperCase().split('.')[1]);
                                },
                              ),
                            ))
                        .toList(),
                  ),
                );
    return bluetoothDevices;
  }


  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: snackBarKeyB,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              bottom: Radius.circular(30),
            ),
          ),
          backgroundColor: Colors.cyanAccent[700],
          title: const Text('MEDIÇÃO DE PRESSÃO ARTERIAL',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18
            ),
          ),
        ),
        drawer: Drawer(
          child: ListView(
            padding: EdgeInsets.zero,
            children: <Widget>[
              const DrawerHeader(
                decoration: BoxDecoration(
                  color: Color.fromARGB(255, 190, 149, 187),
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.white,
                      width: 2.0, // Define a largura da borda
                    ),
                  ),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(30),
                  ),
                ),
                child: Text(
                  'Menu',
                  style: TextStyle(
                    fontSize: 24.0,
                    fontWeight: FontWeight.bold,
                    color:  Color.fromARGB(255, 73, 2, 111),
                  ),
                ),
              ),
              ListTile(
                title: const Text(
                  'Histórico',
                  style: TextStyle(
                    fontSize: 24.0,
                    fontWeight: FontWeight.bold,
                    color:  Color.fromARGB(255, 73, 2, 111),
                  ),
                ),
                onTap: () {
                  Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => HistoricalBloodPressure(),
                  )
                );
                },
              ),
            ],
          ),
        ),
        body: RefreshIndicator(
          onRefresh: () {
            setState(() {}); // force refresh of connectedSystemDevices
            if (FlutterBluePlus.isScanningNow == false) {
              FlutterBluePlus.startScan(timeout: const Duration(seconds: 15), androidUsesFineLocation: false);
            }
            return Future.delayed(const Duration(milliseconds: 500)); // show refresh icon breifly
          },
          child: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                get_list_of_devices(context),
                StreamBuilder<List<ScanResult>>(
                  stream: FlutterBluePlus.scanResults,
                  initialData: const [],
                  builder: (c, snapshot) => Column(
                    children: (snapshot.data ?? [])
                        .map(
                          (r) => ScanResultTile(
                            result: r,
                            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (context) {
                                  isConnectingOrDisconnecting[r.device.remoteId] ??= ValueNotifier(true);
                                  isConnectingOrDisconnecting[r.device.remoteId]!.value = true;
                                  r.device.connect(timeout: const Duration(seconds: 35)).catchError((e) {
                                    final snackBar = snackBarFail(prettyException("Connect Error:", e));
                                    snackBarKeyC.currentState?.removeCurrentSnackBar();
                                    snackBarKeyC.currentState?.showSnackBar(snackBar);
                                  }).then((v) {
                                    isConnectingOrDisconnecting[r.device.remoteId] ??= ValueNotifier(false);
                                    isConnectingOrDisconnecting[r.device.remoteId]!.value = false;
                                  });
                                  
                                  DeviceBloodPressure.getInstance().setDeviceBloodPressure(r.device);
                                  return MainDeviceScreen(
                                    //device: r.device,
                                    isConnectingOrDisconnecting : isConnectingOrDisconnecting,
                                    snackBarKeyA: snackBarKeyA,
                                    snackBarKeyB :snackBarKeyB, 
                                    snackBarKeyC: snackBarKeyC
                                  );
                                  // return DeviceScreen(device: r.device);
                                },
                                settings: const RouteSettings(name: '/deviceScreen'))),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
        floatingActionButton: StreamBuilder<bool>(
          stream: FlutterBluePlus.isScanning,
          initialData: false,
          builder: (c, snapshot) {
            if (snapshot.data ?? false) {
              return FloatingActionButton.extended(
                onPressed: () async {
                  try {
                    FlutterBluePlus.stopScan();
                  } catch (e) {
                    final snackBar = snackBarFail(prettyException("Stop Scan Error:", e));
                    snackBarKeyB.currentState?.removeCurrentSnackBar();
                    snackBarKeyB.currentState?.showSnackBar(snackBar);
                  }
                },
                backgroundColor: Colors.red,
                icon: const Icon(Icons.stop),
                label: const Text("PARAR"),
              );
            } else {
              return FloatingActionButton.extended(
                  icon: const Icon(Icons.search_outlined),
                  label: const Text("ESCANEAR"),
                  onPressed: () async {
                    try {
                      if (FlutterBluePlus.isScanningNow == false) {
                        FlutterBluePlus.startScan(timeout: const Duration(seconds: 15), androidUsesFineLocation: false);
                      }
                    } catch (e) {
                      final snackBar = snackBarFail(prettyException("Start Scan Error:", e));
                      snackBarKeyB.currentState?.removeCurrentSnackBar();
                      snackBarKeyB.currentState?.showSnackBar(snackBar);
                    }
                    setState(() {}); // force refresh of connectedSystemDevices
                  });
            }
          },
        ),
      ),
    );
  }
}

class DeviceScreen extends StatelessWidget {
  final BluetoothDevice device;

  const DeviceScreen({Key? key, required this.device}) : super(key: key);

  List<int> _getRandomBytes() {
    final math = Random();
    return [math.nextInt(255), math.nextInt(255), math.nextInt(255), math.nextInt(255)];
  }

  initState() async{
    try {
      await device.discoverServices();
      final snackBar = snackBarGood("Discover Services: Success");
      snackBarKeyC.currentState?.removeCurrentSnackBar();
      snackBarKeyC.currentState?.showSnackBar(snackBar);
    } catch (e) {
      final snackBar = snackBarFail(prettyException("Discover Services Error:", e));
      snackBarKeyC.currentState?.removeCurrentSnackBar();
      snackBarKeyC.currentState?.showSnackBar(snackBar);
    }
  }

  List<Widget> _buildServiceTiles(BuildContext context, List<BluetoothService> services) {

    List<BluetoothCharacteristic>? serviceTest; 
    for (var s in services) {
      //print(s.characteristics);
      for(var c in s.characteristics){
        print(c.characteristicUuid);
        //List<BluetoothCharacteristic > service_test =;
      }
      serviceTest = s.characteristics.where(
        (element) {
          if(element.characteristicUuid.toString() == "32550a96-8bf4-11e7-bb31-be2e44b06b34"){
            print(element.characteristicUuid.toString());
            element.write([0x1,0x3,0x4], withoutResponse: element.properties.writeWithoutResponse);
            return true;
          }
          return false;
        }
        ).toList();
    }
    print(serviceTest!.length);
    return services
        .map(
          (s) => ServiceTile(
            service: s,
            characteristicTiles: s.characteristics
                .map(
                  (c) => CharacteristicTile(
                    characteristic: c,
                    onReadPressed: () async {
                      try {
                        await c.read();
                        final snackBar = snackBarGood("Read: Success");
                        snackBarKeyC.currentState?.removeCurrentSnackBar();
                        snackBarKeyC.currentState?.showSnackBar(snackBar);
                      } catch (e) {
                        final snackBar = snackBarFail(prettyException("Read Error:", e));
                        snackBarKeyC.currentState?.removeCurrentSnackBar();
                        snackBarKeyC.currentState?.showSnackBar(snackBar);
                      }
                    },
                    onWritePressed: () async {
                      try {
                        await c.write([0x1,0x2], withoutResponse: c.properties.writeWithoutResponse);
                        final snackBar = snackBarGood("Write: Success");
                        print("${c.characteristicUuid}");
                        snackBarKeyC.currentState?.removeCurrentSnackBar();
                        snackBarKeyC.currentState?.showSnackBar(snackBar);
                        if (c.properties.read) {
                          await c.read();
                        }
                      } catch (e) {
                        final snackBar = snackBarFail(prettyException("Write Error:", e));
                        snackBarKeyC.currentState?.removeCurrentSnackBar();
                        snackBarKeyC.currentState?.showSnackBar(snackBar);
                      }
                    },
                    onNotificationPressed: () async {
                      try {
                        String op = c.isNotifying == false ? "Subscribe" : "Unubscribe";
                        await c.setNotifyValue(c.isNotifying == false);
                        final snackBar = snackBarGood("$op : Success");
                        snackBarKeyC.currentState?.removeCurrentSnackBar();
                        snackBarKeyC.currentState?.showSnackBar(snackBar);
                        if (c.properties.read) {
                          await c.read();
                        }
                      } catch (e) {
                        final snackBar = snackBarFail(prettyException("Subscribe Error:", e));
                        snackBarKeyC.currentState?.removeCurrentSnackBar();
                        snackBarKeyC.currentState?.showSnackBar(snackBar);
                      }
                    },
                    descriptorTiles: c.descriptors
                        .map(
                          (d) => DescriptorTile(
                            descriptor: d,
                            onReadPressed: () async {
                              try {
                                await d.read();
                                final snackBar = snackBarGood("Read: Success");
                                snackBarKeyC.currentState?.removeCurrentSnackBar();
                                snackBarKeyC.currentState?.showSnackBar(snackBar);
                              } catch (e) {
                                final snackBar = snackBarFail(prettyException("Read Error:", e));
                                snackBarKeyC.currentState?.removeCurrentSnackBar();
                                snackBarKeyC.currentState?.showSnackBar(snackBar);
                              }
                            },
                            onWritePressed: () async {
                              try {
                                await d.write(_getRandomBytes());
                                final snackBar = snackBarGood("Write: Success");
                                snackBarKeyC.currentState?.removeCurrentSnackBar();
                                snackBarKeyC.currentState?.showSnackBar(snackBar);
                              } catch (e) {
                                final snackBar = snackBarFail(prettyException("Write Error:", e));
                                snackBarKeyC.currentState?.removeCurrentSnackBar();
                                snackBarKeyC.currentState?.showSnackBar(snackBar);
                              }
                            },
                          ),
                        )
                        .toList(),
                  ),
                )
                .toList(),
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: snackBarKeyC,
      child: Scaffold(
        appBar: AppBar(
          title: Text(device.localName),
          actions: <Widget>[
            StreamBuilder<BluetoothConnectionState>(
              stream: device.connectionState,
              initialData: BluetoothConnectionState.connecting,
              builder: (c, snapshot) {
                VoidCallback? onPressed;
                String text;
                switch (snapshot.data) {
                  case BluetoothConnectionState.connected:
                    onPressed = () async {
                      isConnectingOrDisconnecting[device.remoteId] ??= ValueNotifier(true);
                      isConnectingOrDisconnecting[device.remoteId]!.value = true;
                      try {
                        await device.disconnect();
                        final snackBar = snackBarGood("Disconnect: Success");
                        snackBarKeyC.currentState?.removeCurrentSnackBar();
                        snackBarKeyC.currentState?.showSnackBar(snackBar);
                      } catch (e) {
                        final snackBar = snackBarFail(prettyException("Disconnect Error:", e));
                        snackBarKeyC.currentState?.removeCurrentSnackBar();
                        snackBarKeyC.currentState?.showSnackBar(snackBar);
                      }
                      isConnectingOrDisconnecting[device.remoteId] ??= ValueNotifier(false);
                      isConnectingOrDisconnecting[device.remoteId]!.value = false;
                    };
                    text = 'DESCONECTAR';
                    break;
                  case BluetoothConnectionState.disconnected:
                    onPressed = () async {
                      isConnectingOrDisconnecting[device.remoteId] ??= ValueNotifier(true);
                      isConnectingOrDisconnecting[device.remoteId]!.value = true;
                      try {
                        await device.connect(timeout: const Duration(seconds: 35));
                        final snackBar = snackBarGood("Connect: Success");
                        snackBarKeyC.currentState?.removeCurrentSnackBar();
                        snackBarKeyC.currentState?.showSnackBar(snackBar);
                      } catch (e) {
                        final snackBar = snackBarFail(prettyException("Connect Error:", e));
                        snackBarKeyC.currentState?.removeCurrentSnackBar();
                        snackBarKeyC.currentState?.showSnackBar(snackBar);
                      }
                      isConnectingOrDisconnecting[device.remoteId] ??= ValueNotifier(false);
                      isConnectingOrDisconnecting[device.remoteId]!.value = false;
                    };
                    text = 'CONECTAR';
                    break;
                  default:
                    onPressed = null;
                    text = snapshot.data.toString().split(".").last.toUpperCase();
                    break;
                }
                return ValueListenableBuilder<bool>(
                    valueListenable: isConnectingOrDisconnecting[device.remoteId]!,
                    builder: (context, value, child) {
                      isConnectingOrDisconnecting[device.remoteId] ??= ValueNotifier(false);
                      if (isConnectingOrDisconnecting[device.remoteId]!.value == true) {
                        // Show spinner when connecting or disconnecting
                        return const Padding(
                          padding: EdgeInsets.all(14.0),
                          child: AspectRatio(
                            aspectRatio: 1.0,
                            child: CircularProgressIndicator(
                              backgroundColor: Colors.black12,
                              color: Colors.black26,
                            ),
                          ),
                        );
                      } else {
                        return TextButton(
                            onPressed: onPressed,
                            child: Text(
                              text,
                              style: const TextStyle(
                                color: Color.fromARGB(255, 203, 54, 54)
                              ),
                              //style: Theme.of(context).primaryTextTheme.labelLarge?.copyWith(color: const Color.fromARGB(255, 9, 0, 65)),
                            ));
                      }
                    });
              },
            ),
          ],
        ),
        body: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              StreamBuilder<BluetoothConnectionState>(
                stream: device.connectionState,
                initialData: BluetoothConnectionState.connecting,
                builder: (c, snapshot) => Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text('${device.remoteId}'),
                    ),
                    ListTile(
                      leading: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          snapshot.data == BluetoothConnectionState.connected
                              ? const Icon(Icons.bluetooth_connected)
                              : const Icon(Icons.bluetooth_disabled),
                          snapshot.data == BluetoothConnectionState.connected
                              ? StreamBuilder<int>(
                                  stream: rssiStream(maxItems: 1),
                                  builder: (context, snapshot) {
                                    return Text(snapshot.hasData ? '${snapshot.data}dBm' : '',
                                        style: Theme.of(context).textTheme.bodySmall);
                                  })
                              : Text('', style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                      title: Text('Device is ${snapshot.data.toString().split('.')[1]}.'),
                      trailing: StreamBuilder<bool>(
                        stream: device.isDiscoveringServices,
                        initialData: false,
                        builder: (c, snapshot) => IndexedStack(
                          index: (snapshot.data ?? false) ? 1 : 0,
                          children: <Widget>[
                            TextButton(
                              child: const Text("Get Services"),
                              onPressed: () async {
                                try {
                                  await device.discoverServices();
                                  final snackBar = snackBarGood("Discover Services: Success");
                                  snackBarKeyC.currentState?.removeCurrentSnackBar();
                                  snackBarKeyC.currentState?.showSnackBar(snackBar);
                                } catch (e) {
                                  final snackBar = snackBarFail(prettyException("Discover Services Error:", e));
                                  snackBarKeyC.currentState?.removeCurrentSnackBar();
                                  snackBarKeyC.currentState?.showSnackBar(snackBar);
                                }
                              },
                            ),
                            const IconButton(
                              icon: SizedBox(
                                width: 18.0,
                                height: 18.0,
                                child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation(Colors.grey),
                                ),
                              ),
                              onPressed: null,
                            )
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              StreamBuilder<int>(
                stream: device.mtu,
                initialData: 0,
                builder: (c, snapshot) => ListTile(
                  title: const Text('MTU Size'),
                  subtitle: Text('${snapshot.data} bytes'),
                  trailing: IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () async {
                        try {
                          await device.requestMtu(50);
                          final snackBar = snackBarGood("Request Mtu: Success");
                          snackBarKeyC.currentState?.removeCurrentSnackBar();
                          snackBarKeyC.currentState?.showSnackBar(snackBar);
                        } catch (e) {
                          final snackBar = snackBarFail(prettyException("Change Mtu Error:", e));
                          snackBarKeyC.currentState?.removeCurrentSnackBar();
                          snackBarKeyC.currentState?.showSnackBar(snackBar);
                        }
                      }),
                ),
              ),
              StreamBuilder<List<BluetoothService>>(
                stream: device.servicesStream,
                initialData: const [],
                builder: (c, snapshot) {
                  return Column(
                    children: _buildServiceTiles(context, snapshot.data ?? []),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Stream<int> rssiStream({Duration frequency = const Duration(seconds: 5), int? maxItems}) async* {
    var isConnected = true;
    final subscription = device.connectionState.listen((v) {
      isConnected = v == BluetoothConnectionState.connected;
    });
    int i = 0;
    while (isConnected && (maxItems == null || i < maxItems)) {
      try {
        yield await device.readRssi();
      } catch (e) {
        print("Error reading RSSI: $e");
        break;
      }
      await Future.delayed(frequency);
      i++;
    }
    // Device disconnected, stopping RSSI stream
    subscription.cancel();
  }
}

String prettyException(String prefix, dynamic e) {
  if (e is FlutterBluePlusException) {
    return "$prefix ${e.description}";
  } else if (e is PlatformException) {
    return "$prefix ${e.message}";
  }
  return prefix + e.toString();
}
