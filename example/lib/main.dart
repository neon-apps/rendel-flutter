import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:rendel/rendel.dart';

import 'gallery.dart';

/// Neon Kicks — the scripted demo & e2e testbed for the assistant.
/// All state is in-memory; the five registered actions exercise every risk
/// level: search (read), order status (read), add to cart (write), promo
/// (write), cancel order (destructive).

/// The three lines the docs promise, written out.
///
/// The SDK ships an in-memory store by default and takes no storage
/// dependency of its own, so this is the host's decision to make. A real app
/// would use `shared_preferences` or its own secure store; the example writes
/// a file next to its own state so it needs no plugin either.
class KicksConfigStore implements RendelConfigStore {
  const KicksConfigStore();

  File get _file => File('${Directory.systemTemp.path}/neon_kicks_config.json');

  @override
  Future<String?> read() async {
    try {
      return await _file.exists() ? await _file.readAsString() : null;
    } catch (_) {
      // A cache that cannot be read costs the next launch its head start and
      // nothing else, which is the whole contract.
      return null;
    }
  }

  @override
  Future<void> write(String value) async {
    try {
      await _file.writeAsString(value);
    } catch (_) {/* see read() */}
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Rendel.init(
    // The default is the LOCAL seed key (supabase/seed.sql) and is valid
    // only against a stack you are running yourself. To point the example at
    // a deployed environment, pass both defines:
    //   flutter run --dart-define=RENDEL_API=... --dart-define=RENDEL_KEY=...
    // (NC_API and NC_KEY, the names before the rename, still work.)
    appKey: const String.fromEnvironment(
      'RENDEL_KEY',
      defaultValue: String.fromEnvironment(
        'NC_KEY',
        defaultValue: 'nc_pk_test_neonkicks_dev0001',
      ),
    ),
    config: RendelConfig(
      apiBaseUrl: String.fromEnvironment(
        'RENDEL_API',
        defaultValue: String.fromEnvironment(
          'NC_API',
          defaultValue: 'http://localhost:3200',
        ),
      ),
      assistantName: 'Kicks',
      launcherLabel: 'Ask',
      // A host with no store still gets the right assistant on every launch; it
      // just re-fetches on each cold start instead of painting from a cache.
      // This is the file-backed one so the example demonstrates the whole
      // path, including the offline launch.
      configStore: KicksConfigStore(),
      // This app draws only a light theme, so the assistant does too, even on a
      // phone in dark mode. An app with a dark theme leaves this out.
      themeMode: RendelThemeMode.light,

      // Photos, Camera, Files and the microphone are the SDK's own, ready
      // without a line here. The three Info.plist strings the camera and the
      // microphone need are in this app's own bundle, because Apple shows
      // them to this app's users. `onPickAttachment` and `onDictate` would
      // replace them with the host's.
      // Openers name what this app can actually do, in a shopper's words.
      // They double as the fastest manual smoke test of the golden path.
      suggestions: [
        'Running shoes under \$150',
        'Where is my order 1042?',
        'Cancel order 1039',
      ],
    ),
    actions: KicksStore.instance.assistantActions(),
  );
  Rendel.addContextProvider('cart', () async => KicksStore.instance.cartSnapshot());
  registerKicksRoutes();
  runApp(const NeonKicksApp());
}

/// The app's own navigator, so a screen the assistant offers is pushed where
/// the app pushes its screens.
final kicksNavigator = GlobalKey<NavigatorState>();

/// The screens the assistant may open from an answer (design/NAVIGATE.md):
/// each main screen of the app, under the name the app itself gives it. This
/// is the shape the AI setup playbook writes for a host, and its eval reads
/// this file as the reference.
void registerKicksRoutes() {
  final store = KicksStore.instance;
  Future<void> push(Widget screen) async {
    await kicksNavigator.currentState?.push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  Rendel.registerRoute(
    'product_detail',
    title: 'Shop › Product',
    description: 'One sneaker: its price and the EU sizes in stock.',
    params: {
      'product_id': const RendelRouteParam.string(
        description: 'The id search_products returns, e.g. p1',
        required: true,
        fromActions: true,
      ),
    },
    open: (params) async {
      final product = store.products.where((p) => p.id == '${params['product_id']}').firstOrNull;
      if (product != null) await push(ProductScreen(product: product));
    },
  );
  Rendel.registerRoute(
    'cart',
    title: 'Cart',
    description: 'What is in the shopper\'s cart, its total and any promo code.',
    open: (_) => push(const CartScreen()),
  );
  Rendel.registerRoute(
    'orders',
    title: 'Orders',
    description: 'Every order the shopper has placed, with its status.',
    open: (_) => push(const OrdersScreen()),
  );
  Rendel.registerRoute(
    'order_detail',
    title: 'Orders › Order',
    description: 'One order: its items and delivery status.',
    params: {
      'order_id': const RendelRouteParam.string(
        description: 'The order number, e.g. 1042',
        required: true,
        fromActions: true,
      ),
    },
    open: (params) async {
      final order = store.orders.where((o) => o.id == '${params['order_id']}').firstOrNull;
      if (order != null) await push(OrderScreen(order: order));
    },
  );
}

/// Action params come off the wire, which means they came from a model. The
/// schema says what should arrive; nothing guarantees it did. `as String?`
/// throws on the one request where the model sent a number, and a handler that
/// throws takes the whole turn with it — so coerce, never cast. The SDK's own
/// renderers follow the same rule for block props.
String _text(Object? value) => switch (value) {
      String v => v,
      num v => '$v',
      _ => '',
    };

double? _number(Object? value) => switch (value) {
      num v => v.toDouble(),
      String v => double.tryParse(v),
      _ => null,
    };

class Product {
  const Product(this.id, this.name, this.price, this.sizes);
  final String id;
  final String name;
  final double price;
  final List<int> sizes;
}

class Order {
  Order(this.id, this.items, this.status);
  final String id;
  final List<String> items;
  String status; // ordered | shipped | delivered | cancelled
}

class KicksStore extends ChangeNotifier {
  KicksStore._();
  static final KicksStore instance = KicksStore._();

  final products = const [
    Product('p1', 'Aero Glide 2', 129, [40, 41, 42, 43, 44]),
    Product('p2', 'Court Low', 95, [39, 40, 41, 42, 43, 44, 45]),
    Product('p3', 'Trail Circuit', 149, [41, 42, 43, 44]),
    Product('p4', 'Metro Knit', 119, [40, 41, 42, 43]),
  ];

  final orders = [
    Order('1042', ['Aero Glide 2 (43)'], 'shipped'),
    Order('1039', ['Court Low (42)'], 'delivered'),
  ];

  final cart = <(Product, int)>[];
  String? promo;

  /// Who is signed in. The demo has one account and no password.
  String? shopper;

  /// The app's own sign-in, and the one line the assistant needs from it:
  /// `identify`, so every turn from here is this shopper's, across relaunches.
  Future<void> signIn() async {
    shopper = 'kicks-shopper-1042';
    notifyListeners();
    await Rendel.identify(userId: shopper!, traits: {'name': 'Demo Shopper', 'tier': 'member'});
  }

  /// Sign-out, and `reset`: the next turn is anonymous and the thread is gone.
  void signOut() {
    shopper = null;
    notifyListeners();
    Rendel.reset();
  }

  void addToCart(Product product, int size) {
    cart.add((product, size));
    notifyListeners();
  }

  Map<String, dynamic> cartSnapshot() => {
        'items': cart.length,
        'total': cart.fold<double>(0, (sum, e) => sum + e.$1.price).toStringAsFixed(2),
        if (promo != null) 'promo': promo,
      };

  List<RendelAction> assistantActions() => [
        RendelAction(
          name: 'search_products',
          description: 'Search the sneaker catalog by name and optional maximum price.',
          params: RendelSchema.object({
            'query': RendelSchema.string(description: 'Free text, e.g. "running"').orAbsent,
            'max_price': RendelSchema.number(description: 'Upper price bound in USD').orAbsent,
          }),
          risk: RendelRisk.read,
          handler: (params) async {
            final query = _text(params['query']).toLowerCase();
            final maxPrice = _number(params['max_price']) ?? double.infinity;
            final priced = products.where((p) => p.price <= maxPrice);
            final words = query.split(RegExp(r'\s+')).where((w) => w.length > 2);
            var hits = priced
                .where((p) => words.any((w) => p.name.toLowerCase().contains(w)))
                .toList();
            // Tiny catalog, no category field: a miss on names means "show
            // everything in budget" rather than a dead end.
            if (hits.isEmpty) hits = priced.toList();
            final out = hits
                .map((p) => {
                      'id': p.id,
                      'name': p.name,
                      'price': '\$${p.price.toStringAsFixed(0)}',
                      'sizes': p.sizes,
                    })
                .toList();
            return RendelResult.ok({'products': out});
          },
        ),
        RendelAction(
          name: 'get_order_status',
          description: 'Fetch the delivery status of an order by id.',
          params: RendelSchema.object({'order_id': RendelSchema.string()}),
          risk: RendelRisk.read,
          handler: (params) async {
            final orderId = _text(params['order_id']);
            final order = orders.where((o) => o.id == orderId).firstOrNull;
            if (order == null) return RendelResult.fail('order not found');
            return RendelResult.ok({
              'order_id': order.id,
              'items': order.items,
              'status': order.status,
              'eta': order.status == 'shipped' ? 'Aug 26' : null,
            });
          },
        ),
        RendelAction(
          name: 'add_to_cart',
          description: 'Add a product to the cart in a specific EU size.',
          params: RendelSchema.object({
            'product_id': RendelSchema.string(),
            'size': RendelSchema.integer(description: 'EU size, e.g. 44'),
          }),
          risk: RendelRisk.write,
          confirmTemplate: 'Add {product_id} in size {size} to your cart?',
          handler: (params) async {
            final productId = _text(params['product_id']);
            final product = products.where((p) => p.id == productId).firstOrNull;
            final size = _number(params['size'])?.toInt();
            if (product == null || size == null) return RendelResult.fail('unknown product');
            if (!product.sizes.contains(size)) {
              return RendelResult.fail('size $size is out of stock for ${product.name}');
            }
            cart.add((product, size));
            notifyListeners();
            return RendelResult.ok({'cart_items': cart.length});
          },
        ),
        RendelAction(
          name: 'apply_promo_code',
          description: 'Apply a promo code to the cart.',
          params: RendelSchema.object({'code': RendelSchema.string()}),
          risk: RendelRisk.write,
          confirmTemplate: 'Apply promo code {code}?',
          handler: (params) async {
            final code = _text(params['code']).toUpperCase();
            if (code != 'KICKS10') return RendelResult.fail('code not valid');
            promo = code;
            notifyListeners();
            return RendelResult.ok({'discount': '10%'});
          },
        ),
        RendelAction(
          name: 'cancel_order',
          description: 'Cancel an order that has not shipped yet.',
          params: RendelSchema.object({'order_id': RendelSchema.string()}),
          risk: RendelRisk.destructive,
          confirmTemplate: 'Cancel order {order_id}? This cannot be undone.',
          handler: (params) async {
            final order = orders.where((o) => o.id == params['order_id']).firstOrNull;
            if (order == null) return RendelResult.fail('order not found');
            order.status = 'cancelled';
            notifyListeners();
            return RendelResult.ok({'order_id': order.id, 'refund_eta_days': 5});
          },
        ),
      ];
}

class NeonKicksApp extends StatelessWidget {
  const NeonKicksApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Neon Kicks',
      navigatorKey: kicksNavigator,
      // Every screen counted, and each question asked on the screen it is about.
      navigatorObservers: [Rendel.navigatorObserver],
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFF55733),
          surface: const Color(0xFFFAF7F2),
        ),
        useMaterial3: true,
      ),
      home: const ShopScreen(),
    );
  }
}

