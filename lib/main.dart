import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() => runApp(const ShowroomApp());

const stores = [
  (name: 'The Factory', url: 'https://thefactoryfurniture.com/ar/'),
  (name: 'CityW', url: 'https://cityw.com.sa/'),
];
const arUrl = String.fromEnvironment('SHOWROOM_AR_URL');
const londonUrl =
    'https://thefactoryfurniture.com/ar/shop/sofa-three-seater-white-3-seater-london/';

class ShowroomApp extends StatelessWidget {
  const ShowroomApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Almutlaq Furniture',
    theme: ThemeData(colorSchemeSeed: const Color(0xff365348)),
    home: const Storefront(),
  );
}

class Storefront extends StatefulWidget {
  const Storefront({super.key});

  @override
  State<Storefront> createState() => _StorefrontState();
}

class _StorefrontState extends State<Storefront> {
  late final List<WebViewController> controllers;
  final progress = [0, 0];
  final londonOpen = [false, false];
  final errors = [false, false];
  int selected = 0;

  @override
  void initState() {
    super.initState();
    controllers = List.generate(stores.length, makeController);
  }

  WebViewController makeController(int index) => WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setNavigationDelegate(
      NavigationDelegate(
        onProgress: (value) {
          if (mounted) setState(() => progress[index] = value);
        },
        onPageStarted: (url) {
          if (!mounted) return;
          setState(() {
            errors[index] = false;
            final current = Uri.tryParse(url);
            final london = Uri.parse(londonUrl);
            londonOpen[index] =
                current?.host == london.host &&
                current?.path.replaceFirst(RegExp(r'/$'), '') ==
                    london.path.replaceFirst(RegExp(r'/$'), '');
          });
        },
        onWebResourceError: (error) {
          if (mounted && error.isForMainFrame == true) {
            setState(() => errors[index] = true);
          }
        },
        onNavigationRequest: (request) {
          final url = Uri.tryParse(request.url);
          if (url?.scheme == 'https' || url?.scheme == 'about') {
            return NavigationDecision.navigate;
          }
          if (url != null && ['tel', 'mailto'].contains(url.scheme)) {
            openExternal(url);
          }
          return NavigationDecision.prevent;
        },
      ),
    )
    ..loadRequest(Uri.parse(stores[index].url));

  Future<void> openExternal(Uri uri) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // The platform might not have a handler for this link.
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open the link.')));
    }
  }

  Future<void> goBack() async {
    final controller = controllers[selected];
    if (await controller.canGoBack()) await controller.goBack();
  }

  @override
  Widget build(BuildContext context) {
    final ar = Uri.tryParse(arUrl);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) goBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: goBack,
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
          ),
          title: Text(stores[selected].name),
          actions: [
            IconButton(
              onPressed: () => controllers[selected].reload(),
              icon: const Icon(Icons.refresh),
              tooltip: 'Reload',
            ),
            IconButton(
              onPressed: () async {
                final current = await controllers[selected].currentUrl();
                final url = Uri.tryParse(current ?? stores[selected].url);
                if (url != null && url.scheme == 'https') {
                  await openExternal(url);
                }
              },
              icon: const Icon(Icons.open_in_browser),
              tooltip: 'Open in browser',
            ),
          ],
        ),
        body: Column(
          children: [
            if (progress[selected] < 100 && !errors[selected])
              LinearProgressIndicator(value: progress[selected] / 100),
            if (londonOpen[selected] &&
                ar != null &&
                ar.scheme == 'https' &&
                ar.host.isNotEmpty)
              FilledButton.icon(
                onPressed: () => openExternal(ar),
                icon: const Icon(Icons.view_in_ar),
                label: const Text('View in your room'),
              ),
            if (errors[selected])
              MaterialBanner(
                content: const Text('The store could not load.'),
                actions: [
                  TextButton(
                    onPressed: () => controllers[selected].reload(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            Expanded(
              child: IndexedStack(
                index: selected,
                children: [
                  for (final controller in controllers)
                    WebViewWidget(controller: controller),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: selected,
          onDestinationSelected: (index) => setState(() => selected = index),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.weekend_outlined),
              label: 'The Factory',
            ),
            NavigationDestination(
              icon: Icon(Icons.chair_outlined),
              label: 'CityW',
            ),
          ],
        ),
      ),
    );
  }
}
