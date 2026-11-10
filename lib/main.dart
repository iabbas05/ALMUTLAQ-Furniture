import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'catalogue.dart';
import 'room_planner.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(FurnitureApp(await SharedPreferences.getInstance()));
}

const arUrl = String.fromEnvironment('SHOWROOM_AR_URL');

class FurnitureApp extends StatefulWidget {
  const FurnitureApp(this.preferences, {super.key});
  final SharedPreferences preferences;
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
        if (store == index &&
            !products.any((p) => p.categories.contains(category))) {
          category = null;
        }
      });
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
    final saved =
        jsonDecode(widget.preferences.getString('cart') ?? '{}') as Map;
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
      loadCatalogue(i);
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
    return Image.network(
      p.image!,
      height: height,
      width: double.infinity,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => placeholder,
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
              if (p.hasModel) ...[
                const SizedBox(
                  height: 280,
                  child: ModelViewer(
                    src: 'assets/london-10_14_3.glb',
                    alt: 'London sofa prototype',
                    cameraControls: true,
                  ),
                ),
                if (arUrl.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final uri = Uri.tryParse(arUrl);
                      if (uri != null && uri.scheme == 'https') {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                    icon: const Icon(Icons.view_in_ar),
                    label: Text(tr('جرّبها في غرفتك', 'View in your room')),
                  ),
              ],
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
        ],
      ),
    ),
  );

  Widget content(BuildContext context) {
    final selected = products(store);
    final q = query.trim().toLowerCase();
    final shown = tab == 1
        ? allProducts.where((p) => favourites.contains(p.key))
        : selected.where(
            (p) =>
                (category == null || p.categories.contains(category)) &&
                '${p.name} ${p.arabic} ${p.sku}'.toLowerCase().contains(q),
          );
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
          Text(
            tr('أثاث بيتك', 'Furniture for your home'),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          if (loading.contains(store)) const LinearProgressIndicator(),
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
              return GridView.count(
                crossAxisCount: columns,
                mainAxisExtent: 260,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final p in shown.take(visibleCount))
                    productCard(context, p),
                ],
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
      scaffoldBackgroundColor: const Color(0xfff8f6f1),
    ),
    home: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: Text(tr('المطلق للأثاث', 'Almutlaq Furniture')),
          actions: [
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
          children: [content(context), RoomPlanner(widget.preferences, arabic)],
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
