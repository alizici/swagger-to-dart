import '../models/swagger_endpoint.dart';

/// Turns OpenAPI endpoints and schemas into typed Dart request/response
/// classes (json_serializable style).
class DartModelGenerator {
  final Map<String, dynamic> schemas;

  /// Prepended to every generated class name, e.g. `Api` -> `ApiCreateUserRequest`.
  final String basePrefix;

  /// Import line for the base request classes in the target project.
  final String requestsImport;

  DartModelGenerator({
    required this.schemas,
    this.basePrefix = '',
    this.requestsImport = 'package:your_app/network/requests.dart',
  });

  String generateRequestClass(SwaggerEndpoint endpoint) {
    final className = _generateRequestClassName(endpoint);
    final parametersClassName = '${className}Parameters';
    final buffer = StringBuffer();

    // Add imports
    buffer.writeln("import '$requestsImport';");
    buffer.writeln('');

    // Main request class
    final requestType = _getRequestType(endpoint.method);
    buffer.writeln('class $className extends $requestType {');

    if (_hasRequestBody(endpoint) || _hasParameters(endpoint)) {
      buffer.writeln('  $className($parametersClassName parameters)');
      buffer.writeln('      : super("${endpoint.path}", parameters.toMap())${_needsValidation(endpoint) ? ' {' : ';'}');
      if (_needsValidation(endpoint)) {
        buffer.writeln('    // Validate required fields before sending request');
        buffer.writeln('    parameters.validate();');
        buffer.writeln('  }');
      }
    } else {
      buffer.writeln('  $className()');
      buffer.writeln('      : super("${endpoint.path}", {});');
    }

    buffer.writeln('}');

    // Generate parameters class if needed
    if (_hasRequestBody(endpoint) || _hasParameters(endpoint)) {
      buffer.writeln('');
      _generateParametersClass(buffer, endpoint, parametersClassName);
    }

    // Generate nested classes if needed
    _generateNestedRequestClasses(buffer, endpoint);

    return buffer.toString();
  }

  void _generateParametersClass(StringBuffer buffer, SwaggerEndpoint endpoint, String className) {
    buffer.writeln('class $className {');

    final fields = <String, FieldInfo>{};
    final required = <String>{};

    // Collect fields from request body
    if (endpoint.requestBody.isNotEmpty) {
      final content = endpoint.requestBody['content'] as Map<String, dynamic>?;
      if (content != null) {
        final schema = content['application/json']?['schema'];
        if (schema != null) {
          _collectFields(schema, fields, required, schemas);
        }
      }
    }

    // Collect fields from parameters
    if (endpoint.parameters.isNotEmpty) {
      for (var param in endpoint.parameters) {
        final name = param['name'] as String;
        final isRequired = param['required'] ?? false;
        final type = _mapSwaggerTypeToString(param['schema']);

        fields[name] = FieldInfo(
          type: type,
          originalName: name,
          dartName: _toCamelCase(name),
          isRequired: isRequired,
        );

        if (isRequired) {
          required.add(name);
        }
      }
    }

    // Generate fields
    fields.forEach((name, fieldInfo) {
      if (fieldInfo.isRequired) {
        if (fieldInfo.type == 'String' || fieldInfo.type.startsWith('List<') || fieldInfo.type == 'Map<String, dynamic>') {
          buffer.writeln('  final ${fieldInfo.type} ${fieldInfo.dartName};');
        } else {
          buffer.writeln('  late ${fieldInfo.type} ${fieldInfo.dartName};');
        }
      } else {
        buffer.writeln('  final ${fieldInfo.type}? ${fieldInfo.dartName};');
      }
    });

    buffer.writeln('');

    // Generate constructor
    buffer.writeln('  $className({');
    fields.forEach((name, fieldInfo) {
      if (fieldInfo.isRequired) {
        if (fieldInfo.type == 'String' || fieldInfo.type.startsWith('List<') ||
            fieldInfo.isComplexType || fieldInfo.type == 'Map<String, dynamic>') {
          buffer.writeln('    required this.${fieldInfo.dartName},');
        } else {
          // Numeric types with defaults
          final defaultValue = _getDefaultValue(fieldInfo.type);
          buffer.writeln('    this.${fieldInfo.dartName} = $defaultValue,');
        }
      } else {
        buffer.writeln('    this.${fieldInfo.dartName},');
      }
    });
    buffer.writeln('  });');

    // Generate validate method if there are required fields
    if (required.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('  /// Validates all required fields');
      buffer.writeln('  void validate() {');

      fields.forEach((name, fieldInfo) {
        if (fieldInfo.isRequired) {
          _generateValidationForField(buffer, fieldInfo);
        }
      });

      buffer.writeln('  }');
    }

    // Generate toMap method
    buffer.writeln('');
    buffer.writeln('  Map<String, dynamic> toMap() {');

    if (fields.isEmpty) {
      buffer.writeln('    return {};');
    } else {
      buffer.writeln('    Map<String, dynamic> map = {};');

      // Add default values first
      _addDefaultMapValues(buffer, endpoint);

      // Add fields
      fields.forEach((name, fieldInfo) {
        final jsonName = fieldInfo.originalName;
        final dartName = fieldInfo.dartName;

        if (fieldInfo.isRequired) {
          if (fieldInfo.isComplexType) {
            buffer.writeln('    map["$jsonName"] = $dartName.toMap();');
          } else if (fieldInfo.type == 'int' || fieldInfo.type == 'double') {
            buffer.writeln('    if ($dartName > 0) {');
            buffer.writeln('      map["$jsonName"] = $dartName${fieldInfo.needsToString ? '.toString()' : ''};');
            buffer.writeln('    }');
          } else {
            buffer.writeln('    map["$jsonName"] = $dartName;');
          }
        } else {
          if (fieldInfo.isComplexType) {
            buffer.writeln('    if ($dartName != null) map["$jsonName"] = $dartName.toMap();');
          } else {
            buffer.writeln('    if ($dartName != null) map["$jsonName"] = $dartName;');
          }
        }
      });

      buffer.writeln('    return map;');
    }

    buffer.writeln('  }');
    buffer.writeln('}');
  }

  String generateResponseClass(SwaggerEndpoint endpoint) {
    final className = _generateResponseClassName(endpoint);
    final buffer = StringBuffer();

    // Add imports
    buffer.writeln("import 'package:json_annotation/json_annotation.dart';");
    buffer.writeln('');
    buffer.writeln("part '../generated/responses/${_toSnakeCase(className)}.g.dart';");
    buffer.writeln('');

    // Main response class
    buffer.writeln('@JsonSerializable(fieldRename: FieldRename.pascal, explicitToJson: true)');
    buffer.writeln('class $className {');

    final response200 = endpoint.responses['200'] ?? endpoint.responses['201'];
    if (response200 != null) {
      final content = response200['content'] as Map<String, dynamic>?;
      if (content != null) {
        final schema = content['application/json']?['schema'];
        if (schema != null) {
          _generateResponseFields(buffer, schema, schemas);
          buffer.writeln('');
          _generateResponseConstructor(buffer, className, schema, schemas);
          buffer.writeln('');
          _generateResponseFactoryMethods(buffer, className);

          // Add toString override
          buffer.writeln('');
          buffer.writeln('  @override');
          buffer.writeln('  String toString() {');
          buffer.writeln('    return toJson().toString();');
          buffer.writeln('  }');
        }
      }
    }

    buffer.writeln('}');

    // Generate nested response classes
    _generateNestedResponseClasses(buffer, endpoint);

    return buffer.toString();
  }

  void _generateResponseFields(StringBuffer buffer, Map<String, dynamic> schema, Map<String, dynamic> allSchemas) {
    final fields = <String, FieldInfo>{};
    final required = <String>{};

    _collectFields(schema, fields, required, allSchemas);

    fields.forEach((name, fieldInfo) {
      // Add JsonKey annotation if needed for custom conversion
      if (_needsCustomJsonKey(fieldInfo)) {
        buffer.writeln('  @JsonKey(fromJson: _safe${_toPascalCase(fieldInfo.type)}FromJson)');
      }

      buffer.writeln('  final ${fieldInfo.type}${fieldInfo.isRequired ? '' : '?'} ${fieldInfo.dartName};');
    });

    // Add custom conversion methods if needed
    if (_hasFieldsNeedingConversion(fields)) {
      buffer.writeln('');
      _generateCustomConversionMethods(buffer, fields);
    }
  }

  void _generateResponseConstructor(StringBuffer buffer, String className, Map<String, dynamic> schema, Map<String, dynamic> allSchemas) {
    final fields = <String, FieldInfo>{};
    final required = <String>{};

    _collectFields(schema, fields, required, allSchemas);

    buffer.writeln('  const $className({');

    fields.forEach((name, fieldInfo) {
      if (fieldInfo.isRequired) {
        buffer.writeln('    required this.${fieldInfo.dartName},');
      } else {
        buffer.writeln('    this.${fieldInfo.dartName},');
      }
    });

    buffer.writeln('  });');
  }

  void _generateResponseFactoryMethods(StringBuffer buffer, String className) {
    buffer.writeln('  factory $className.fromJson(Map<String, dynamic> json) =>');
    buffer.writeln('      _\$${className}FromJson(json);');
    buffer.writeln('');
    buffer.writeln('  Map<String, dynamic> toJson() => _\$${className}ToJson(this);');
  }

  void _collectFields(Map<String, dynamic> schema, Map<String, FieldInfo> fields, Set<String> required, Map<String, dynamic> allSchemas) {
    final ref = schema['\$ref'] as String?;

    if (ref != null) {
      final schemaName = ref.split('/').last;
      if (allSchemas.containsKey(schemaName)) {
        _collectFields(allSchemas[schemaName], fields, required, allSchemas);
      }
      return;
    }

    final properties = schema['properties'] as Map<String, dynamic>? ?? {};
    final requiredList = List<String>.from(schema['required'] ?? []);

    properties.forEach((name, property) {
      final fieldInfo = _createFieldInfo(name, property, requiredList.contains(name), allSchemas);
      fields[name] = fieldInfo;
      if (fieldInfo.isRequired) {
        required.add(name);
      }
    });
  }

  FieldInfo _createFieldInfo(String name, Map<String, dynamic> property, bool isRequired, Map<String, dynamic> allSchemas) {
    final type = _getFieldType(property, allSchemas);
    final dartName = _toCamelCase(name);

    return FieldInfo(
      type: type,
      originalName: name,
      dartName: dartName,
      isRequired: isRequired,
      isComplexType: _isComplexType(property, allSchemas),
      needsToString: _needsStringConversion(property),
    );
  }

  void _generateNestedRequestClasses(StringBuffer buffer, SwaggerEndpoint endpoint) {
    if (endpoint.requestBody.isEmpty) return;

    final content = endpoint.requestBody['content'] as Map<String, dynamic>?;
    if (content == null) return;

    final schema = content['application/json']?['schema'];
    if (schema == null) return;

    final processedClasses = <String>{};
    _generateNestedClassesFromSchema(buffer, schema, schemas, processedClasses, true);
  }

  void _generateNestedResponseClasses(StringBuffer buffer, SwaggerEndpoint endpoint) {
    final response = endpoint.responses['200'] ?? endpoint.responses['201'];
    if (response == null) return;

    final content = response['content'] as Map<String, dynamic>?;
    if (content == null) return;

    final schema = content['application/json']?['schema'];
    if (schema == null) return;

    final processedClasses = <String>{};
    _generateNestedClassesFromSchema(buffer, schema, schemas, processedClasses, false);
  }

  void _generateNestedClassesFromSchema(
    StringBuffer buffer,
    Map<String, dynamic> schema,
    Map<String, dynamic> allSchemas,
    Set<String> processedClasses,
    bool isRequest,
  ) {
    // Process direct schema reference
    final ref = schema['\$ref'] as String?;
    if (ref != null) {
      final schemaName = ref.split('/').last;
      if (allSchemas.containsKey(schemaName) && !processedClasses.contains(schemaName)) {
        processedClasses.add(schemaName);
        final nestedSchema = allSchemas[schemaName];
        _generateSingleNestedClass(buffer, schemaName, nestedSchema, allSchemas, isRequest);

        // Recursively process this schema's properties
        _generateNestedClassesFromSchema(buffer, nestedSchema, allSchemas, processedClasses, isRequest);
      }
    }

    // Process properties
    final properties = schema['properties'] as Map<String, dynamic>? ?? {};
    properties.forEach((name, property) {
      final propRef = property['\$ref'] as String?;
      if (propRef != null) {
        final propSchemaName = propRef.split('/').last;
        if (allSchemas.containsKey(propSchemaName) && !processedClasses.contains(propSchemaName)) {
          processedClasses.add(propSchemaName);
          final nestedSchema = allSchemas[propSchemaName];
          _generateSingleNestedClass(buffer, propSchemaName, nestedSchema, allSchemas, isRequest);

          // Recursively process nested schema
          _generateNestedClassesFromSchema(buffer, nestedSchema, allSchemas, processedClasses, isRequest);
        }
      }

      // Check for array items
      if (property['type'] == 'array') {
        final items = property['items'] as Map<String, dynamic>?;
        if (items != null) {
          final itemRef = items['\$ref'] as String?;
          if (itemRef != null) {
            final itemSchemaName = itemRef.split('/').last;
            if (allSchemas.containsKey(itemSchemaName) && !processedClasses.contains(itemSchemaName)) {
              processedClasses.add(itemSchemaName);
              final nestedSchema = allSchemas[itemSchemaName];
              _generateSingleNestedClass(buffer, itemSchemaName, nestedSchema, allSchemas, isRequest);

              // Recursively process nested schema
              _generateNestedClassesFromSchema(buffer, nestedSchema, allSchemas, processedClasses, isRequest);
            }
          }
        }
      }
    });
  }

  void _generateSingleNestedClass(
    StringBuffer buffer,
    String className,
    Map<String, dynamic> schema,
    Map<String, dynamic> allSchemas,
    bool isRequest,
  ) {
    buffer.writeln('');

    if (!isRequest) {
      buffer.writeln('@JsonSerializable(fieldRename: FieldRename.pascal, explicitToJson: true)');
    }

    buffer.writeln('class $className {');

    final fields = <String, FieldInfo>{};
    final required = <String>{};
    _collectFields(schema, fields, required, allSchemas);

    // Generate fields
    fields.forEach((name, fieldInfo) {
      if (isRequest) {
        if (fieldInfo.isRequired) {
          buffer.writeln('  final ${fieldInfo.type} ${fieldInfo.dartName};');
        } else {
          buffer.writeln('  final ${fieldInfo.type}? ${fieldInfo.dartName};');
        }
      } else {
        buffer.writeln('  final ${fieldInfo.type}${fieldInfo.isRequired ? '' : '?'} ${fieldInfo.dartName};');
      }
    });

    buffer.writeln('');

    // Generate constructor
    if (isRequest) {
      buffer.writeln('  $className({');
      fields.forEach((name, fieldInfo) {
        if (fieldInfo.isRequired) {
          buffer.writeln('    required this.${fieldInfo.dartName},');
        } else {
          buffer.writeln('    this.${fieldInfo.dartName},');
        }
      });
      buffer.writeln('  });');

      // Generate validate method for request classes
      if (required.isNotEmpty) {
        buffer.writeln('');
        buffer.writeln('  /// Validates all required fields in $className');
        buffer.writeln('  void validate() {');
        fields.forEach((name, fieldInfo) {
          if (fieldInfo.isRequired) {
            _generateValidationForField(buffer, fieldInfo);
          }
        });
        buffer.writeln('  }');
      }

      // Generate toMap method for request classes
      buffer.writeln('');
      buffer.writeln('  Map<String, dynamic> toMap() {');
      buffer.writeln('    return {');
      fields.forEach((name, fieldInfo) {
        final jsonName = fieldInfo.originalName;
        final dartName = fieldInfo.dartName;

        if (fieldInfo.isRequired) {
          if (fieldInfo.isComplexType) {
            buffer.writeln('      "$jsonName": $dartName.toMap(),');
          } else {
            buffer.writeln('      "$jsonName": $dartName,');
          }
        } else {
          if (fieldInfo.isComplexType) {
            buffer.writeln('      if ($dartName != null) "$jsonName": $dartName.toMap(),');
          } else {
            buffer.writeln('      if ($dartName != null) "$jsonName": $dartName,');
          }
        }
      });
      buffer.writeln('    };');
      buffer.writeln('  }');
    } else {
      // Response class constructor
      buffer.writeln('  const $className({');
      fields.forEach((name, fieldInfo) {
        if (fieldInfo.isRequired) {
          buffer.writeln('    required this.${fieldInfo.dartName},');
        } else {
          buffer.writeln('    this.${fieldInfo.dartName},');
        }
      });
      buffer.writeln('  });');

      // Factory methods for response classes
      buffer.writeln('');
      buffer.writeln('  factory $className.fromJson(Map<String, dynamic> json) =>');
      buffer.writeln('      _\$${className}FromJson(json);');
      buffer.writeln('');
      buffer.writeln('  Map<String, dynamic> toJson() => _\$${className}ToJson(this);');
    }

    buffer.writeln('}');
  }

  void _generateValidationForField(StringBuffer buffer, FieldInfo fieldInfo) {
    if (fieldInfo.type == 'String') {
      buffer.writeln('    assert(${fieldInfo.dartName}.isNotEmpty, \'${fieldInfo.dartName} is required\');');
    } else if (fieldInfo.type == 'int' || fieldInfo.type == 'double') {
      buffer.writeln('    assert(${fieldInfo.dartName} >= 0, \'${fieldInfo.dartName} cannot be negative\');');
    } else if (fieldInfo.isComplexType) {
      buffer.writeln('    // Validate nested object');
      buffer.writeln('    ${fieldInfo.dartName}.validate();');
    }
  }

  void _generateCustomConversionMethods(StringBuffer buffer, Map<String, FieldInfo> fields) {
    final generatedMethods = <String>{};

    fields.values.where((f) => _needsCustomJsonKey(f)).forEach((fieldInfo) {
      final methodName = '_safe${_toPascalCase(fieldInfo.type)}FromJson';
      if (!generatedMethods.contains(methodName)) {
        generatedMethods.add(methodName);

        if (fieldInfo.type == 'int') {
          buffer.writeln('  static int? $methodName(dynamic value) {');
          buffer.writeln('    if (value == null) return null;');
          buffer.writeln('    if (value is int) return value;');
          buffer.writeln('    if (value is String) return int.tryParse(value);');
          buffer.writeln('    if (value is num) return value.toInt();');
          buffer.writeln('    return null;');
          buffer.writeln('  }');
        }
      }
    });
  }

  String _getRequestType(String method) {
    switch (method.toUpperCase()) {
      case 'GET':
        return 'JsonGetRequest';
      case 'POST':
        return 'JsonPostRequest';
      case 'PUT':
        return 'PutRequest';
      case 'DELETE':
        return 'JsonDeleteRequest';
      default:
        return 'JsonPostRequest';
    }
  }

  String _getFieldType(Map<String, dynamic> property, Map<String, dynamic> allSchemas) {
    final ref = property['\$ref'] as String?;
    if (ref != null) {
      return ref.split('/').last;
    }

    final type = property['type'] as String?;
    switch (type) {
      case 'string':
        final format = property['format'] as String?;
        if (format == 'date-time') return 'DateTime';
        return 'String';
      case 'integer':
        return 'int';
      case 'number':
        return 'double';
      case 'boolean':
        return 'bool';
      case 'array':
        final items = property['items'] as Map<String, dynamic>?;
        if (items != null) {
          final itemType = _getFieldType(items, allSchemas);
          return 'List<$itemType>';
        }
        return 'List<dynamic>';
      case 'object':
        final additionalProperties = property['additionalProperties'];
        if (additionalProperties != null) {
          return 'Map<String, dynamic>';
        }
        return 'Map<String, dynamic>';
      default:
        return 'dynamic';
    }
  }

  String _mapSwaggerTypeToString(Map<String, dynamic>? schema) {
    if (schema == null) return 'dynamic';
    return _getFieldType(schema, schemas);
  }

  bool _hasRequestBody(SwaggerEndpoint endpoint) {
    return endpoint.requestBody.isNotEmpty;
  }

  bool _hasParameters(SwaggerEndpoint endpoint) {
    return endpoint.parameters.isNotEmpty;
  }

  bool _needsValidation(SwaggerEndpoint endpoint) {
    if (endpoint.requestBody.isNotEmpty) {
      final content = endpoint.requestBody['content'] as Map<String, dynamic>?;
      if (content != null) {
        final schema = content['application/json']?['schema'];
        if (schema != null) {
          final ref = schema['\$ref'] as String?;
          if (ref != null) {
            final schemaName = ref.split('/').last;
            if (schemas.containsKey(schemaName)) {
              final refSchema = schemas[schemaName];
              return (refSchema['required'] as List?)?.isNotEmpty ?? false;
            }
          }
          return (schema['required'] as List?)?.isNotEmpty ?? false;
        }
      }
    }
    return endpoint.parameters.any((p) => p['required'] == true);
  }

  bool _isComplexType(Map<String, dynamic> property, Map<String, dynamic> allSchemas) {
    final ref = property['\$ref'] as String?;
    return ref != null && allSchemas.containsKey(ref.split('/').last);
  }

  bool _needsStringConversion(Map<String, dynamic> property) {
    // Check if this field needs toString() in toMap
    return false; // Implement based on actual needs
  }

  bool _needsCustomJsonKey(FieldInfo fieldInfo) {
    // Determine if field needs custom JSON conversion
    return false; // Implement based on actual needs
  }

  bool _hasFieldsNeedingConversion(Map<String, FieldInfo> fields) {
    return fields.values.any((f) => _needsCustomJsonKey(f));
  }

  void _addDefaultMapValues(StringBuffer buffer, SwaggerEndpoint endpoint) {
    // Add any default values that should always be in the map
    // Example: map["State"] = "Active";
  }

  String _getDefaultValue(String type) {
    switch (type) {
      case 'int':
        return '0';
      case 'double':
        return '0.0';
      case 'bool':
        return 'false';
      default:
        return '""';
    }
  }

  String _generateRequestClassName(SwaggerEndpoint endpoint) {
    // Examples (prefix "Api"):
    // /api/v1/Loan/LoanAccounts/Calculate -> ApiLoanCalculationRequest
    // /api/v1/Loan/LoanAccounts/Basics -> ApiLoanBasicInfoRequest
    // /api/v1/Deposit/DepositAccounts -> ApiCreateDepositAccountRequest

    if (endpoint.operationId != null) {
      final op = endpoint.operationId!;

      // Special handling for common operation patterns
      if (op.toLowerCase().contains('calculate')) {
        final entity = op.replaceAll(RegExp(r'calculate', caseSensitive: false), '');
        return '$basePrefix${_toPascalCase(entity)}CalculationRequest';
      } else if (op.toLowerCase().contains('getby')) {
        final entity = op.replaceAll(RegExp(r'getby', caseSensitive: false), '');
        return '${basePrefix}Get${_toPascalCase(entity)}Request';
      } else if (op.toLowerCase().contains('create')) {
        final entity = op.replaceAll(RegExp(r'create', caseSensitive: false), '');
        return '${basePrefix}Create${_toPascalCase(entity)}Request';
      } else if (op.toLowerCase().contains('update')) {
        final entity = op.replaceAll(RegExp(r'update', caseSensitive: false), '');
        return '${basePrefix}Update${_toPascalCase(entity)}Request';
      } else if (op.toLowerCase().contains('delete')) {
        final entity = op.replaceAll(RegExp(r'delete', caseSensitive: false), '');
        return '${basePrefix}Delete${_toPascalCase(entity)}Request';
      }

      // Default: clean and format
      final cleanOp = op.replaceAll('_', '');
      return '$basePrefix${_toPascalCase(cleanOp)}Request';
    }

    // Path-based naming
    final pathParts = endpoint.path.split('/').where((p) => p.isNotEmpty && !p.contains('{'));
    final relevantParts = pathParts.skip(3).toList(); // Skip /api/v1/{domain}

    if (relevantParts.isEmpty) {
      final domain = pathParts.length > 3 ? pathParts.elementAt(3) : 'General';
      return '$basePrefix${_toPascalCase(domain)}Request';
    }

    // Build name from path parts
    String className = basePrefix;

    // Handle common patterns
    final lastPart = relevantParts.last.toLowerCase();
    if (lastPart.contains('basic')) {
      className += '${_toPascalCase(relevantParts.first)}BasicInfoRequest';
    } else if (lastPart.contains('detail')) {
      className += '${_toPascalCase(relevantParts.first)}DetailInfoRequest';
    } else if (lastPart.contains('calculate')) {
      className += '${_toPascalCase(relevantParts.first.replaceAll('Accounts', ''))}CalculationRequest';
    } else if (lastPart.contains('info')) {
      className += '${_toPascalCase(relevantParts.first)}InfoRequest';
    } else {
      // Default: use method prefix
      final methodPrefix = _getMethodPrefix(endpoint.method);
      className += '$methodPrefix${relevantParts.map((p) => _toPascalCase(p)).join('')}Request';
    }

    return className;
  }

  String _generateResponseClassName(SwaggerEndpoint endpoint) {
    // Response names follow similar pattern but without the prefix for nested types
    final requestName = _generateRequestClassName(endpoint);

    // Remove 'Request' and replace with 'Response'
    String responseName = requestName.replaceAll('Request', 'Response');

    // Some responses don't have the prefix (for nested/shared types)
    if (basePrefix.isNotEmpty &&
        (endpoint.operationId?.toLowerCase().contains('enum') ?? false)) {
      responseName = responseName.replaceFirst(basePrefix, '');
    }

    return responseName;
  }

  String _getMethodPrefix(String method) {
    switch (method.toUpperCase()) {
      case 'GET':
        return 'Get';
      case 'POST':
        return 'Create';
      case 'PUT':
        return 'Update';
      case 'DELETE':
        return 'Delete';
      case 'PATCH':
        return 'Patch';
      default:
        return '';
    }
  }


  String _toPascalCase(String text) {
    if (text.isEmpty) return text;
    final words = text.split(RegExp(r'[_\-\s/]'));
    return words.map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1);
    }).join();
  }

  String _toCamelCase(String text) {
    if (text.isEmpty) return text;

    // Keep original casing for already camelCase fields
    if (text[0].toLowerCase() == text[0] && !text.contains('_')) {
      return text;
    }

    // Convert PascalCase to camelCase
    if (text[0].toUpperCase() == text[0] && !text.contains('_')) {
      return text[0].toLowerCase() + text.substring(1);
    }

    // Convert snake_case to camelCase
    final pascal = _toPascalCase(text);
    if (pascal.isEmpty) return pascal;
    return pascal[0].toLowerCase() + pascal.substring(1);
  }

  String _toSnakeCase(String text) {
    return text.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (match) => '_${match.group(1)!.toLowerCase()}',
    ).replaceFirst(RegExp(r'^_'), '');
  }
}

class FieldInfo {
  final String type;
  final String originalName;
  final String dartName;
  final bool isRequired;
  final bool isComplexType;
  final bool needsToString;

  FieldInfo({
    required this.type,
    required this.originalName,
    required this.dartName,
    required this.isRequired,
    this.isComplexType = false,
    this.needsToString = false,
  });
}