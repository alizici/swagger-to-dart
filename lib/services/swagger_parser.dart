import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/swagger_endpoint.dart';

class SwaggerParser {
  Future<Map<String, dynamic>> loadSwaggerFromUrl(String url) async {
    try {
      // Convert Swagger HTML URL to JSON URL if needed
      String jsonUrl = url;
      if (url.contains('/swagger/index.html')) {
        jsonUrl = url.replaceAll('/swagger/index.html', '/swagger/v1/swagger.json');
      } else if (!url.endsWith('.json')) {
        // Try common swagger.json paths
        if (url.endsWith('/')) {
          jsonUrl = '${url}swagger.json';
        } else {
          jsonUrl = '$url/swagger.json';
        }
      }

      final response = await http.get(Uri.parse(jsonUrl));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load Swagger documentation: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Connection failed: $e\n\nPlease download the swagger.json file manually and use "Load File" button instead.');
    }
  }

  Map<String, dynamic> loadSwaggerFromJson(String jsonContent) {
    return json.decode(jsonContent);
  }

  List<SwaggerEndpoint> parseEndpoints(Map<String, dynamic> swagger) {
    List<SwaggerEndpoint> endpoints = [];

    final paths = swagger['paths'] as Map<String, dynamic>? ?? {};

    paths.forEach((path, pathItem) {
      final pathData = pathItem as Map<String, dynamic>;

      pathData.forEach((method, operation) {
        if (operation is Map<String, dynamic> &&
            ['get', 'post', 'put', 'delete', 'patch'].contains(method.toLowerCase())) {

          endpoints.add(SwaggerEndpoint(
            path: path,
            method: method.toUpperCase(),
            operationId: operation['operationId'],
            requestBody: operation['requestBody'] ?? {},
            responses: operation['responses'] ?? {},
            parameters: List<Map<String, dynamic>>.from(operation['parameters'] ?? []),
          ));
        }
      });
    });

    return endpoints;
  }

  Map<String, dynamic>? getComponents(Map<String, dynamic> swagger) {
    return swagger['components'] as Map<String, dynamic>?;
  }

  Map<String, dynamic>? getSchemas(Map<String, dynamic> swagger) {
    final components = getComponents(swagger);
    return components?['schemas'] as Map<String, dynamic>?;
  }
}