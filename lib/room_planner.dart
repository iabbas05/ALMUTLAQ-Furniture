import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'room_geometry.dart';
import 'room_drawing.dart';
import 'room_orbit.dart';
import 'room_document.dart';
import 'room_link.dart';
import 'room_scan.dart';

class RoomPlanner extends StatefulWidget {
  const RoomPlanner(this.preferences, this.arabic, {super.key});
  final SharedPreferences preferences;
  final bool arabic;

  @override
  State<RoomPlanner> createState() => RoomPlannerState();
}

class RoomPlannerState extends State<RoomPlanner> {
  void addProduct(FurnitureSize product) {
    final item = RoomPiece(product, width / 2, length / 2, 0);
    if (pieces.length >= 50 || !item.fits(width, length, height)) {
      message(
        'القطعة ما تناسب الغرفة، أو وصلت حد القطع.',
        'This piece does not fit, or the item limit was reached.',
      );
      return;
    }
    remember();
    setState(() {
      pieces.add(item);
      selected = pieces.length - 1;
    });
  }

  final widthInput = TextEditingController(text: '400');
  final lengthInput = TextEditingController(text: '500');
  final heightInput = TextEditingController(text: '280');
  int width = 400, length = 500, height = 280, selected = 0;
  bool perspective = true, metres = false;
  var openings = <Opening>[
    const Opening(Wall.top, 140, 120, true, 95, 110, false),
    const Opening(Wall.left, 360, 90, false, 0, 210, false),
  ];
  final undo = <String>[], redo = <String>[];
  String layoutName = '';
  RoomDocument get document =>
      RoomDocument(width, length, height, openings, pieces);
  void remember() {
    undo.add(plan());
    if (undo.length > 30) undo.removeAt(0);
    redo.clear();
  }

  void stepBack(bool forward) {
    final from = forward ? redo : undo, to = forward ? undo : redo;
    if (from.isEmpty) return;
    to.add(plan());
    restore(from.removeLast());
  }

