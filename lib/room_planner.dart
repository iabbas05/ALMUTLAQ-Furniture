import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'room_geometry.dart';

class RoomPlanner extends StatefulWidget {
  const RoomPlanner(this.preferences, this.arabic, {super.key});
  final SharedPreferences preferences;
  final bool arabic;

  @override
  State<RoomPlanner> createState() => _RoomPlannerState();
}

class _RoomPlannerState extends State<RoomPlanner> {
  final widthInput = TextEditingController(text: '400');
  final lengthInput = TextEditingController(text: '500');
  int width = 400, length = 500, selected = 0;
  String? saved;
  var pieces = [RoomPiece(furnitureSizes.first, 200, 125, 0)];

  String tr(String ar, String en) => widget.arabic ? ar : en;
  String name(FurnitureSize product) => widget.arabic ? product.ar : product.en;
  RoomPiece? get active => pieces.isEmpty ? null : pieces[selected];

  @override
  void dispose() {
    widthInput.dispose();
    lengthInput.dispose();
    super.dispose();
  }

  void message(String ar, String en) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr(ar, en))));

  void updateRoom() {
    final w = int.tryParse(widthInput.text.trim());
    final l = int.tryParse(lengthInput.text.trim());
    if (w == null || l == null || w < 100 || l < 100 || w > 2500 || l > 2500) {
      message(
        'أدخل مقاس من ١٠٠ إلى ٢٥٠٠ سم',
        'Enter dimensions from 100 to 2500 cm.',
      );
      return;
    }
    setState(() {
      width = w;
      length = l;
    });
  }

  void modify(RoomPiece next) => setState(() => pieces[selected] = next);

  String plan() => jsonEncode({
    'version': 1,
    'unit': 'cm',
    'width': width,
    'length': length,
    'pieces': [for (final piece in pieces) piece.toJson()],
  });

  List<String> get layouts =>
      widget.preferences.getStringList('room-layouts-v1') ?? [];

  Future<void> save() async {
    final value = plan();
    final list = layouts;
    if (!list.contains(value)) {
      final ok = await widget.preferences.setStringList('room-layouts-v1', [
        value,
        ...list,
      ]);
      if (!mounted) return;
      if (!ok) {
        message('تعذّر الحفظ', 'Could not save layout.');
        return;
      }
    }
    if (!mounted) return;
    setState(() => saved = value);
    message('انحفظ التصميم على الجهاز', 'Layout saved on this device.');
  }

  void restore(String value) {
    try {
      final data = jsonDecode(value) as Map<String, dynamic>;
      final w = data['width'] as int;
      final l = data['length'] as int;
      if (data['version'] != 1 ||
          data['unit'] != 'cm' ||
          w < 100 ||
          l < 100 ||
          w > 2500 ||
          l > 2500)
        throw const FormatException('Invalid room');
      final items = (data['pieces'] as List)
          .map((entry) => RoomPiece.fromJson(entry as Map<String, dynamic>))
          .toList();
      setState(() {
        width = w;
        length = l;
        widthInput.text = '$w';
        lengthInput.text = '$l';
        pieces = items;
        selected = 0;
        saved = value;
      });
    } catch (_) {
      message('تعذّر فتح التصميم', 'Could not open the saved layout.');
    }
  }

  Future<void> copyPlan() async {
    final lines = <String>[
      tr('الغرفة: $width × $length سم', 'Room: $width × $length cm'),
      tr(
        'الاتجاهات حسب المخطط من فوق.',
        'Directions are relative to the top-down plan.',
      ),
      for (final piece in pieces)
        '${name(piece.product)} (${piece.product.sku}) · ${piece.angle}° · '
            '${tr('المركز من اليسار والأعلى', 'Centre from left and top')}: '
            '${piece.x.round()} × ${piece.y.round()} ${tr('سم', 'cm')}',
    ];
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (mounted) message('اننسخ مخطط التركيب', 'Installation layout copied.');
  }

  @override
  Widget build(BuildContext context) {
    final item = active;
    final gaps = item?.margins(width, length);
    final outside = gaps?.any((g) => g < -0.0001) ?? false;
    final collision =
        item != null &&
        pieces.asMap().entries.any(
          (e) => e.key != selected && item.overlaps(e.value),
        );
    final options = layouts;
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          tr('صمّم غرفتك', 'Design your room'),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        Text(tr('مخطط قياس من فوق بالسنتيمتر', 'Top-down plan in centimetres')),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: widthInput,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr('العرض', 'Width')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: lengthInput,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr('الطول', 'Length')),
              ),
            ),
            TextButton(
              onPressed: updateRoom,
              child: Text(tr('تطبيق', 'Apply')),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = math.min(constraints.maxWidth / width, 285 / length);
            return Center(
              child: Semantics(
                label: tr(
                  'اسحب القطعة المحددة لتحريكها',
                  'Drag to move the selected piece',
                ),
                child: GestureDetector(
                  onPanUpdate: item == null
                      ? null
                      : (event) {
                          final piece = active!;
                          modify(
                            piece.move(
                              (piece.x + event.delta.dx / scale)
                                  .clamp(0, width)
                                  .toDouble(),
                              (piece.y + event.delta.dy / scale)
                                  .clamp(0, length)
                                  .toDouble(),
                            ),
                          );
                        },
                  child: CustomPaint(
                    size: Size(width * scale, length * scale),
                    painter: _RoomMap(pieces.toList(), selected, scale),
                  ),
                ),
              ),
            );
          },
        ),
        if (item != null) ...[
          DropdownButton<int>(
            isExpanded: true,
            value: selected,
            items: [
              for (var i = 0; i < pieces.length; i++)
                DropdownMenuItem(
                  value: i,
                  child: Text('${i + 1}. ${name(pieces[i].product)}'),
                ),
            ],
            onChanged: (i) {
              if (i != null) setState(() => selected = i);
            },
          ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => modify(item.turn()),
                child: Text(tr('دوّر ١٥°', 'Rotate 15°')),
              ),
              OutlinedButton(
                onPressed: () => setState(() {
                  pieces.removeAt(selected);
                  selected = 0;
                }),
                child: Text(tr('احذف', 'Remove')),
              ),
            ],
          ),
          Text(
            tr(
              'بدّل القطعة في نفس المكان والزاوية',
              'Swap in the same position and angle',
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final p in furnitureSizes.where(
                (p) => p.sku != item.product.sku,
              ))
                ActionChip(
                  label: Text(name(p)),
                  onPressed: () => modify(item.replace(p)),
                ),
            ],
          ),
          Text(
            tr('مقاس القطعة', 'Product size') +
                ' · ${item.product.width} × ${item.product.depth} × ${item.product.height} ${tr('سم', 'cm')}',
          ),
          Text(
            '${tr('يسار', 'Left')} ${gaps![0].round()} · '
            '${tr('فوق', 'Top')} ${gaps[1].round()} · '
            '${tr('يمين', 'Right')} ${gaps[2].round()} · '
            '${tr('تحت', 'Bottom')} ${gaps[3].round()} ${tr('سم', 'cm')}',
          ),
          if (outside)
            Text(
              tr('القطعة خارج حدود الغرفة', 'Piece crosses a room boundary'),
            ),
          if (collision)
            Text(
              tr('القطعة تتداخل مع قطعة ثانية', 'Piece overlaps another item'),
            ),
        ],
        const SizedBox(height: 12),
        Text(tr('أضف قطعة', 'Add a piece')),
        Wrap(
          spacing: 8,
          children: [
            for (final p in furnitureSizes)
              ActionChip(
                label: Text(name(p)),
                onPressed: () => setState(() {
                  pieces.add(RoomPiece(p, width / 2, length / 2, 0));
                  selected = pieces.length - 1;
                }),
              ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              onPressed: save,
              child: Text(tr('احفظ توزيع', 'Save layout')),
            ),
            OutlinedButton(
              onPressed: copyPlan,
              child: Text(tr('انسخ مخطط التركيب', 'Copy installation plan')),
            ),
          ],
        ),
        if (options.isNotEmpty)
          DropdownButton<String>(
            isExpanded: true,
            value: options.contains(saved) ? saved : null,
            hint: Text(tr('افتح توزيع محفوظ', 'Open a saved layout')),
            items: [
              for (var i = 0; i < options.length; i++)
                DropdownMenuItem(
                  value: options[i],
                  child: Text(tr('توزيع ${i + 1}', 'Layout ${i + 1}')),
                ),
            ],
            onChanged: (value) {
              if (value != null) restore(value);
            },
          ),
      ],
    );
  }
}

class _RoomMap extends CustomPainter {
  _RoomMap(this.pieces, this.selected, this.scale);
  final List<RoomPiece> pieces;
  final int selected;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(bounds, Paint()..color = const Color(0xffe6dfd0));
    canvas.save();
    canvas.clipRect(bounds);
    for (var i = 0; i < pieces.length; i++) {
      final path = Path()
        ..addPolygon([
          for (final p in pieces[i].corners) Offset(p.x * scale, p.y * scale),
        ], true);
      canvas.drawPath(
        path,
        Paint()
          ..color = i == selected
              ? const Color(0xff365348)
              : const Color(0xff9a8167),
      );
    }
    canvas.restore();
    canvas.drawRect(
      bounds,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xff514637),
    );
  }

  @override
  bool shouldRepaint(covariant _RoomMap oldDelegate) => true;
}
