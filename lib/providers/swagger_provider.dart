import 'package:flutter/foundation.dart';
import '../models/swagger_endpoint.dart';
import '../services/swagger_parser.dart';
import '../services/dart_model_generator.dart';

class SwaggerProvider extends ChangeNotifier {
  final SwaggerParser _parser = SwaggerParser();
  List<SwaggerEndpoint> _endpoints = [];
  Map<String, dynamic> _swaggerJson = {};
  String _generatedCode = '';
  bool _isLoading = false;
  String? _error;
  String _classPrefix = '';

  List<SwaggerEndpoint> get endpoints => _endpoints;
  String get generatedCode => _generatedCode;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get classPrefix => _classPrefix;

  void setClassPrefix(String value) {
    _classPrefix = value.trim();
    notifyListeners();
  }

  Future<void> loadSwaggerFromUrl(String url) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _swaggerJson = await _parser.loadSwaggerFromUrl(url);
      _endpoints = _parser.parseEndpoints(_swaggerJson);
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  void loadSwaggerFromJson(String jsonContent) {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _swaggerJson = _parser.loadSwaggerFromJson(jsonContent);
      _endpoints = _parser.parseEndpoints(_swaggerJson);
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  void toggleEndpointSelection(int index) {
    if (index >= 0 && index < _endpoints.length) {
      _endpoints[index].selected = !_endpoints[index].selected;
      notifyListeners();
    }
  }

  void generateCode() {
    final selectedEndpoints = _endpoints.where((e) => e.selected).toList();
    final schemas = _parser.getSchemas(_swaggerJson) ?? {};

    final generator = DartModelGenerator(schemas: schemas, basePrefix: _classPrefix);
    final buffer = StringBuffer();

    for (var endpoint in selectedEndpoints) {
      // Generate Request
      buffer.writeln('// Request for ${endpoint.method} ${endpoint.path}');
      buffer.writeln('// ${'-' * 60}');
      buffer.writeln(generator.generateRequestClass(endpoint));
      buffer.writeln('');
      buffer.writeln('// ${'=' * 60}');
      buffer.writeln('');

      // Generate Response as separate item
      buffer.writeln('// Response for ${endpoint.method} ${endpoint.path}');
      buffer.writeln('// ${'-' * 60}');
      buffer.writeln(generator.generateResponseClass(endpoint));
      buffer.writeln('');
      buffer.writeln('// ${'=' * 60}');
      buffer.writeln('');
    }

    _generatedCode = buffer.toString();
    notifyListeners();
  }

  void clearSelection() {
    for (var endpoint in _endpoints) {
      endpoint.selected = false;
    }
    _generatedCode = '';
    notifyListeners();
  }
}