class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = KicksStore.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Neon Kicks', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          // Every catalog block with real fixtures, drawn by the real
          // renderer. Faster than talking the model into emitting one.
          IconButton(
            tooltip: 'Component gallery',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const GalleryScreen()),
            ),
            icon: const Icon(Icons.grid_view_rounded),
          ),
          IconButton(
            tooltip: 'Orders',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const OrdersScreen()),
            ),
            icon: const Icon(Icons.receipt_long_outlined),
          ),
          ListenableBuilder(
            listenable: store,
            builder: (_, __) => IconButton(
              tooltip: store.shopper == null ? 'Sign in' : 'Sign out',
              onPressed: store.shopper == null ? store.signIn : store.signOut,
              icon: Icon(store.shopper == null ? Icons.person_outline : Icons.logout_rounded),
            ),
          ),
          ListenableBuilder(
            listenable: store,
            builder: (_, __) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                tooltip: 'Cart',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const CartScreen()),
                ),
                icon: Badge(
                  label: Text('${store.cart.length}'),
                  isLabelVisible: store.cart.isNotEmpty,
                  child: const Icon(Icons.shopping_bag_outlined),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: const RendelLauncher(),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) => GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.78,
          ),
          itemCount: store.products.length,
          itemBuilder: (context, index) {
            final product = store.products[index];
            return GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => ProductScreen(product: product)),
              ),
              child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0x1A0E0E12)),
                borderRadius: BorderRadius.circular(4),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: const LinearGradient(
                          colors: [Color(0x47F55733), Color(0x14F55733)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(product.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    '\$${product.price.toStringAsFixed(0)}',
                    style: const TextStyle(color: Color(0xFF6E645A)),
                  ),
                ],
              ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One sneaker. The assistant opens it as `product_detail`.
class ProductScreen extends StatelessWidget {
  const ProductScreen({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(product.name)),
      floatingActionButton: const RendelLauncher(),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('\$${product.price.toStringAsFixed(0)}', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          const Text('EU sizes in stock'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final size in product.sizes)
                ActionChip(
                  label: Text('$size'),
                  onPressed: () {
                    KicksStore.instance.addToCart(product, size);
                    // An event for Analytics, with flat properties. Taps are counted by themselves.
                    Rendel.track('add_to_cart', {'product': product.name, 'size': size});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${product.name} ($size) is in your cart')),
                    );
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The cart. The assistant opens it as `cart`.
class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = KicksStore.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Cart')),
      floatingActionButton: const RendelLauncher(),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) => ListView(
          children: [
            for (final (product, size) in store.cart)
              ListTile(
                title: Text(product.name),
                subtitle: Text('EU $size'),
                trailing: Text('\$${product.price.toStringAsFixed(0)}'),
              ),
            ListTile(
              title: const Text('Total'),
              subtitle: store.promo == null ? null : Text('Promo ${store.promo}'),
              trailing: Text('\$${store.cartSnapshot()['total']}'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Every order. The assistant opens it as `orders`.
class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = KicksStore.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Orders')),
      floatingActionButton: const RendelLauncher(),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) => ListView(
          children: [
            for (final order in store.orders)
              ListTile(
                title: Text('Order ${order.id}'),
                subtitle: Text(order.items.join(', ')),
                trailing: Text(order.status),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => OrderScreen(order: order)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One order. The assistant opens it as `order_detail`.
class OrderScreen extends StatelessWidget {
  const OrderScreen({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Order ${order.id}')),
      floatingActionButton: const RendelLauncher(),
      body: ListenableBuilder(
        listenable: KicksStore.instance,
        builder: (context, _) => ListView(
          children: [
            for (final item in order.items) ListTile(title: Text(item)),
            ListTile(title: const Text('Status'), trailing: Text(order.status)),
          ],
        ),
      ),
    );
  }
}
