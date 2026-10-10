import 'dart:convert';
import 'dart:io';

/// The protocol's own wire schema, read from packages/protocol, so a test
/// fixture is held to what the server accepts rather than to what this SDK
/// believes it accepts.
///
/// A validator for the part of JSON Schema that zod's export writes, and no
/// more: types, constants, enums, lengths, patterns, bounds, objects and
/// arrays, `anyOf` and `oneOf`. The schema cannot say what zod's refinements
/// say, so [wireBlockErrors] checks the two that wave 2 added by hand.
///
/// Found by walking up from wherever the suite runs, since both this package
/// and its example read it.
final Map<String, dynamic> wireBlockSchema = _protocolSchema('wire-block');

/// What a device may send to `/v1/chat`, for the parts of a request a test
/// builds: a `form_submission`, `context.open_forms`.
final Map<String, dynamic> chatRequestSchema = _protocolSchema('chat-request');

Map<String, dynamic> _protocolSchema(String name) {
  for (Directory? at = Directory.current; at != null && at.parent.path != at.path; at = at.parent) {
    final schema = File('${at.path}/packages/protocol/schemas/$name.schema.json');
    if (schema.existsSync()) return jsonDecode(schema.readAsStringSync()) as Map<String, dynamic>;
  }
  throw StateError('packages/protocol/schemas/$name.schema.json is not above ${Directory.current.path}');
}

/// What is wrong with [block] as the server would send it, or nothing.
List<String> wireBlockErrors(Map<String, dynamic> block) {
  final type = block['type'];
  final branch = (wireBlockSchema['oneOf'] as List).cast<Map<String, dynamic>>().where(
        (schema) => (schema['properties'] as Map)['type']['const'] == type,
      );
  if (branch.isEmpty) return ['no block type "$type" in the protocol'];
  final errors = schemaErrors(block, branch.single);
  final props = block['props'];
  if (props is Map) errors.addAll(_refinements(type, props));
  return errors;
}

/// The zod refinements in packages/protocol/src/blocks.ts that the JSON
/// Schema export leaves out.
List<String> _refinements(Object? type, Map props) {
  final errors = <String>[];
  if (type == 'comparison') {
    final items = (props['items'] as List?)?.length ?? 0;
    for (final row in (props['rows'] as List?) ?? const []) {
      final values = (row as Map)['values'] as List;
      if (values.length != items) errors.add('comparison: every row has one value per item');
      final best = row['best_index'];
      if (best is int && best >= items) errors.add('comparison: best_index names an item');
      if (row['kind'] == 'check' && !values.every((v) => v == 'yes' || v == 'no')) {
        errors.add("comparison: a check row's values are yes or no");
      }
    }
  }
  if (type == 'order_tracker' && props['eta'] != null && props['as_of'] == null) {
    errors.add('order_tracker: eta needs as_of');
  }
  return errors;
}

/// What is wrong with [value] against [schema], each error with the path it
/// was found at.
List<String> schemaErrors(Object? value, Map schema, [String at = r'$']) {
  final errors = <String>[];
  void fail(String why) => errors.add('$at: $why');

  if (schema.containsKey('const') && schema['const'] != value) {
    fail('is not ${schema['const']}');
  }
  if (schema['enum'] case final List options when !options.contains(value)) {
    fail('is not one of $options');
  }
  if (schema['type'] case final Object type) {
    final types = type is List ? type : [type];
    if (!types.any((t) => _isType(value, t as String))) {
      fail('is not ${types.join(' or ')}');
      return errors;
    }
  }
  if (schema['anyOf'] case final List options) {
    if (!options.any((option) => schemaErrors(value, option as Map, at).isEmpty)) {
      fail('matches none of anyOf');
    }
  }
  if (schema['oneOf'] case final List options) {
    final matches = options.where((option) => schemaErrors(value, option as Map, at).isEmpty).length;
    if (matches != 1) fail('matches $matches of oneOf, not one');
  }
  if (value is String) {
    if (schema['minLength'] case final int min when value.length < min) fail('is shorter than $min');
    if (schema['maxLength'] case final int max when value.length > max) fail('is longer than $max');
    if (schema['pattern'] case final String pattern when !RegExp(pattern).hasMatch(value)) {
      fail('does not match $pattern');
    }
  }
  if (value is num) {
    if (schema['minimum'] case final num min when value < min) fail('is under $min');
    if (schema['maximum'] case final num max when value > max) fail('is over $max');
    if (schema['exclusiveMinimum'] case final num min when value <= min) fail('is not over $min');
  }
  if (value is List) {
    if (schema['minItems'] case final int min when value.length < min) fail('has fewer than $min');
    if (schema['maxItems'] case final int max when value.length > max) fail('has more than $max');
    if (schema['items'] case final Map items) {
      for (var i = 0; i < value.length; i++) {
        errors.addAll(schemaErrors(value[i], items, '$at[$i]'));
      }
    }
  }
  if (value is Map) {
    final properties = (schema['properties'] as Map?) ?? const {};
    for (final key in (schema['required'] as List?) ?? const []) {
      if (!value.containsKey(key)) fail('lacks $key');
    }
    final extra = schema['additionalProperties'];
    for (final entry in value.entries) {
      final key = '${entry.key}';
      if (schema['propertyNames'] case final Map names) {
        errors.addAll(schemaErrors(key, names, '$at.$key (name)'));
      }
      if (properties[key] case final Map own) {
        errors.addAll(schemaErrors(entry.value, own, '$at.$key'));
      } else if (extra == false) {
        fail('has no property $key');
      } else if (extra is Map) {
        errors.addAll(schemaErrors(entry.value, extra, '$at.$key'));
      }
    }
  }
  return errors;
}

bool _isType(Object? value, String type) => switch (type) {
      'string' => value is String,
      'number' => value is num,
      'integer' => value is int || (value is double && value == value.roundToDouble()),
      'boolean' => value is bool,
      'object' => value is Map,
      'array' => value is List,
      'null' => value == null,
      _ => false,
    };
