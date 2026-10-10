import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';

/// The code the setup agent writes into an app, compiled.
///
/// Every snippet the setup file (`rendel-setup.md`) hands an agent is prose:
/// a string in a TypeScript module (`apps/web/src/console/lib/snippets.ts`)
/// that the Dart analyzer has never seen. So a rename in the SDK would break
/// it silently, and the first to find out would be an agent writing code that
/// does not compile into somebody's app.
///
/// This file is the same code as real Dart. `flutter analyze` and `flutter
/// test` fail here the moment the API moves, which is the whole point; the
/// companion check in `apps/web/src/console/lib/snippets.test.ts` asserts that
/// what the setup file WRITES is character-for-character what this file
/// COMPILES.
///
/// Keep the snippet bodies below verbatim. If one has to change, change it
/// here first and let the string check tell you where else it is written down.

/// A stand-in for the host app's own API client, so the snippet can read the
/// way a real integration does rather than being rewritten around a mock.
class _Api {
  Future<_Order> fetchOrder(Object? id) async => _Order();
}

class _Order {
  Map<String, dynamic> toJson() => {'status': 'in_transit'};
}

final api = _Api();

class _User {
  final String id = 'u_42';
}

final user = _User();

class _Auth {
  final String? accessToken = 'jwt';
}

final auth = _Auth();

/// The host app's own root widget, which the install snippet runs.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// ———————————————————— setup file, step 2: install ————————————————————

Future<void> installMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Rendel.init(
    // Your app's key: Rendel console → Settings → API keys → Copy.
    // Start on the test key; swap in the live key for release builds.
    appKey: 'rd_pk_test_…',
    // The languages the copilot answers in. Put yours here:
    //   ['tr']        Turkish only, whatever the user writes in
    //   ['tr', 'en']  Turkish or English, whichever the user writes;
    //                 anything else is answered in the first, Turkish
    //   ['en']        English only
    // Leave out config and it answers in whatever the user writes.
    config: RendelConfig(
      languages: ['tr'],
      // If people sign in to your app: their current token, from your own
      // sign-in code, so the copilot reaches your API as them — no API key.
      // Null when nobody is signed in.
      // userToken: () async => auth.accessToken,
    ),
  );
  runApp(const MyApp());
}

// ———————————————————— setup file, step 3: identity ————————————————————

Future<void> identifySnippet() async {
  await Rendel.identify(
    userId: user.id,
    traits: {'plan': 'pro'},
  );
}

// ——————— the install snippet's commented token line, switched on ———————

Future<void> userTokenSnippet() async {
  await Rendel.init(
    // Your app's key: Rendel console → Settings → API keys → Copy.
    appKey: 'rd_pk_test_...',
    config: RendelConfig(
      languages: ['tr'],
      userToken: () async => auth.accessToken,
    ),
  );
}

// ———————————————————— setup file: an action in code ————————————————————

void registerActionSnippet() {
  Rendel.registerAction(RendelAction(
    name: 'get_order_status',
    description: 'Fetch the delivery status of an order',
    params: RendelSchema.object({'order_id': RendelSchema.string()}),
    risk: RendelRisk.read,
    handler: (params) async {
      final order = await api.fetchOrder(params['order_id']);
      return RendelResult.ok(order.toJson());
    },
  ));
}

// ———————————————————— setup file, step 2: a way in ————————————————————

void openSnippet(BuildContext context) {
  Rendel.open(context);
}

void main() {
  test('the documented action compiles and carries what the docs claim', () {
    final action = RendelAction(
      name: 'get_order_status',
      description: 'Fetch the delivery status of an order',
      params: RendelSchema.object({'order_id': RendelSchema.string()}),
      risk: RendelRisk.read,
      handler: (params) async => RendelResult.ok(const {}),
    );
    expect(action.name, 'get_order_status');
    expect(action.risk, RendelRisk.read);
    // The default the reference page states.
    expect(action.timeout, const Duration(seconds: 15));
  });

  test('the schema helpers the docs name all exist', () {
    // Every one of these appears in `/docs/reference/sdk`.
    RendelSchema.object({
      'order_id': RendelSchema.string(description: 'The order number'),
      'reason': RendelSchema.enumOf(const ['damaged', 'wrong_item', 'other']).optional,
      'quantity': RendelSchema.integer().optional,
      'flag': RendelSchema.boolean(),
      'amount': RendelSchema.number(),
      'tags': RendelSchema.list(RendelSchema.string()),
      'anything': RendelSchema.raw(const {'type': 'string'}),
    });
  });

  test('a failing result carries the sentence the model is meant to read', () {
    final result = RendelResult.fail('no order with that number');
    expect(result.ok, isFalse);
    expect(result.error, 'no order with that number');
  });

  test('the default host is the one the docs print', () {
    // The docs name this URL in three places. It was pointed at a domain that
    // did not resolve once, and every out-of-the-box integration failed with
    // a connection error the docs never explained.
    expect(const RendelConfig().apiBaseUrl, 'https://api.rendel.ai');
  });
}
