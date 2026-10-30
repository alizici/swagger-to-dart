import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:swagtoflut/services/dart_model_generator.dart';
import 'package:swagtoflut/services/swagger_parser.dart';

void main() {
  final parser = SwaggerParser();
  final spec =
      parser.loadSwaggerFromJson(File('test_swagger.json').readAsStringSync());
  final endpoints = parser.parseEndpoints(spec);
  final schemas = parser.getSchemas(spec) ?? {};

  test('parses every endpoint in the sample spec', () {
    expect(endpoints, isNotEmpty);
    expect(endpoints.first.path, '/api/v1/loan/calculate');
    expect(endpoints.first.method, 'POST');
  });

  test('applies the configured class prefix and request import', () {
    final generator = DartModelGenerator(
      schemas: schemas,
      basePrefix: 'Api',
      requestsImport: 'package:demo/requests.dart',
    );
    final code = generator.generateRequestClass(endpoints.first);

    expect(code, contains("import 'package:demo/requests.dart';"));
    expect(code, contains('class ApiLoanCalculationRequest'));
  });

  test('works without a prefix', () {
    final code = DartModelGenerator(schemas: schemas)
        .generateRequestClass(endpoints.first);

    expect(code, contains('class LoanCalculationRequest'));
  });

  test('response class mirrors the request name', () {
    final code = DartModelGenerator(schemas: schemas, basePrefix: 'Api')
        .generateResponseClass(endpoints.first);

    expect(code, contains('ApiLoanCalculationResponse'));
  });
}
