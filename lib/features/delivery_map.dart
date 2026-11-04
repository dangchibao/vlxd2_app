import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

class DeliveryMap extends StatelessWidget {
  final Map<String, dynamic> data;
  const DeliveryMap({super.key, required this.data});
  @override
  Widget build(BuildContext context) {
    final point = LatLng(
      (data['latE6'] as int) / 1000000,
      (data['lngE6'] as int) / 1000000,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Điểm giao hàng')),
      body: Column(
        children: [
          ListTile(
            title: Text(data['address'] as String? ?? ''),
            subtitle: Text('${point.latitude}, ${point.longitude}'),
            trailing: OutlinedButton(
              onPressed: () async {
                final opened = await launchUrl(
                  Uri.https('www.google.com', '/maps/dir/', {
                    'api': '1',
                    'destination': '${point.latitude},${point.longitude}',
                  }),
                  mode: LaunchMode.externalApplication,
                );
                if (!opened && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Không mở được ứng dụng chỉ đường.'),
                    ),
                  );
                }
              },
              child: const Text('Chỉ đường'),
            ),
          ),
          Expanded(
            child: FlutterMap(
              options: MapOptions(initialCenter: point, initialZoom: 15),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'vn.bayhai.vlxd',
                  maxZoom: 19,
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: point,
                      child: const Icon(
                        Icons.location_pin,
                        color: Colors.red,
                        size: 44,
                      ),
                    ),
                  ],
                ),
                RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution(
                      'OpenStreetMap contributors',
                      onTap: () => launchUrl(
                        Uri.https('www.openstreetmap.org', '/copyright'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
