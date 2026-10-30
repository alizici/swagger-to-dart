import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'providers/swagger_provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SwaggerProvider(),
      child: MaterialApp(
        title: 'Swagger to Flutter',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const SwaggerToFlutterScreen(),
      ),
    );
  }
}

class SwaggerToFlutterScreen extends StatefulWidget {
  const SwaggerToFlutterScreen({super.key});

  @override
  State<SwaggerToFlutterScreen> createState() => _SwaggerToFlutterScreenState();
}

class _SwaggerToFlutterScreenState extends State<SwaggerToFlutterScreen> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  String? _selectedOutputPath;
  String _searchQuery = '';

  @override
  void dispose() {
    _urlController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Swagger to Flutter Code Generator'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Consumer<SwaggerProvider>(
        builder: (context, provider, child) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _urlController,
                        decoration: const InputDecoration(
                          labelText: 'Swagger URL',
                          hintText: 'https://example.com/swagger.json',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: provider.isLoading ? null : () async {
                        if (_urlController.text.isNotEmpty) {
                          await provider.loadSwaggerFromUrl(_urlController.text);
                        }
                      },
                      child: const Text('Load URL'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: provider.isLoading ? null : () async {
                        FilePickerResult? result = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['json'],
                        );

                        if (result != null) {
                          File file = File(result.files.single.path!);
                          String contents = await file.readAsString();
                          provider.loadSwaggerFromJson(contents);
                        }
                      },
                      child: const Text('Load File'),
                    ),
                  ],
                ),
              ),
              if (provider.error != null)
                Container(
                  color: Colors.red.shade100,
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    'Error: ${provider.error}',
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Card(
                        margin: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      const Text(
                                        'Endpoints',
                                        style: TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      const Spacer(),
                                      if (provider.endpoints.isNotEmpty)
                                        TextButton(
                                          onPressed: () => provider.clearSelection(),
                                          child: const Text('Clear Selection'),
                                        ),
                                    ],
                                  ),
                                  if (provider.endpoints.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: _searchController,
                                      decoration: const InputDecoration(
                                        hintText: 'Search endpoints...',
                                        prefixIcon: Icon(Icons.search),
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                        border: OutlineInputBorder(),
                                      ),
                                      onChanged: (value) {
                                        setState(() {
                                          _searchQuery = value.toLowerCase();
                                        });
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Expanded(
                              child: provider.isLoading
                                  ? const Center(child: CircularProgressIndicator())
                                  : provider.endpoints.isEmpty
                                      ? const Center(child: Text('No endpoints loaded'))
                                      : () {
                                          // Filter endpoints based on search query
                                          final filteredEndpoints = provider.endpoints.where((endpoint) {
                                            if (_searchQuery.isEmpty) return true;

                                            final searchLower = _searchQuery.toLowerCase();
                                            final methodMatch = endpoint.method.toLowerCase().contains(searchLower);
                                            final pathMatch = endpoint.path.toLowerCase().contains(searchLower);
                                            final operationMatch = endpoint.operationId?.toLowerCase().contains(searchLower) ?? false;

                                            return methodMatch || pathMatch || operationMatch;
                                          }).toList();

                                          if (filteredEndpoints.isEmpty) {
                                            return const Center(
                                              child: Text('No endpoints match your search'),
                                            );
                                          }

                                          return ListView.builder(
                                            itemCount: filteredEndpoints.length,
                                            itemBuilder: (context, index) {
                                              final endpoint = filteredEndpoints[index];
                                              final actualIndex = provider.endpoints.indexOf(endpoint);

                                              return ListTile(
                                                leading: Checkbox(
                                                  value: endpoint.selected,
                                                  onChanged: (_) => provider.toggleEndpointSelection(actualIndex),
                                                ),
                                                title: Text(
                                                  '${endpoint.method} ${endpoint.path}',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w500,
                                                    color: _getMethodColor(endpoint.method),
                                                  ),
                                                ),
                                                subtitle: endpoint.operationId != null
                                                    ? Text(endpoint.operationId!)
                                                    : null,
                                                onTap: () => provider.toggleEndpointSelection(actualIndex),
                                              );
                                            },
                                          );
                                        }(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Card(
                        margin: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              child: const Text(
                                'Generated Code Preview',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            Expanded(
                              child: provider.generatedCode.isEmpty
                                  ? const Center(child: Text('Select endpoints and click Generate'))
                                  : SingleChildScrollView(
                                      padding: const EdgeInsets.all(12),
                                      child: SelectableText(
                                        provider.generatedCode,
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () async {
                        String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
                        if (selectedDirectory != null) {
                          setState(() {
                            _selectedOutputPath = selectedDirectory;
                          });
                        }
                      },
                      icon: const Icon(Icons.folder_open),
                      label: Text(_selectedOutputPath ?? 'Select Output Folder'),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 160,
                      child: TextField(
                        decoration: const InputDecoration(
                          labelText: 'Class prefix',
                          hintText: 'e.g. Api',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: provider.setClassPrefix,
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: provider.endpoints.where((e) => e.selected).isEmpty
                          ? null
                          : () {
                              provider.generateCode();
                            },
                      icon: const Icon(Icons.code),
                      label: const Text('Generate Code'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: provider.generatedCode.isEmpty || _selectedOutputPath == null
                          ? null
                          : () async {
                              await _saveGeneratedCode(provider);
                            },
                      icon: const Icon(Icons.save),
                      label: const Text('Save Files'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Color _getMethodColor(String method) {
    switch (method.toUpperCase()) {
      case 'GET':
        return Colors.blue;
      case 'POST':
        return Colors.green;
      case 'PUT':
        return Colors.orange;
      case 'DELETE':
        return Colors.red;
      case 'PATCH':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  Future<void> _saveGeneratedCode(SwaggerProvider provider) async {
    if (_selectedOutputPath == null) return;

    try {
      final outputDir = Directory(_selectedOutputPath!);

      if (!outputDir.existsSync()) {
        outputDir.createSync(recursive: true);
      }

      // Split by separator to get individual code blocks
      final codes = provider.generatedCode.split('// ${'=' * 60}');

      for (var code in codes) {
        if (code.trim().isEmpty) continue;

        final lines = code.trim().split('\n');
        String? fileName;
        String? fileContent;

        // Check the first line to determine if it's Request or Response
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].contains('// Request for')) {

            // Find the class definition
            for (var j = i + 1; j < lines.length; j++) {
              if (lines[j].startsWith('class ') && lines[j].contains('Request')) {
                final match = RegExp(r'class (\w+)').firstMatch(lines[j]);
                if (match != null) {
                  fileName = '${_toSnakeCase(match.group(1)!)}.dart';

                  // Get only the request code content (skip header comments)
                  final contentLines = <String>[];
                  bool startCollecting = false;

                  for (var k = 0; k < lines.length; k++) {
                    // Skip initial comment lines
                    if (lines[k].startsWith('// Request for') ||
                        lines[k].startsWith('// ---')) {
                      continue;
                    }
                    // Start collecting from first import or class
                    if (lines[k].startsWith('import ') || lines[k].startsWith('class ')) {
                      startCollecting = true;
                    }
                    if (startCollecting) {
                      contentLines.add(lines[k]);
                    }
                  }

                  fileContent = contentLines.join('\n');
                  break;
                }
              }
            }
            break;
          } else if (lines[i].contains('// Response for')) {

            // Find the class definition
            for (var j = i + 1; j < lines.length; j++) {
              if (lines[j].startsWith('@JsonSerializable') ||
                  (lines[j].startsWith('class ') && lines[j].contains('Response'))) {

                // Extract class name
                String? className;
                for (var k = j; k < lines.length && k < j + 2; k++) {
                  if (lines[k].contains('class ')) {
                    final match = RegExp(r'class (\w+)').firstMatch(lines[k]);
                    if (match != null) {
                      className = match.group(1);
                      break;
                    }
                  }
                }

                if (className != null) {
                  fileName = '${_toSnakeCase(className)}.dart';

                  // Get only the response code content (skip header comments)
                  final contentLines = <String>[];
                  bool startCollecting = false;

                  for (var k = 0; k < lines.length; k++) {
                    // Skip initial comment lines
                    if (lines[k].startsWith('// Response for') ||
                        lines[k].startsWith('// ---')) {
                      continue;
                    }
                    // Start collecting from first import or annotation
                    if (lines[k].startsWith('import ') ||
                        lines[k].startsWith('part ') ||
                        lines[k].startsWith('@JsonSerializable')) {
                      startCollecting = true;
                    }
                    if (startCollecting) {
                      contentLines.add(lines[k]);
                    }
                  }

                  fileContent = contentLines.join('\n');
                  break;
                }
              }
            }
            break;
          }
        }

        if (fileName != null && fileContent != null && fileContent.trim().isNotEmpty) {
          final file = File('${outputDir.path}/$fileName');
          await file.writeAsString(fileContent.trim());
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Files saved successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving files: $e')),
        );
      }
    }
  }

  String _toSnakeCase(String text) {
    return text.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (match) => '_${match.group(1)!.toLowerCase()}',
    ).replaceFirst(RegExp(r'^_'), '');
  }
}