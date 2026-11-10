import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(FurnitureApp(await SharedPreferences.getInstance()));
}

const stores = ['The Factory', 'CityW'];
const arUrl = String.fromEnvironment('SHOWROOM_AR_URL');

class Product {
  const Product(
    this.sku,
    this.store,
    this.name,
    this.arabic,
    this.size,
    this.details,
    this.arabicDetails, {
    this.image,
    this.hasModel = false,
  });
  final String sku, name, arabic, size, details, arabicDetails;
  final int store;
  final String? image;
  final bool hasModel;
}

const catalogue = [
  Product(
    '10_14_3',
    0,
    'London three-seater',
    '�렡 ��� �韣�',
    '210 ? 103 ? 100 cm',
    'White upholstered sofa with three seats.',
    '�렡 ����� �뤑�� ��韣� ���.',
    image: 'https://thefactoryfurniture.com/wp-content/uploads/2026/11/10-14-00003-1.jpg',
    hasModel: true,
  ),
  Product(
    '6_14_5',
    0,
    'London chair',
    '詫� ���',
    '84 ? 95 ? 94 cm',
    'White upholstered single seat.',
    '詫� ���� �뤑� ���� ퟥ�.',
    image: 'https://thefactoryfurniture.com/wp-content/uploads/2026/11/06-14-00005-1.jpg',
  ),
  Product(
    '23_88_1',
    1,
    'Warm Beige three-seater',
    '�렡 �� ��� �韣�',
    '230 ? 101 ? 78 cm',
    'Woven fabric with a solid wood frame.',
    '�꟬ ���� �� �៩ �� �馬� ���.',
  ),
];

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

  @override
  void initState() {
    super.initState();
    arabic = widget.preferences.getBool('arabic') ?? true;
    favourites = (widget.preferences.getStringList('favourites') ?? []).toSet();
    final saved =
        jsonDecode(widget.preferences.getString('cart') ?? '{}') as Map;
    cart = {
      for (final p in catalogue)
        if (saved[p.sku] is int && (saved[p.sku] as int) > 0)
          p.sku: saved[p.sku] as int,
    };
  }

  String tr(String ar, String en) => arabic ? ar : en;
  String title(Product p) => arabic ? p.arabic : p.name;

  void toggleFavourite(Product p) {
    setState(() {
      if (!favourites.remove(p.sku)) favourites.add(p.sku);
    });
    widget.preferences.setStringList('favourites', favourites.toList());
  }

  void changeQuantity(Product p, int delta) {
    setState(() {
      final next = (cart[p.sku] ?? 0) + delta;
      if (next <= 0) {
        cart.remove(p.sku);
      } else {
        cart[p.sku] = next;
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
              photo(p, 240),
              Text(title(p), style: Theme.of(context).textTheme.headlineMedium),
              Text('${p.sku}  ?  ${p.size}'),
              const SizedBox(height: 12),
              Text(arabic ? p.arabicDetails : p.details),
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
                    label: Text(tr('����� �� ���', 'View in your room')),
                  ),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  changeQuantity(p, 1);
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.shopping_bag_outlined),
                label: Text(tr('��� ���', 'Add to bag')),
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
            title: Text(title(p)),
            subtitle: Text(p.size),
            trailing: IconButton(
              tooltip: tr('������', 'Favourites'),
              onPressed: () => toggleFavourite(p),
              icon: Icon(
                favourites.contains(p.sku)
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
    final selected = catalogue.where((p) => p.store == store);
    final q = query.trim().toLowerCase();
    final shown = tab == 1
        ? catalogue.where((p) => favourites.contains(p.sku))
        : selected.where(
            (p) => '${p.name} ${p.arabic} ${p.sku}'.toLowerCase().contains(q),
          );
    final items = selected.where((p) => cart.containsKey(p.sku));
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
                  onSelected: (_) => setState(() => store = i),
                ),
            ],
          ),
        if (tab == 0) ...[
          Text(
            tr('���� ���', 'Furniture for your home'),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          Text(tr('袟��� �����', 'Demo catalogue')),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: query,
            onChanged: (value) => setState(() => query = value),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              labelText: tr('���� ��韫� �� �����', 'Search by name or SKU'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (tab == 2) ...[
          if (items.isEmpty) Text(tr('��� ���', 'Your bag is empty')),
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
                  Text('${cart[p.sku]}'),
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
                '���� ���� �� ��� ��� ���頟�.',
                'Checkout is pending store integration.',
              ),
            ),
        ] else ...[
          if (shown.isEmpty) Text(tr('� �� �뢤��', 'No products found')),
          for (final p in shown) productCard(context, p),
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
          title: Text(tr('������ �隣��', 'Almutlaq Furniture')),
          actions: [
            TextButton(
              onPressed: () {
                setState(() => arabic = !arabic);
                widget.preferences.setBool('arabic', arabic);
              },
              child: Text(arabic ? 'EN' : '㩠�'),
            ),
          ],
        ),
        body: content(context),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.storefront),
              label: tr('��ꢟ��', 'Stores'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.favorite_border),
              label: tr('������', 'Favourites'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.shopping_bag_outlined),
              label: tr('���', 'Bag'),
            ),
          ],
        ),
      ),
    ),
  );
}