  Future<void> scanRoom() async {
    final result = await RoomScan.capture(context, widget.arabic);
    if (!mounted || result == null) return;
    if (result['rectangular'] != true) {
      message(
        'شكل الغرفة يحتاج مراجعة يدوية. ما غيّرنا تصميمك إلى مستطيل تقريبي.',
        'This room needs manual review. Your design was not replaced by an approximate rectangle.',
      );
      return;
    }
    final dims = result['dimensions'] as Map?;
    if (dims == null) return;
    final w = ((dims['width'] as num) * 100).round();
    final d = ((dims['depth'] as num) * 100).round();
    final h = ((dims['height'] as num) * 100).round();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('راجع قياسات المسح', 'Review the scanned measurements')),
        content: Text(
          tr(
            'عرض ${w / 100} م، عمق ${d / 100} م، ارتفاع ${h / 100} م.\nأبعاد مقترحة تحتاج مراجعة بقياس فعلي قبل الشراء. حدد مواقع الأبواب والدرايش يدويًا.',
            'Width ${w / 100} m, depth ${d / 100} m, height ${h / 100} m.\nThese are draft measurements. Verify them before buying. Place doors and windows manually.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('استخدم القياسات', 'Use measurements')),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    widthInput.text = dimension(w);
    lengthInput.text = dimension(d);
    heightInput.text = dimension(h);
    updateRoom();
  }

  String get unit => metres ? tr('م', 'm') : tr('سم', 'cm');

  int? centimetres(String input) {
    final value = parseMeasurement(input, metres: metres);
    return value != null && value <= 2500 ? value.round() : null;
  }

  String dimension(num cm) =>
      metres ? (cm / 100).toStringAsFixed(2) : cm.round().toString();
  void updateFields() {
    widthInput.text = dimension(width);
    lengthInput.text = dimension(length);
    heightInput.text = dimension(height);
  }

  String wallLabel(Wall wall) => switch (wall) {
    Wall.top => tr('الجدار العلوي', 'Top wall'),
    Wall.right => tr('الجدار اليمين', 'Right wall'),
    Wall.bottom => tr('الجدار السفلي', 'Bottom wall'),
    Wall.left => tr('الجدار اليسار', 'Left wall'),
  };

  Future<void> editOpening(bool window, {int? index}) async {
    final current = index == null ? null : openings[index];
    var wall = current?.wall ?? Wall.top;
    var reverse = current?.reverse ?? false;
    var offset = dimension(current?.offset ?? 0);
    var span = dimension(current?.width ?? 90);
    var sill = dimension(current?.sill ?? 90);
    var tall = dimension(current?.height ?? (window ? 100 : 210));
    String? error;
    final result = await showDialog<Opening>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, redraw) {
          Widget field(
            String label,
            String initial,
            ValueChanged<String> change,
          ) => TextFormField(
            initialValue: initial,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: label, suffixText: unit),
            onChanged: change,
          );
          return AlertDialog(
            title: Text(window ? tr('دريشة', 'Window') : tr('باب', 'Door')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButton<Wall>(
                    value: wall,
                    isExpanded: true,
                    items: [
                      for (final side in Wall.values)
                        DropdownMenuItem(
                          value: side,
                          child: Text(wallLabel(side)),
                        ),
                    ],
                    onChanged: (side) {
                      if (side != null) redraw(() => wall = side);
                    },
                  ),
                  field(
                    tr('البعد من بداية الجدار', 'Offset from wall start'),
                    offset,
                    (v) => offset = v,
                  ),
                  Text(
                    tr(
                      'قِس من اليسار أو من فوق حسب المخطط',
                      'Measure from the left or top end of the wall',
                    ),
                  ),
                  field(
                    tr('عرض الفتحة', 'Opening width'),
                    span,
                    (v) => span = v,
                  ),
                  field(
                    tr('ارتفاع الفتحة', 'Opening height'),
                    tall,
                    (v) => tall = v,
                  ),
                  if (window)
                    field(
                      tr('الارتفاع من الأرض', 'Sill height'),
                      sill,
                      (v) => sill = v,
                    ),
                  if (!window)
                    SwitchListTile(
                      title: Text(tr('اعكس جهة المفصلة', 'Reverse hinge')),
                      value: reverse,
                      onChanged: (v) => redraw(() => reverse = v),
                    ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr('إلغاء', 'Cancel')),
              ),
              FilledButton(
                onPressed: () {
                  final next = Opening(
                    wall,
                    centimetres(offset) ?? -1,
                    centimetres(span) ?? -1,
                    window,
                    window ? centimetres(sill) ?? -1 : 0,
                    centimetres(tall) ?? -1,
                    reverse,
                  );
                  final overlaps = openings.asMap().entries.any((entry) {
                    final o = entry.value;
                    return entry.key != index &&
                        o.wall == wall &&
                        next.offset < o.offset + o.width &&
                        o.offset < next.offset + next.width;
                  });
                  if (overlaps || !next.fits(width, length, height)) {
                    redraw(
                      () => error = tr(
                        'تأكد من المقاس ومكان الفتحة على الجدار.',
                        'The opening must fit the wall and stay clear of other openings.',
                      ),
                    );
                    return;
                  }
                  Navigator.pop(context, next);
                },
                child: Text(tr('حفظ', 'Save')),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted || result == null) return;
    remember();
    setState(() {
      if (index == null) {
        openings.add(result);
      } else {
        openings[index] = result;
      }
    });
  }

  Future<void> editPosition(RoomPiece piece) async {
    var x = dimension(piece.x), y = dimension(piece.y);
    String? error;
    final result = await showDialog<RoomPiece>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, redraw) {
          Widget field(
            String label,
            String value,
            ValueChanged<String> change,
          ) => TextFormField(
            initialValue: value,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: label, suffixText: unit),
            onChanged: change,
          );
          return AlertDialog(
            title: Text(tr('مكان مركز القطعة', 'Piece centre position')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                field(
                  tr('من الجدار اليسار', 'From the left wall'),
                  x,
                  (v) => x = v,
                ),
                field(
                  tr('من الجدار العلوي', 'From the top wall'),
                  y,
                  (v) => y = v,
                ),
                if (error != null) Text(error!),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr('إلغاء', 'Cancel')),
              ),
              FilledButton(
                onPressed: () {
                  final nextX = centimetres(x), nextY = centimetres(y);
                  if (nextX == null ||
                      nextY == null ||
                      nextX > width ||
                      nextY > length) {
                    redraw(
                      () => error = tr(
                        'خلّ مركز القطعة داخل الغرفة.',
                        'Keep the centre within the room.',
                      ),
                    );
                    return;
                  }
                  Navigator.pop(
                    context,
                    piece.move(nextX.toDouble(), nextY.toDouble()),
                  );
                },
                child: Text(tr('تطبيق', 'Apply')),
              ),
            ],
          );
        },
      ),
    );
    if (mounted && result != null) modify(result);
  }

  void pickPiece(Offset point, double scale) {
    for (var i = pieces.length - 1; i >= 0; i--) {
      final piece = pieces[i];
      final angle = piece.angle * math.pi / 180;
      final dx = point.dx / scale - piece.x, dy = point.dy / scale - piece.y;
      final x = dx * math.cos(angle) + dy * math.sin(angle);
      final y = -dx * math.sin(angle) + dy * math.cos(angle);
      if (x.abs() <= piece.product.width / 2 &&
          y.abs() <= piece.product.depth / 2) {
        setState(() => selected = i);
        return;
      }
    }
  }

  String? saved;
  var pieces = [RoomPiece(furnitureSizes.first, 200, 125, 0)];

  String tr(String ar, String en) => widget.arabic ? ar : en;
  String name(FurnitureSize product) => widget.arabic ? product.ar : product.en;
  RoomPiece? get active => pieces.isEmpty ? null : pieces[selected];

  @override
  void dispose() {
    widthInput.dispose();
    lengthInput.dispose();
    heightInput.dispose();
    super.dispose();
  }

  void message(String ar, String en) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr(ar, en))));

  void updateRoom() {
    final w = centimetres(widthInput.text);
    final l = centimetres(lengthInput.text);
    final h = centimetres(heightInput.text);
    if (w == null ||
        l == null ||
        h == null ||
        w < 100 ||
        l < 100 ||
        h < 200 ||
        h > 1000) {
      message(
        'أدخل أبعاداً من ١٠٠ إلى ٢٥٠٠ سم أو ما يعادلها بالمتر.',
        'Enter dimensions between 100 and 2500 cm, or their equivalent in metres.',
      );
      return;
    }
    if (openings.any((o) => !o.fits(w, l, h))) {
      message(
        'عدّل الفتحات قبل تصغير الغرفة.',
        'Adjust the openings before shrinking the room.',
      );
      return;
    }
    if (pieces.any((p) => !p.fits(w, l, h))) {
      message(
        'حرّك القطع أو احذف القطعة الكبيرة قبل تصغير الغرفة.',
        'Move the pieces or remove an oversized item before shrinking the room.',
      );
      return;
    }
    remember();
    setState(() {
      width = w;
      length = l;
      height = h;
      updateFields();
    });
  }

  void modify(RoomPiece next, {bool record = true}) {
    final valid = next.contained(width, length);
    if (valid == null || valid.product.height > height) {
      message(
        'القطعة ما تناسب قياسات الغرفة بهالزاوية.',
        'This piece does not fit the room at this angle.',
      );
      return;
    }
    if (record) remember();
    setState(() => pieces[selected] = valid);
  }

  String plan() => jsonEncode({
    'version': 1,
    if (layoutName.isNotEmpty) 'name': layoutName,
    'unit': 'cm',
    'width': width,
    'length': length,
    'height': height,
    'openings': openings.map((o) => o.toJson()).toList(),
    'pieces': [for (final piece in pieces) piece.toJson()],
  });

  List<String> get layouts =>
      widget.preferences.getStringList('room-layouts-v1') ?? [];

  Future<void> save() async {
    final input = TextEditingController(text: layoutName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('احفظ تصميمك', 'Save your design')),
        content: TextField(
          controller: input,
          maxLength: 80,
          decoration: InputDecoration(
            labelText: tr('اسم التصميم', 'Design name'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text.trim()),
            child: Text(tr('حفظ', 'Save')),
          ),
        ],
      ),
    );
    input.dispose();
    if (!mounted || name == null) return;
    layoutName = name.isEmpty ? tr('غرفتي', 'My room') : name;
    final value = plan();
    final list = layouts;
    if (list.length >= 100 && !list.contains(value)) {
      message(
        'وصلت ١٠٠ تصميم محفوظ. احتفظ بنسخة قبل إضافة تصميم جديد.',
        '100 designs are saved. Export a copy before adding another.',
      );
      return;
    }
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
      final h = data['height'] as int? ?? 280;
      final cuts = (data['openings'] as List? ?? [])
          .map((entry) => Opening.fromJson(entry as Map<String, dynamic>))
          .toList();
      if (data['version'] != 1 ||
          data['unit'] != 'cm' ||
          w < 100 ||
          l < 100 ||
          w > 2500 ||
          l > 2500 ||
          h < 200 ||
          h > 1000 ||
          cuts.any((o) => !o.fits(w, l, h))) {
        throw const FormatException('Invalid room');
      }
      final items = (data['pieces'] as List)
          .map((entry) => RoomPiece.fromJson(entry as Map<String, dynamic>))
          .toList();
      setState(() {
        width = w;
        length = l;
        height = h;
        openings = cuts;
        updateFields();
        pieces = items;
        selected = 0;
        saved = value;
        layoutName = data['name'] as String? ?? '';
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
        Text(
          tr(
            'قياسات حقيقية، وتصميم تحفظه وتكمل عليه.',
            'Measured furniture, in a design you can save and revisit.',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            IconButton(
              tooltip: tr('تراجع', 'Undo'),
              onPressed: undo.isEmpty ? null : () => stepBack(false),
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: tr('إعادة', 'Redo'),
              onPressed: redo.isEmpty ? null : () => stepBack(true),
              icon: const Icon(Icons.redo),
            ),
            if (RoomScan.offered)
              OutlinedButton.icon(
                onPressed: scanRoom,
                icon: const Icon(Icons.document_scanner_outlined),
                label: Text(tr('مسح الغرفة', 'Scan room')),
              ),
            ChoiceChip(
              label: Text(tr('مخطط', 'Plan')),
              selected: !perspective,
              onSelected: (_) => setState(() => perspective = false),
            ),
            ChoiceChip(
              label: Text(tr('منظور 3D', '3D view')),
              selected: perspective,
              onSelected: (_) => setState(() => perspective = true),
            ),
            TextButton(
              onPressed: () => setState(() {
                metres = !metres;
                updateFields();
              }),
              child: Text(
                metres
                    ? tr('عرض بالسم', 'Show cm')
                    : tr('عرض بالمتر', 'Show metres'),
              ),
            ),
          ],
        ),
        Row(
          children: [
            for (final (controller, label) in [
              (widthInput, tr('العرض', 'Width')),
              (lengthInput, tr('الطول', 'Length')),
              (heightInput, tr('الارتفاع', 'Height')),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: label,
                      suffixText: unit,
                    ),
                  ),
                ),
              ),
          ],
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            onPressed: updateRoom,
            child: Text(tr('تطبيق القياسات', 'Apply dimensions')),
          ),
        ),
        if (perspective)
          RoomOrbit(
            width: width,
            length: length,
            height: height,
            openings: openings,
            pieces: pieces,
            arabic: widget.arabic,
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final scale = math.min(
                constraints.maxWidth / width,
                295 / length,
              );
              return Center(
                child: GestureDetector(
                  onTapDown: (event) => pickPiece(event.localPosition, scale),
                  onPanStart: (event) {
                    pickPiece(event.localPosition, scale);
                    if (active != null) remember();
                  },
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
                            record: false,
                          );
                        },
                  child: CustomPaint(
                    size: Size(width * scale, length * scale),
                    painter: RoomDrawing(
                      pieces,
                      openings,
                      selected,
                      width,
                      length,
                    ),
                  ),
                ),
              );
            },
          ),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: () => editOpening(false),
              icon: const Icon(Icons.add),
              label: Text(tr('أضف باب', 'Add door')),
            ),
            TextButton.icon(
              onPressed: () => editOpening(true),
              icon: const Icon(Icons.add),
              label: Text(tr('أضف دريشة', 'Add window')),
            ),
          ],
        ),
        for (var i = 0; i < openings.length; i++)
          ListTile(
            dense: true,
            onTap: () => editOpening(openings[i].window, index: i),
            title: Text(
              openings[i].window ? tr('دريشة', 'Window') : tr('باب', 'Door'),
            ),
            subtitle: Text(wallLabel(openings[i].wall)),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                remember();
                setState(() => openings.removeAt(i));
              },
            ),
          ),
        if (item != null) ...[
          TextButton.icon(
            onPressed: () => editPosition(item),
            icon: const Icon(Icons.straighten),
            label: Text(
              tr('حدد المكان بالقياس', 'Set position by measurement'),
            ),
          ),
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
                onPressed: () {
                  remember();
                  setState(() {
                    pieces.removeAt(selected);
                    selected = 0;
                  });
                },
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
          if (outside && gaps != null)
            Text(
              tr(
                'القطعة متجاوزة الجدار بـ ${dimension(-gaps.reduce(math.min))} $unit',
                'Piece extends past a wall by ${dimension(-gaps.reduce(math.min))} $unit',
              ),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            )
          else if (gaps != null)
            Wrap(
              spacing: 10,
              children: [
                for (final (i, side) in [
                  (0, tr('يسار', 'Left')),
                  (1, tr('فوق', 'Top')),
                  (2, tr('يمين', 'Right')),
                  (3, tr('تحت', 'Bottom')),
                ])
                  Text('$side ${dimension(math.max(0, gaps[i]))} $unit'),
              ],
            ),
          if (collision)
            Text(
              tr('القطعة تتداخل مع قطعة ثانية', 'Piece overlaps another item'),
            ),
        ],
        const SizedBox(height: 12),
        Text(
          tr('أثاث جاهز للمعاينة', 'Furniture ready to preview'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          tr(
            'المجسمات معاد بناؤها بأبعاد الموقع، وتحتاج اعتماد الشكل والقماش من المصنع.',
            'Models are reconstructed to the website dimensions. Shape and fabric need manufacturer approval.',
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final p in furnitureSizes)
              ActionChip(
                label: Text(name(p)),
                onPressed: () {
                  final next = RoomPiece(p, width / 2, length / 2, 0);
                  if (pieces.length >= 50 ||
                      !next.fits(width, length, height)) {
                    message(
                      'القطعة ما تناسب الغرفة، أو وصلت حد القطع.',
                      'This piece does not fit, or the item limit was reached.',
                    );
                    return;
                  }
                  remember();
                  setState(() {
                    pieces.add(next);
                    selected = pieces.length - 1;
                  });
                },
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
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () async {
            try {
              await Clipboard.setData(ClipboardData(text: document.encode()));
              if (mounted)
                message(
                  'تم نسخ ملف الغرفة. تقدر تلصقه في لوحة الموظف.',
                  'Room document copied. Paste it into the staff panel.',
                );
            } catch (_) {
              if (mounted)
                message(
                  'راجع القطع والفتحات قبل التصدير.',
                  'Check furniture and openings before exporting.',
                );
            }
          },
          icon: const Icon(Icons.copy),
          label: Text(tr('نسخ ملف الغرفة', 'Copy room document')),
        ),
        RoomLinkPanel(
          preferences: widget.preferences,
          arabic: widget.arabic,
          document: () => document,
        ),
      ],
    );
  }
}
