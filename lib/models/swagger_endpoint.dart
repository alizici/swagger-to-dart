class SwaggerEndpoint {
  final String path;
  final String method;
  final String? operationId;
  final Map<String, dynamic> requestBody;
  final Map<String, dynamic> responses;
  final List<Map<String, dynamic>> parameters;
  bool selected;

  SwaggerEndpoint({
    required this.path,
    required this.method,
    this.operationId,
    required this.requestBody,
    required this.responses,
    required this.parameters,
    this.selected = false,
  });
}