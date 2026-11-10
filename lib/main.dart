import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'catalogue.dart';
import 'room_planner.dart';
import 'room_geometry.dart';
import 'room_orbit.dart';
import 'app_updates.dart';

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

  Widget photo(Product p, double height) {
    final placeholder = SizedBox(
      height: height,
      child: const Center(child: Icon(Icons.weekend_outlined, size: 48)),
    );
    if (p.image == null) return placeholder;
    final network = Image.network(
      p.image!,
      height: height,
      width: double.infinity,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => placeholder,
    );
    final asset = p.store == 0 && p.sku == '10_14_3'
        ? 'assets/london-sofa.jpg'
        : p.store == 0 && p.sku == '6_14_5'
        ? 'assets/london-chair.jpg'
        : null;
    return asset == null
        ? network
        : Image.asset(
            asset,
            height: height,
            width: double.infinity,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => network,
          );
  }

  void showProduct(BuildContext context, Product p) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(stores[p.store])),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (p.gallery.length > 1)
                SizedBox(
                  height: 240,
                  child: PageView(
                    children: [
                      for (final url in p.gallery)
                        Image.network(
                          url,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => photo(p, 240),
                        ),
                    ],
                  ),
                )
              else
                photo(p, 240),
              Text(title(p), style: Theme.of(context).textTheme.headlineMedium),
              Text('${p.sku}  •  ${p.size}'),
              const SizedBox(height: 12),
              if (p.price.isNotEmpty)
                Text(p.price, style: Theme.of(context).textTheme.titleLarge),
              if (p.inStock != null)
                Text(
                  p.inStock!
                      ? tr('متوفر', 'In stock')
                      : tr('غير متوفر', 'Out of stock'),
                ),
              Text(arabic ? p.arabicDetails : p.details),
              for (final attribute in p.attributes) Text(attribute),
              if (p.link != null)
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse(p.link!),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Text(
                    tr('الصفحة الرسمية للمنتج', 'Official product page'),
                  ),
                ),
              if (p.geometry case final FurnitureSize geometry) ...[
                const SizedBox(height: 16),
                RoomOrbit(
                  width: 360,
                  length: 360,
                  height: 280,
                  openings: const [],
                  pieces: [RoomPiece(geometry, 180, 180, 0)],
                  arabic: arabic,
                ),
                Text(
                  tr(
                    'مجسم بأبعاد المنتج، يحتاج اعتماد الشكل والخامة.',
                    'Dimensioned reconstruction. Shape and material approval are pending.',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    setState(() => tab = 3);
                    plannerKey.currentState?.addProduct(geometry);
                  },
                  icon: const Icon(Icons.add_home_outlined),
                  label: Text(tr('أضف إلى غرفتي', 'Add to my room')),
                ),
                if (arUrl.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final uri = Uri.tryParse(arUrl);
                      if (uri != null && uri.scheme == 'https') {
                        await launchUrl(
                          uri.replace(
                            queryParameters: {
                              ...uri.queryParameters,
                              'sku': p.sku,
                            },
                          ),
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                    icon: const Icon(Icons.view_in_ar),
                    label: Text(tr('جرّبه في مكانك', 'View in your space')),
                  ),
              ] else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    tr(
                      'تجربة الغرفة تتوفر عقب تجهيز مجسم ومقاسات معتمدة لهالمنتج.',
                      'Room preview will be available after this product has a model and approved dimensions.',
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: p.inStock == false
                    ? null
                    : () {
                        changeQuantity(p, 1);
                        Navigator.of(context).pop();
                      },
                icon: const Icon(Icons.shopping_bag_outlined),
                label: Text(tr('أضف للسلة', 'Add to bag')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget productCard(BuildContext context, Product p) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => showProduct(context, p),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          photo(p, 165),
          ListTile(
            title: Text(title(p), maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(p.price.isEmpty ? p.size : p.price),
            trailing: IconButton(
              tooltip: tr('المفضلة', 'Favourites'),
              onPressed: () => toggleFavourite(p),
              icon: Icon(
                favourites.contains(p.key)
                    ? Icons.favorite
                    : Icons.favorite_border,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                if (p.geometry != null) const Icon(Icons.view_in_ar, size: 18),
                const Spacer(),
                IconButton(
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
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

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
                          (p) => p.geometry != null
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

  Widget content(BuildContext context) {
    final selected = products(store);
    final q = query.trim().toLowerCase();
    final filtered = tab == 1
        ? allProducts.where((p) => favourites.contains(p.key))
        : selected.where(
            (p) =>
                (category == null || p.categories.contains(category)) &&
                (!availableOnly || p.inStock == true) &&
                (!modelsOnly || p.geometry != null) &&
                '${p.name} ${p.arabic} ${p.sku}'.toLowerCase().contains(q),
          );
    final shown = filtered.toList();
    if (sort == 'name') shown.sort((a, b) => title(a).compareTo(title(b)));
    if (sort == 'priceAsc' || sort == 'priceDesc')
      shown.sort((a, b) {
        if (a.numericPrice == null) return b.numericPrice == null ? 0 : 1;
        if (b.numericPrice == null) return -1;
        return sort == 'priceAsc'
            ? a.numericPrice!.compareTo(b.numericPrice!)
            : b.numericPrice!.compareTo(a.numericPrice!);
      });
    final items = selected.where((p) => cart.containsKey(p.key));
    final departments = selected.expand((p) => p.categories).toSet().toList()
      ..sort();
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        if (tab != 1)
          Wrap(
            spacing: 8,
            children: [
              for (var i = 0; i < stores.length; i++)
                ChoiceChip(
                  label: Text(stores[i]),
                  selected: store == i,
                  onSelected: (_) => setState(() {
                    store = i;
                    category = null;
                    visibleCount = 24;
                  }),
                ),
            ],
          ),
        if (tab == 0) ...[
          const SizedBox(height: 16),
          Text(
            tr('أثاث بيتك', 'Furniture for your home'),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          Text(
            tr(
              'اختار القطعة، جرّب مقاسها، واحفظ تصميمك.',
              'Find a piece, preview its size, and keep your design.',
            ),
          ),
          const SizedBox(height: 16),
          if (loading.contains(store)) const LinearProgressIndicator(),
          if (cacheTimes[store] != null)
            Text(
              '${tr('آخر تحديث', 'Updated')} ${cacheTimes[store]!.toLocal().toString().substring(0, 16)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (failed.contains(store))
            ListTile(
              title: Text(
                tr('تعذّر تحديث الكتالوج', 'Catalogue update unavailable'),
              ),
              subtitle: Text(
                tr(
                  'تُعرض المنتجات المتاحة في التطبيق',
                  'Showing available local products',
                ),
              ),
              trailing: IconButton(
                onPressed: () => loadCatalogue(store),
                icon: const Icon(Icons.refresh),
              ),
            ),
          if (!live.containsKey(store))
            Text(tr('كتالوج تجريبي', 'Demo catalogue')),
          if (departments.isNotEmpty)
            DropdownButton<String>(
              isExpanded: true,
              value: category ?? '',
              items: [
                DropdownMenuItem(
                  value: '',
                  child: Text(tr('كل الأقسام', 'All departments')),
                ),
                for (final department in departments)
                  DropdownMenuItem(
                    value: department,
                    child: Text(department, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) => setState(() {
                category = value == '' ? null : value;
                visibleCount = 24;
              }),
            ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: query,
            onChanged: (value) => setState(() {
              query = value;
              visibleCount = 24;
            }),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              labelText: tr('ابحث بالاسم أو الكود', 'Search by name or SKU'),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilterChip(
                label: Text(tr('متوفر', 'In stock')),
                selected: availableOnly,
                onSelected: (v) => setState(() => availableOnly = v),
              ),
              FilterChip(
                label: Text(tr('جاهز للغرفة', 'Room preview')),
                selected: modelsOnly,
                onSelected: (v) => setState(() => modelsOnly = v),
              ),
              if (compare.length >= 2)
                ActionChip(
                  label: Text(
                    tr(
                      'قارن (${compare.length})',
                      'Compare (${compare.length})',
                    ),
                  ),
                  onPressed: () => showComparison(context),
                ),
            ],
          ),
          DropdownButton<String>(
            isExpanded: true,
            value: sort,
            items: [
              DropdownMenuItem(
                value: 'default',
                child: Text(tr('ترتيب الموقع', 'Website order')),
              ),
              DropdownMenuItem(value: 'name', child: Text(tr('الاسم', 'Name'))),
              DropdownMenuItem(
                value: 'priceAsc',
                child: Text(tr('السعر: الأقل أولًا', 'Price: low to high')),
              ),
              DropdownMenuItem(
                value: 'priceDesc',
                child: Text(tr('السعر: الأعلى أولًا', 'Price: high to low')),
              ),
            ],
            onChanged: (v) {
              if (v != null) setState(() => sort = v);
            },
          ),
        ],
        const SizedBox(height: 12),
        if (tab == 2) ...[
          if (items.isEmpty) Text(tr('السلة فاضية', 'Your bag is empty')),
          for (final p in items)
            ListTile(
              title: Text(title(p)),
              subtitle: Text(p.sku),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () => changeQuantity(p, -1),
                    icon: const Icon(Icons.remove),
                  ),
                  Text('${cart[p.key]}'),
                  IconButton(
                    onPressed: () => changeQuantity(p, 1),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
          if (items.isNotEmpty)
            Text(
              tr(
                'الدفع يتفعّل بعد ربط نظام الطلبات.',
                'Checkout is pending store integration.',
              ),
            ),
        ] else ...[
          if (shown.isEmpty) Text(tr('ما في منتجات', 'No products found')),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 340
                  ? 1
                  : (constraints.maxWidth / 185).floor().clamp(2, 5).toInt();
              return GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisExtent:
                      330 +
                      (MediaQuery.textScalerOf(context).scale(20) - 20) * 4,
                ),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: shown.length < visibleCount
                    ? shown.length
                    : visibleCount,
                itemBuilder: (context, index) =>
                    productCard(context, shown[index]),
              );
            },
          ),
          if (shown.length > visibleCount)
            OutlinedButton(
              onPressed: () => setState(() => visibleCount += 24),
              child: Text(tr('عرض منتجات أكثر', 'Show more products')),
            ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: Locale(arabic ? 'ar' : 'en'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    title: 'Almutlaq Furniture',
    theme: ThemeData(
      colorSchemeSeed: const Color(0xff365348),
      fontFamily: arabic ? 'NotoSansArabic' : null,
      scaffoldBackgroundColor: const Color(0xfff8f6f1),
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xfff8f6f1),
        centerTitle: false,
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        color: Color(0xffefebe3),
        margin: EdgeInsets.all(6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xffeeece5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          height: 1.4,
        ),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
