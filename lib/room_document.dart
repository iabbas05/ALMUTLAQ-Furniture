import 'dart:convert';

import 'room_geometry.dart';
import 'room_drawing.dart';

/// Shared with the staff service and Unity. Customer identity never enters this document.
class RoomDocument {
  const RoomDocument(
    this.width,
    this.length,
    this.height,
    this.openings,
    this.pieces,
  );
  final int width, length, height;
  final List<Opening> openings;
  final List<RoomPiece> pieces;

  Map<String, dynamic> toWire() {
    validate();
    return {
      'schemaVersion': 2,
      'unit': 'm',
      'room': {
        'width': width / 100,
        'depth': length / 100,
        'height': height / 100,
      },
      'openings': [
        for (final o in openings)
          {
            'wall': o.wall.name,
            'kind': o.window ? 'window' : 'door',
            'offset': o.offset / 100,
            'width': o.width / 100,
            'sill': o.sill / 100,
            'height': o.height / 100,
            'reverse': o.reverse,
          },
      ],
      'items': [
        for (var i = 0; i < pieces.length; i++)
          {
            'instanceId': 'piece-$i',
            'productId': pieces[i].product.productId,
            'position': {'x': pieces[i].x / 100, 'z': pieces[i].y / 100},
            'rotationY': pieces[i].angle,
            if (pieces[i].modelVersion != null)
              'modelVersion': pieces[i].modelVersion,
          },
      ],
    };
  }

  void validate() {
    if (width < 100 ||
        width > 2500 ||
        length < 100 ||
        length > 2500 ||
        height < 200 ||
        height > 1000 ||
        pieces.length > 50 ||
        openings.length > 32) {
      throw const FormatException('Invalid room dimensions or item count.');
    }
    for (var i = 0; i < openings.length; i++) {
      final o = openings[i];
      if (!o.fits(width, length, height) || (!o.window && o.sill != 0)) {
        throw const FormatException('Invalid opening.');
      }
      for (var j = 0; j < i; j++) {
        final a = openings[j];
        if (a.wall == o.wall &&
            a.offset < o.offset + o.width &&
            o.offset < a.offset + a.width) {
          throw const FormatException('Openings overlap.');
        }
      }
    }
    for (final p in pieces) {
      if (!p.x.isFinite || !p.y.isFinite || !p.fits(width, length, height)) {
        throw const FormatException('A piece extends outside the room.');
      }
    }
  }

  static RoomDocument fromWire(Map<String, dynamic> data) {
    if (data['schemaVersion'] != 2 || data['unit'] != 'm') {
      throw const FormatException('Unsupported room document.');
    }
    int cm(dynamic value) {
      if (value is! num || !value.isFinite || value < 0 || value > 25) {
        throw const FormatException('Invalid measurement.');
      }
      return (value * 100).round();
    }

    final room = data['room'] as Map;
    final cuts = (data['openings'] as List).map((raw) {
      final row = raw as Map;
      if (row['kind'] != 'window' && row['kind'] != 'door') {
        throw const FormatException('Unknown opening.');
      }
      return Opening(
        Wall.values.byName(row['wall'] as String),
        cm(row['offset']),
        cm(row['width']),
        row['kind'] == 'window',
        cm(row['sill']),
        cm(row['height']),
        row['reverse'] as bool,
      );
    }).toList();
    final ids = <String>{};
    final items = (data['items'] as List).map((raw) {
      final row = raw as Map;
      if (row['instanceId'] is! String ||
          !ids.add(row['instanceId'] as String)) {
        throw const FormatException('Duplicate item.');
      }
      final product = furnitureSizes.firstWhere(
        (p) => p.productId == row['productId'],
      );
      final position = row['position'] as Map;
      final rotation = row['rotationY'];
      if (rotation is! num ||
          !rotation.isFinite ||
          rotation != rotation.roundToDouble()) {
        throw const FormatException('Invalid rotation.');
      }
      return RoomPiece(
        product,
        cm(position['x']).toDouble(),
        cm(position['z']).toDouble(),
        rotation.toInt() % 360,
        modelVersion: row['modelVersion'] as String?,
      );
    }).toList();
    final result = RoomDocument(
      cm(room['width']),
      cm(room['depth']),
      cm(room['height']),
      cuts,
      items,
    );
    result.validate();
    return result;
  }

  String encode() => jsonEncode(toWire());
}
