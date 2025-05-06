import 'dart:async';
import 'dart:convert';
import 'package:image/image.dart' as img;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_map/models/data_point.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  MapPageState createState() => MapPageState();
}

const mqttServer =
    '9301d53c26cf418c9e3d433fa27b5dff.s1.eu.hivemq.cloud';
const mqttPort = 8884;
const clientId = 'tt-controller-mqtt-map';
const username = 'tt_controller';
const password = '1Idk*E2Dro%SX7@n8>wV';
const pubTopic = 'tt_controller/device/raw';

class MapPageState extends State<MapPage> {
  dynamic _client;
  Set<Marker> _markers = {};
  final Map<String, Marker> _markersMap = {};
  final Completer<GoogleMapController> _controller = Completer();
  final Map<String, LatLng> _locationsMap = {};

  bool? _dataReceived;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _disconnectMQTT();
    super.dispose();
  }

  Future<void> _setupMqttClient() async {
    final connMessage = MqttConnectMessage()
        .withClientIdentifier(
            'flutter_client_${DateTime.now().millisecondsSinceEpoch}')
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);

    // HiveMQ Web client configuration
    if (kIsWeb) {
      _client = MqttBrowserClient('wss://$mqttServer:$mqttPort/mqtt', clientId,
          maxConnectionAttempts: 3);
    }

    // HiveMQ Mobile client configuration
    if (!kIsWeb) {
      _client = MqttServerClient('wss://$mqttServer:$mqttPort/mqtt', clientId,
          maxConnectionAttempts: 3);
      _client?.useWebSocket = true;
    }

    // Set up websocket protocol
    _client.port = mqttPort;
    _client?.keepAlivePeriod = 20;
    _client?.onDisconnected = _onDisconnected;
    _client?.onConnected = _onConnected;
    _client?.onSubscribed = _onSubscribed;
    _client?.pongCallback = _pong;
    _client?.onSubscribeFail = _onSubscribeFail;
    _client?.onFailedConnectionAttempt = _onFailedConnectionAttempt;
    _client?.connectionMessage = connMessage;
  }

  Future<void> _connect() async {
    debugPrint('MQTT client connect');
    if (_client == null) {
      await _setupMqttClient();
    }
    try {
      _client?.connect(username, password);
    } catch (e) {
      _disconnect();
    }
  }

  void _disconnect() {
    debugPrint('MQTT client disconnected');
    if (_client != null &&
        _client?.connectionStatus!.state != MqttConnectionState.disconnected) {
      _client?.disconnect();
    }
  }

  void _onConnected() {
    debugPrint('MQTT client connected');
    _subscribe();
  }

  void _subscribe() {
    if (_client != null &&
        _client?.connectionStatus!.state == MqttConnectionState.connected) {
      _client?.subscribe('topic/data', MqttQos.atLeastOnce);
    }

    _client?.updates?.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      for (var msg in messages) {
        final recMess = messages[0].payload as MqttPublishMessage;
        final payload =
            MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
        debugPrint('${msg.topic}: $payload');
        try {
          final Map<String, dynamic> parsedJson = jsonDecode(payload);
          var dataPoint = DataPoint.fromJson(parsedJson);
          final double? lat = dataPoint.location?.lat;
          final double? lng = dataPoint.location?.lng;
          if (lat != null && lng != null) {
            setState(() {
              _dataReceived = true;
              _displayMarker(dataPoint);
            });
          }
        } catch (e) {
          debugPrint("error decoding $e");
        }
      }
    });
  }

  void _onDisconnected() {
    debugPrint('MQTT client disconnected');
  }

  void _onSubscribed(String topic) {
    debugPrint('Subscribed topic: $topic');
  }

  void _onSubscribeFail(String topic) {
    debugPrint('Failed to subscribe $topic');
  }

  void _onFailedConnectionAttempt(int attemptNumber) {
    debugPrint('MQTT Connection failed - attempt $attemptNumber');
  }

  void _pong() {
    debugPrint('Ping response client callback invoked');
  }

  void _disconnectMQTT() {
    _client?.disconnect();
  }

  Future<void> _animateCameraToLocation(LatLng point) async {
    final GoogleMapController controller = await _controller.future;
    controller.animateCamera(CameraUpdate.newLatLngZoom(point, 14));
  }

  Future<void> _displayMarker(DataPoint dataPoint) async {
    if (dataPoint.id != null) {
      var lastLocation = _locationsMap[dataPoint.id!];
      var newLocation = LatLng(dataPoint.location!.lat!, dataPoint.location!.lng!);
      _locationsMap[dataPoint.id!] = newLocation;
      var id = dataPoint.id!;
      var bearing = calculateBearing(lastLocation ?? newLocation, newLocation);
      _markersMap[id] = Marker(
        position: newLocation,
        markerId: MarkerId(id),
        icon: BitmapDescriptor.fromBytes(await _getRotatedMarkerIcon(dataPoint.type ?? 0, bearing)),
      );
    }
    setState(() {
      _markers = _markersMap.values.toSet();
    });
  }

  int calculateBearing(LatLng start, LatLng end) {
    double startLat = degreesToRadians(start.latitude);
    double startLng = degreesToRadians(start.longitude);
    double endLat = degreesToRadians(end.latitude);
    double endLng = degreesToRadians(end.longitude);
    double dLng = endLng - startLng;
    double y = math.sin(dLng) * math.cos(endLat);
    double x = math.cos(startLat) * math.sin(endLat) -
        math.sin(startLat) * math.cos(endLat) * math.cos(dLng);
    double bearingRadians = math.atan2(y, x);
    int bearingDegrees = radiansToDegrees(bearingRadians).round();
    return (bearingDegrees + 360) % 360; // Normalize to 0-360 degrees
  }

  double degreesToRadians(double degrees) {
    return degrees * math.pi / 180;
  }

  double radiansToDegrees(double radians) {
    return radians * 180 / math.pi;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MQTT Location Tracker'),
      ),
      body: Stack(
        children: [
          GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: const CameraPosition(
              target: LatLng(51.5072, 0.1276), // London
              zoom: 7,
            ),
            onMapCreated: (GoogleMapController controller) {
              _controller.complete(controller);
            },
            markers: _markers,
          ),
          Visibility(
              visible: _dataReceived != true,
              child: const Center(child: CircularProgressIndicator()))
        ],
      ),
    );
  }

  Future<Uint8List> _getRotatedMarkerIcon(int assetType, int angle) async {
    var width = 70;
    String imageAssetPath;
    switch (assetType) {
      case 1:
        imageAssetPath = 'assets/images/lorry.png';
        angle += 180;
        width = 100;
      case 2:
        imageAssetPath = 'assets/images/car_yellow.png';
        angle += 180;
        width = 60;
      case 3:
        imageAssetPath = 'assets/images/red_car.png';
        angle += 270;
      default:
        imageAssetPath = 'assets/images/car_blue.png';
    }

    ByteData data = await rootBundle.load(imageAssetPath);
    img.Image? originalImage = img.decodeImage(data.buffer.asUint8List());

    if (originalImage == null) {
      throw Exception('Failed to decode image');
    }

    img.Image rotatedImage = img.copyRotate(originalImage, angle: angle);
    img.Image resizedImage = img.copyResize(rotatedImage, width: width);

    Uint8List pngBytes = img.encodePng(resizedImage);
    return pngBytes;
  }
}
