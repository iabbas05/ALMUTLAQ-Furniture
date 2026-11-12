import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'catalogue.dart';
import 'room_planner.dart';
import 'room_geometry.dart';
import 'room_orbit.dart';
import 'app_updates.dart';
import 'product_ar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(FurnitureApp(await SharedPreferences.getInstance()));
}

const arUrl = String.fromEnvironment('SHOWROOM_AR_URL');

class FurnitureApp extends StatefulWidget {
  const FurnitureApp(this.preferences, {super.key, this.fetchOnline = true});
  final SharedPreferences preferences;
  final bool fetchOnline;
  @override
  State<FurnitureApp> createState() => _FurnitureAppState();
}

class _FurnitureAppState extends State<FurnitureApp> {
  late bool arabic;
  late Set<String> favourites;
  late Map<String, int> cart;
  int store = 0, tab = 0;
  String query = '';
  String? category;
  int visibleCount = 24;
  String sort = 'default';
  bool availableOnly = false, modelsOnly = false;
  final compare = <String>{};
  final plannerKey = GlobalKey<RoomPlannerState>();
  final cacheTimes = <int, DateTime>{};
  final client = CatalogueClient();
  final live = <int, List<Product>>{};
  final loading = <int>{};
  final failed = <int>{};

  Iterable<Product> products(int index) =>
      live[index] ?? sampleCatalogue.where((p) => p.store == index);

  Iterable<Product> get allProducts =>
      List.generate(stores.length, products).expand((items) => items);

  Future<void> loadCatalogue(int index) async {
    if (loading.contains(index)) return;
    setState(() {
      loading.add(index);
      failed.remove(index);
    });
    try {
      final products = await client.fetch(index);
      if (!mounted) return;
      setState(() {
        live[index] = products;
        cacheTimes[index] = DateTime.now();
        if (store == index &&
            !products.any((p) => p.categories.contains(category))) {
          category = null;
        }
      });
      await widget.preferences.setString(
        'catalogue-cache-$index',
        jsonEncode(products.map((p) => p.toCache()).toList()),
      );
      await widget.preferences.setString(
        'catalogue-time-$index',
        DateTime.now().toIso8601String(),
      );
    } catch (_) {
      if (mounted) setState(() => failed.add(index));
    } finally {
      if (mounted) setState(() => loading.remove(index));
    }
  }

  @override
  void initState() {
    super.initState();
    arabic = widget.preferences.getBool('arabic') ?? true;
    favourites = (widget.preferences.getStringList('favourites') ?? []).toSet();
    Map saved = {};
    try {
      saved = jsonDecode(widget.preferences.getString('cart') ?? '{}') as Map;
    } catch (_) {}
    for (var i = 0; i < stores.length; i++) {
      try {
        final raw = widget.preferences.getString('catalogue-cache-$i');
        if (raw != null)
          live[i] = (jsonDecode(raw) as List)
              .map((p) => Product.fromCache(p as Map<String, dynamic>))
              .toList();
        final time = DateTime.tryParse(
          widget.preferences.getString('catalogue-time-$i') ?? '',
        );
        if (time != null) cacheTimes[i] = time;
      } catch (_) {
        live.remove(i);
      }
    }
    cart = {
      for (final entry in saved.entries)
        if (entry.key is String &&
            entry.value is int &&
            (entry.value as int) > 0)
          entry.key as String: entry.value as int,
    };
    for (final p in sampleCatalogue) {
      if (favourites.remove(p.sku)) favourites.add(p.key);
      final quantity = cart.remove(p.sku);
      if (quantity != null) cart.putIfAbsent(p.key, () => quantity);
    }
    for (var i = 0; i < stores.length; i++) {
      if (widget.fetchOnline) loadCatalogue(i);
    }
  }

  String tr(String ar, String en) => arabic ? ar : en;
  String title(Product p) => arabic ? p.arabic : p.name;

  void toggleFavourite(Product p) {
    setState(() {
      if (!favourites.remove(p.key)) favourites.add(p.key);
    });
    widget.preferences.setStringList('favourites', favourites.toList());
  }

  void changeQuantity(Product p, int delta) {
    setState(() {
      final next = (cart[p.key] ?? 0) + delta;
      if (next <= 0) {
        cart.remove(p.key);
      } else {
        cart[p.key] = next;
      }
    });
    widget.preferences.setString('cart', jsonEncode(cart));
  }

