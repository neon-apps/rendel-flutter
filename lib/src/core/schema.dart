/// Minimal JSON Schema builder for action parameters.
///
/// Only the subset the manifest needs: objects with typed properties and
/// required tracking. The output maps 1:1 onto JSON Schema draft 2020-12 so
/// the server can validate model-proposed params against it.
class RendelSchema {
  RendelSchema._(this._schema, {bool optional = false}) : _optional = optional;

  final Map<String, dynamic> _schema;
  final bool _optional;

  Map<String, dynamic> toJson() => _schema;

  static RendelSchema string({String? description}) =>
      RendelSchema._({'type': 'string', if (description != null) 'description': description});

  static RendelSchema number({String? description}) =>
      RendelSchema._({'type': 'number', if (description != null) 'description': description});

  static RendelSchema integer({String? description}) =>
      RendelSchema._({'type': 'integer', if (description != null) 'description': description});

  static RendelSchema boolean({String? description}) =>
      RendelSchema._({'type': 'boolean', if (description != null) 'description': description});

  static RendelSchema enumOf(List<String> values, {String? description}) => RendelSchema._({
        'type': 'string',
        'enum': values,
        if (description != null) 'description': description,
      });

  /// A list of [items], e.g. `RendelSchema.list(RendelSchema.string())`.
  ///
  /// Absent until now, which made "the ids the user picked" impossible to
  /// declare: the only way to express it was a comma-joined string, and every
  /// handler that did paid for it in parsing.
  static RendelSchema list(
    RendelSchema items, {
    String? description,
    int? minItems,
    int? maxItems,
  }) =>
      RendelSchema._({
        'type': 'array',
        'items': items.toJson(),
        if (minItems != null) 'minItems': minItems,
        if (maxItems != null) 'maxItems': maxItems,
        if (description != null) 'description': description,
      });

  /// An escape hatch: any JSON Schema this builder does not model.
  ///
  /// The server validates whatever the manifest declares, so a schema written
  /// by hand is as enforceable as one built here. Use it for the shapes that
  /// are genuinely beyond the subset (oneOf, patterns, nested constraints)
  /// rather than reaching for a string and parsing it yourself.
  static RendelSchema raw(Map<String, dynamic> schema) => RendelSchema._(schema);

  /// Marks a property as optional inside [object].
  ///
  /// ```dart
  /// RendelSchema.object({
  ///   'order_id': RendelSchema.string(),
  ///   'note': RendelSchema.string().optional,
  /// })
  /// ```
  RendelSchema get optional => RendelSchema._(_schema, optional: true);

  /// The original spelling of [optional]. Both do the same thing; this one
  /// stays so existing code keeps compiling.
  RendelSchema get orAbsent => optional;

  static RendelSchema object(Map<String, RendelSchema> properties, {String? description}) {
    final required = [
      for (final entry in properties.entries)
        if (!entry.value._optional) entry.key,
    ]..sort();
    return RendelSchema._({
      'type': 'object',
      'additionalProperties': false,
      'properties': {
        for (final entry in properties.entries) entry.key: entry.value.toJson(),
      },
      if (required.isNotEmpty) 'required': required,
      if (description != null) 'description': description,
    });
  }
}
