import 'dart:io';
import 'package:inzx/services/ytmusic_api_service.dart';

void main() async {
  print('Starting search test...');
  final service = InnerTubeService();
  try {
    final result = await service.search('test');
    print('Query: test');
    print('Total items: ${result.totalCount}');
    print('Tracks: ${result.tracks.length}');
    print('Albums: ${result.albums.length}');
    
    final items = result.toList();
    for (var i = 0; i < items.length && i < 5; i++) {
      print('Item $i: ${items[i].title} (${items[i].type})');
    }
  } catch (e, stack) {
    print('Error: $e');
    print(stack);
  }
  exit(0);
}