  ArModel? arModel(Product p) => ProductAR.model(p.sku, p.store);

  String? bundledPhoto(Product p) => p.store == 0 && p.sku == '10_14_3'
      ? 'assets/london-sofa.jpg'
      : p.store == 0 && p.sku == '6_14_5'
      ? 'assets/london-chair.jpg'
      : null;

  Widget placeholder(Product p, double? height) => SizedBox(
    height: height,
    width: double.infinity,
    child: Center(
      child: Icon(
        arModel(p) != null ? Icons.view_in_ar : Icons.weekend_outlined,
        size: 44,
        color: const Color(0xffb7ab98),
      ),
    ),
  );

  Widget networkPhoto(Product p, String url, double? height, BoxFit fit) =>
      Image.network(
        url,
        height: height,
        width: double.infinity,
        fit: fit,
        errorBuilder: (_, _, _) => placeholder(p, height),
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : SizedBox(
                height: height,
                child: const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
      );

  Widget photo(Product p, double? height, {BoxFit fit = BoxFit.contain}) {
    final network = p.image == null
        ? placeholder(p, height)
        : networkPhoto(p, p.image!, height, fit);
    final asset = bundledPhoto(p);
    return asset == null
        ? network
        : Image.asset(
            asset,
            height: height,
            width: double.infinity,
            fit: fit,
            errorBuilder: (_, _, _) => network,
          );
  }

  List<String> photos(Product p) =>
      p.gallery.isNotEmpty ? p.gallery : [if (p.image != null) p.image!];

  void openPhotos(BuildContext context, Product p, int start) {
    final controller = PageController(initialPage: start);
    final list = photos(p);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(title(p)),
          ),
          body: PageView(
            controller: controller,
            children: [
              for (final url in list)
                InteractiveViewer(
                  maxScale: 5,
                  child: Center(
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => photo(p, null),
                    ),
                  ),
                ),
              if (list.isEmpty)
                InteractiveViewer(child: Center(child: photo(p, null))),
            ],
          ),
        ),
      ),
    );
  }

  Widget gallery(BuildContext context, Product p) {
    final list = photos(p);
    var page = 0;
    return StatefulBuilder(
      builder: (context, refresh) => Container(
        height: 320,
        color: Colors.white,
        child: Stack(
          children: [
            if (list.length > 1)
              PageView(
                onPageChanged: (i) => refresh(() => page = i),
                children: [
                  for (var i = 0; i < list.length; i++)
                    GestureDetector(
                      onTap: () => openPhotos(context, p, i),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: i == 0
                            ? photo(p, null)
                            : networkPhoto(p, list[i], null, BoxFit.contain),
                      ),
                    ),
                ],
              )
            else
              GestureDetector(
                onTap: list.isEmpty ? null : () => openPhotos(context, p, 0),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: photo(p, null),
                ),
              ),
            if (list.length > 1)
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < list.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == page ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i == page
                              ? Theme.of(context).colorScheme.primary
                              : const Color(0xffd5cdc0),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget dimensionTiles(BuildContext context, FurnitureSize size) {
    final theme = Theme.of(context);
    return Row(
      children: [
        for (final (label, value) in [
          (tr('العرض', 'Width'), size.width),
          (tr('العمق', 'Depth'), size.depth),
          (tr('الارتفاع', 'Height'), size.height),
        ])
          Expanded(
            child: Container(
              margin: const EdgeInsetsDirectional.only(end: 8),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(label, style: theme.textTheme.bodySmall),
                  Text(
                    '$value ${tr('سم', 'cm')}',
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget arSection(BuildContext context, Product p, ArModel model) {
    final theme = Theme.of(context);
    final canOpenAR = Platform.isIOS || arUrl.isNotEmpty;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.view_in_ar, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('شوفها في مكانك', 'See it in your space'),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            RoomOrbit(
              width: math.max(360, model.size.width + 120),
              length: math.max(360, model.size.depth + 200),
              height: 280,
              openings: const [],
              pieces: [
                RoomPiece(
                  model.size,
                  math.max(360, model.size.width + 120) / 2,
                  math.max(360, model.size.depth + 200) / 2,
                  0,
                ),
              ],
              arabic: arabic,
            ),
            if (canOpenAR)
              FilledButton.icon(
                onPressed: () async {
                  try {
                    final opened = await ProductAR.open(
                      p.sku,
                      website: arUrl,
                      language: arabic ? 'ar' : 'en',
                    );
                    if (!opened)
                      throw const FormatException('Preview unavailable');
                  } catch (_) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          tr(
                            'تعذّر فتح المعاينة. جرّب العرض ثلاثي الأبعاد.',
                            'Preview unavailable. Try the 3D view.',
                          ),
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.view_in_ar),
                label: Text(tr('جرّبه في مكانك', 'View in your space')),
              ),
            if (model.inRoomPlanner) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  setState(() => tab = 3);
                  plannerKey.currentState?.addProduct(model.size);
                },
                icon: const Icon(Icons.add_home_outlined),
                label: Text(tr('أضف إلى غرفتي', 'Add to my room')),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              tr(
                'مجسم بأبعاد المنتج، يحتاج اعتماد الشكل والخامة.',
                'Dimensioned reconstruction. Shape and material approval are pending.',
              ),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  void showProduct(BuildContext context, Product p) {
    final model = arModel(p);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => StatefulBuilder(
          builder: (context, refresh) {
            final theme = Theme.of(context);
            return Scaffold(
              appBar: AppBar(
                title: Text(stores[p.store]),
                actions: [
                  IconButton(
                    tooltip: tr('المفضلة', 'Favourites'),
                    onPressed: () {
                      toggleFavourite(p);
                      refresh(() {});
                    },
                    icon: Icon(
                      favourites.contains(p.key)
                          ? Icons.favorite
                          : Icons.favorite_border,
                    ),
                  ),
                ],
              ),
              body: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  gallery(context, p),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          stores[p.store].toUpperCase(),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            letterSpacing: 1.2,
                          ),
                        ),
                        Text(title(p), style: theme.textTheme.headlineMedium),
                        Text(
                          p.sku.isEmpty ? p.size : '${p.sku}  •  ${p.size}',
                          textDirection: TextDirection.ltr,
                          textAlign: arabic ? TextAlign.right : TextAlign.left,
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (p.price.isNotEmpty)
                              Text(
                                p.price,
                                textDirection: TextDirection.ltr,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            if (p.inStock != null)
                              Chip(
                                visualDensity: VisualDensity.compact,
                                side: BorderSide.none,
                                backgroundColor: p.inStock!
                                    ? theme.colorScheme.secondaryContainer
                                    : theme.colorScheme.errorContainer,
                                label: Text(
                                  p.inStock!
                                      ? tr('متوفر', 'In stock')
                                      : tr('غير متوفر', 'Out of stock'),
                                ),
                              ),
                          ],
                        ),
                        if (model != null) ...[
                          const SizedBox(height: 16),
                          dimensionTiles(context, model.size),
                          const SizedBox(height: 16),
                          arSection(context, p, model),
                        ] else
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              tr(
                                'تجربة الغرفة تتوفر عقب تجهيز مجسم ومقاسات معتمدة لهالمنتج.',
                                'Room preview will be available after this product has a model and approved dimensions.',
                              ),
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        const SizedBox(height: 20),
                        Text(
                          tr('التفاصيل', 'Details'),
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(arabic ? p.arabicDetails : p.details),
                        if (p.attributes.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          for (final attribute in p.attributes)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('• $attribute'),
                            ),
                        ],
                        if (p.link != null) ...[
                          const SizedBox(height: 12),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton.icon(
                              onPressed: () => launchUrl(
                                Uri.parse(p.link!),
                                mode: LaunchMode.externalApplication,
                              ),
                              icon: const Icon(Icons.open_in_new, size: 18),
                              label: Text(
                                tr(
                                  'الصفحة الرسمية للمنتج',
                                  'Official product page',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              bottomNavigationBar: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: p.inStock == false
                        ? null
                        : () {
                            final messenger = ScaffoldMessenger.of(context);
                            changeQuantity(p, 1);
                            Navigator.of(context).pop();
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  tr('انضافت للسلة', 'Added to your bag'),
                                ),
                                action: SnackBarAction(
                                  label: tr('السلة', 'Bag'),
                                  onPressed: () => setState(() => tab = 2),
                                ),
                              ),
                            );
                          },
                    icon: const Icon(Icons.shopping_bag_outlined),
                    label: Text(tr('أضف للسلة', 'Add to bag')),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget productCard(BuildContext context, Product p) {
    final theme = Theme.of(context);
    final has3d = arModel(p) != null;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showProduct(context, p),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                color: Colors.white,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: photo(p, null),
                    ),
                    if (has3d)
                      PositionedDirectional(
                        top: 10,
                        start: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.view_in_ar,
                                size: 14,
                                color: theme.colorScheme.onPrimary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '3D',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    PositionedDirectional(
                      top: 2,
                      end: 2,
                      child: IconButton(
                        tooltip: tr('المفضلة', 'Favourites'),
                        onPressed: () => toggleFavourite(p),
                        icon: Icon(
                          favourites.contains(p.key)
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: favourites.contains(p.key)
                              ? const Color(0xffb3261e)
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title(p),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          p.price.isEmpty ? p.size : p.price,
                          textDirection: TextDirection.ltr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: p.price.isEmpty
                              ? theme.textTheme.bodySmall
                              : theme.textTheme.titleSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: tr('قارن المنتج', 'Compare product'),
                    onPressed: () => setState(() {
                      if (!compare.remove(p.key)) {
                        if (compare.length >= 3) compare.remove(compare.first);
                        compare.add(p.key);
                      }
                    }),
                    icon: Icon(
                      compare.contains(p.key)
                          ? Icons.check_box_outlined
                          : Icons.compare_arrows,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void showComparison(BuildContext context) {
    final selected = allProducts.where((p) => compare.contains(p.key)).toList();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text(tr('قارن اختياراتك', 'Compare your choices')),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                DataColumn(label: Text(tr('التفاصيل', 'Details'))),
                for (final p in selected)
                  DataColumn(
                    label: SizedBox(width: 160, child: Text(title(p))),
                  ),
              ],
              rows: [
                for (final (label, values) in [
                  (
                    tr('المتجر', 'Store'),
                    selected.map((p) => stores[p.store]).toList(),
                  ),
                  (
                    tr('رمز المنتج', 'SKU'),
                    selected.map((p) => p.sku).toList(),
                  ),
                  (
                    tr('المقاس', 'Dimensions'),
                    selected.map((p) => p.size).toList(),
                  ),
                  (tr('السعر', 'Price'), selected.map((p) => p.price).toList()),
                  (
                    tr('المعاينة', 'Room preview'),
                    selected
                        .map(
                          (p) => arModel(p) != null
                              ? tr('مجسم متاح', 'Model available')
                              : tr('بانتظار التجهيز', 'Pending'),
                        )
                        .toList(),
                  ),
                ])
                  DataRow(
                    cells: [
                      DataCell(Text(label)),
                      for (final value in values)
                        DataCell(
                          SizedBox(
                            width: 160,
                            child: Text(value.isEmpty ? '…' : value),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  int get activeFilters =>
      (category != null ? 1 : 0) +
      (availableOnly ? 1 : 0) +
      (modelsOnly ? 1 : 0) +
      (sort != 'default' ? 1 : 0);

  void showFilters(BuildContext context, List<String> departments) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) {
          void update(VoidCallback change) {
            setState(() {
              change();
              visibleCount = 24;
            });
            refresh(() {});
          }

          final theme = Theme.of(context);
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    tr('تصفية وترتيب', 'Filter and sort'),
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  if (departments.isNotEmpty) ...[
                    Text(
                      tr('القسم', 'Department'),
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        ChoiceChip(
                          label: Text(tr('كل الأقسام', 'All departments')),
                          selected: category == null,
                          onSelected: (_) => update(() => category = null),
                        ),
                        for (final department in departments)
                          ChoiceChip(
                            label: Text(department),
                            selected: category == department,
                            onSelected: (_) =>
                                update(() => category = department),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('المتوفر فقط', 'In stock only')),
                    value: availableOnly,
                    onChanged: (v) => update(() => availableOnly = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('جاهز للمعاينة 3D', 'Ready for 3D preview')),
                    value: modelsOnly,
                    onChanged: (v) => update(() => modelsOnly = v),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr('الترتيب', 'Sort'),
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final (value, label) in [
                        ('default', tr('ترتيب الموقع', 'Website order')),
                        ('name', tr('الاسم', 'Name')),
                        (
                          'priceAsc',
                          tr('السعر: الأقل أولًا', 'Price: low to high'),
                        ),
                        (
                          'priceDesc',
                          tr('السعر: الأعلى أولًا', 'Price: high to low'),
                        ),
                      ])
                        ChoiceChip(
                          label: Text(label),
                          selected: sort == value,
                          onSelected: (_) => update(() => sort = value),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => update(() {
                          category = null;
                          availableOnly = false;
                          modelsOnly = false;
                          sort = 'default';
                        }),
                        child: Text(tr('مسح الكل', 'Clear all')),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(tr('عرض النتائج', 'Show results')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget emptyState(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(icon, size: 56, color: const Color(0xffc8bda9)),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget productGrid(BuildContext context, List<Product> shown) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth < 340
              ? 1
              : (constraints.maxWidth / 185).floor().clamp(2, 5).toInt();
          return GridView.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
              mainAxisExtent:
                  300 + (MediaQuery.textScalerOf(context).scale(20) - 20) * 4,
            ),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: shown.length < visibleCount
                ? shown.length
                : visibleCount,
            itemBuilder: (context, index) => productCard(context, shown[index]),
          );
        },
      );

  Widget roomBanner(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xff2d4a3f), Color(0xff4f6f61)],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('جرّب قبل ما تشتري', 'Try before you buy'),
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tr(
                    'أدخل مقاس غرفتك وشوف القطع بمقاسها الحقيقي.',
                    'Enter your room size and see pieces at true scale.',
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: .85),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xff2d4a3f),
                  ),
                  onPressed: () => setState(() => tab = 3),
                  icon: const Icon(Icons.architecture, size: 18),
                  label: Text(tr('صمّم غرفتك', 'Design your room')),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.view_in_ar, size: 64, color: Color(0x55ffffff)),
        ],
      ),
    );
  }

  Widget bag(BuildContext context) {
    final theme = Theme.of(context);
    final items = allProducts.where((p) => cart.containsKey(p.key)).toList();
    final count = items.fold<int>(0, (n, p) => n + cart[p.key]!);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        Text(tr('السلة', 'Bag'), style: theme.textTheme.headlineMedium),
        if (items.isEmpty)
          emptyState(
            context,
            Icons.shopping_bag_outlined,
            tr('السلة فاضية', 'Your bag is empty'),
          )
        else ...[
          Text(
            tr('$count قطعة', '$count item${count == 1 ? '' : 's'}'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          for (final p in items)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => showProduct(context, p),
                      child: Container(
                        width: 76,
                        height: 76,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: photo(p, null),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title(p),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                          Text(
                            stores[p.store],
                            style: theme.textTheme.bodySmall,
                          ),
                          if (p.price.isNotEmpty)
                            Text(
                              p.price,
                              textDirection: TextDirection.ltr,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: tr('أنقص', 'Decrease'),
                            onPressed: () => changeQuantity(p, -1),
                            icon: Icon(
                              cart[p.key] == 1
                                  ? Icons.delete_outline
                                  : Icons.remove,
                              size: 20,
                            ),
                          ),
                          Text('${cart[p.key]}'),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: tr('زِد', 'Increase'),
                            onPressed: () => changeQuantity(p, 1),
                            icon: const Icon(Icons.add, size: 20),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr(
                      'الدفع يتفعّل بعد ربط نظام الطلبات.',
                      'Checkout is pending store integration.',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget content(BuildContext context) {
    if (tab == 2) return bag(context);
    final theme = Theme.of(context);
    final selected = products(store);
    final q = query.trim().toLowerCase();
    final filtered = tab == 1
        ? allProducts.where((p) => favourites.contains(p.key))
        : selected.where(
            (p) =>
                (category == null || p.categories.contains(category)) &&
                (!availableOnly || p.inStock == true) &&
                (!modelsOnly || arModel(p) != null) &&
                '${p.name} ${p.arabic} ${p.sku}'.toLowerCase().contains(q),
          );
    final shown = filtered.toList();
    if (sort == 'name') shown.sort((a, b) => title(a).compareTo(title(b)));
    if (sort == 'priceAsc' || sort == 'priceDesc') {
      shown.sort((a, b) {
        if (a.numericPrice == null) return b.numericPrice == null ? 0 : 1;
        if (b.numericPrice == null) return -1;
        return sort == 'priceAsc'
            ? a.numericPrice!.compareTo(b.numericPrice!)
            : b.numericPrice!.compareTo(a.numericPrice!);
      });
    }
    final departments = selected.expand((p) => p.categories).toSet().toList()
      ..sort();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (tab == 1) ...[
          Text(
            tr('المفضلة', 'Favourites'),
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          if (shown.isEmpty)
            emptyState(
              context,
              Icons.favorite_border,
              tr(
                'اضغط على القلب لحفظ القطع اللي تعجبك.',
                'Tap the heart to keep pieces you like.',
              ),
            ),
        ],
        if (tab == 0) ...[
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              for (var i = 0; i < stores.length; i++)
                ButtonSegment(value: i, label: Text(stores[i])),
            ],
            selected: {store},
            onSelectionChanged: (value) => setState(() {
              store = value.first;
              category = null;
              visibleCount = 24;
            }),
          ),
          const SizedBox(height: 14),
          if (q.isEmpty) ...[roomBanner(context), const SizedBox(height: 14)],
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: query,
                  onChanged: (value) => setState(() {
                    query = value;
                    visibleCount = 24;
                  }),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: tr(
                      'ابحث بالاسم أو الكود',
                      'Search by name or SKU',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Badge(
                isLabelVisible: activeFilters > 0,
                label: Text('$activeFilters'),
                child: IconButton.filledTonal(
                  tooltip: tr('تصفية وترتيب', 'Filter and sort'),
                  onPressed: () => showFilters(context, departments),
                  icon: const Icon(Icons.tune),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  !live.containsKey(store)
                      ? tr('كتالوج تجريبي', 'Demo catalogue')
                      : cacheTimes[store] != null
                      ? '${tr('آخر تحديث', 'Updated')} ${cacheTimes[store]!.toLocal().toString().substring(0, 16)}'
                      : '',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              if (failed.contains(store))
                TextButton.icon(
                  onPressed: () => loadCatalogue(store),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(
                    tr('تعذّر التحديث، أعد المحاولة', 'Update failed, retry'),
                  ),
                ),
              if (compare.length >= 2)
                TextButton.icon(
                  onPressed: () => showComparison(context),
                  icon: const Icon(Icons.compare_arrows, size: 18),
                  label: Text(
                    tr(
                      'قارن (${compare.length})',
                      'Compare (${compare.length})',
                    ),
                  ),
                ),
            ],
          ),
          if (loading.contains(store)) const LinearProgressIndicator(),
          const SizedBox(height: 6),
          if (shown.isEmpty)
            emptyState(
              context,
              Icons.search_off,
              tr('ما في منتجات', 'No products found'),
            ),
        ],
        if (shown.isNotEmpty) productGrid(context, shown),
        if (shown.length > visibleCount)
          OutlinedButton(
            onPressed: () => setState(() => visibleCount += 24),
            child: Text(tr('عرض منتجات أكثر', 'Show more products')),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: Locale(arabic ? 'ar' : 'en'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    title: 'Almutlaq Furniture',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff365348),
        surface: const Color(0xfff8f6f1),
      ),
      fontFamily: arabic ? 'NotoSansArabic' : null,
      scaffoldBackgroundColor: const Color(0xfff8f6f1),
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        backgroundColor: Color(0xfff8f6f1),
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: arabic ? 'NotoSansArabic' : null,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Color(0xff1d2b25),
        ),
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        color: Color(0xfff0ece4),
        margin: EdgeInsets.all(4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xffeeeae2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: Color(0xffd7e6dc),
        elevation: 2,
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        bodyMedium: TextStyle(fontSize: 14, height: 1.6),
      ),
    ),
    home: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: Text(tr('المطلق للأثاث', 'Almutlaq Furniture')),
          actions: [
            IconButton(
              tooltip: tr('تحديث التطبيق', 'App updates'),
              icon: const Icon(Icons.system_update_alt),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => AppUpdates(arabic)),
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() => arabic = !arabic);
                widget.preferences.setBool('arabic', arabic);
              },
              child: Text(arabic ? 'EN' : 'عربي'),
            ),
          ],
        ),
        body: IndexedStack(
          index: tab == 3 ? 1 : 0,
          children: [
            content(context),
            RoomPlanner(widget.preferences, arabic, key: plannerKey),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.storefront),
              label: tr('المتاجر', 'Stores'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.favorite_border),
              label: tr('المفضلة', 'Favourites'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.shopping_bag_outlined),
              label: tr('السلة', 'Bag'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.architecture),
              label: tr('الغرفة', 'Room'),
            ),
          ],
        ),
      ),
    ),
  );
}
