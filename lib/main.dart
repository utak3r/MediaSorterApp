import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:reorderable_grid_view/reorderable_grid_view.dart';

void main() {
  runApp(const MediaSorterApp());
}

class MediaSorterApp extends StatelessWidget {
  const MediaSorterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Media Sorter Lite',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const MediaSorterHome(),
    );
  }
}

class MediaSorterHome extends StatefulWidget {
  const MediaSorterHome({super.key});

  @override
  State<MediaSorterHome> createState() => _MediaSorterHomeState();
}

class _MediaSorterHomeState extends State<MediaSorterHome> {
  String? _currentDirectoryPath;
  List<FileSystemEntity> _files = [];
  bool _isLoading = false;

  final List<String> _imageExtensions = ['.jpg', '.jpeg', '.png', '.webp'];
  final List<String> _videoExtensions = ['.mp4', '.mov', '.avi'];

  bool _isMediaFile(FileSystemEntity entity) {
    if (entity is! File) return false;
    final ext = path.extension(entity.path).toLowerCase();
    return _imageExtensions.contains(ext) || _videoExtensions.contains(ext);
  }

  bool _isVideo(FileSystemEntity entity) {
    final ext = path.extension(entity.path).toLowerCase();
    return _videoExtensions.contains(ext);
  }

  Future<void> _pickDirectory() async {
    String? selectedDirectory = await FilePicker.getDirectoryPath();
    if (selectedDirectory != null) {
      await _loadDirectory(selectedDirectory);
    }
  }

  Future<void> _loadDirectory(String dirPath) async {
    setState(() {
      _isLoading = true;
      _currentDirectoryPath = dirPath;
      _files.clear();
    });

    final dir = Directory(dirPath);
    List<FileSystemEntity> foundFiles = [];
    try {
      final entries = dir.listSync();
      for (var entry in entries) {
        if (_isMediaFile(entry)) {
          foundFiles.add(entry);
        }
      }

      // Try to load order.json
      final orderFile = File(path.join(dirPath, 'order.json'));
      if (orderFile.existsSync()) {
        try {
          final content = orderFile.readAsStringSync();
          final List<dynamic> orderList = jsonDecode(content);
          final List<String> orderedNames = orderList.cast<String>();

          // Sort foundFiles based on orderedNames
          foundFiles.sort((a, b) {
            final nameA = path.basename(a.path);
            final nameB = path.basename(b.path);
            final indexA = orderedNames.indexOf(nameA);
            final indexB = orderedNames.indexOf(nameB);

            if (indexA != -1 && indexB != -1) {
              return indexA.compareTo(indexB);
            } else if (indexA != -1) {
              return -1;
            } else if (indexB != -1) {
              return 1;
            } else {
              return nameA.compareTo(nameB);
            }
          });
        } catch (e) {
          debugPrint('Failed to parse order.json: $e');
          foundFiles.sort(
            (a, b) => path.basename(a.path).compareTo(path.basename(b.path)),
          );
        }
      } else {
        // default alphabetical sort
        foundFiles.sort(
          (a, b) => path.basename(a.path).compareTo(path.basename(b.path)),
        );
      }

      setState(() {
        _files = foundFiles;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading directory: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveOrder() async {
    if (_currentDirectoryPath == null || _files.isEmpty) return;

    final fileNames = _files.map((e) => path.basename(e.path)).toList();

    // 1. Print to console
    debugPrint(fileNames.toString());

    // 2. Copy to clipboard
    final clipboardStr = fileNames.map((e) => '"$e"').join(', ');
    await Clipboard.setData(ClipboardData(text: clipboardStr));

    // 3. Save to order.json
    final orderFile = File(path.join(_currentDirectoryPath!, 'order.json'));
    try {
      await orderFile.writeAsString(jsonEncode(fileNames));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order saved to order.json and clipboard.'),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving order.json: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving order: $e')));
      }
    }
  }

  void _showLightbox(FileSystemEntity file) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Material(
            color: Colors.black87,
            child: Stack(
              children: [
                Center(
                  child: _isVideo(file)
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.play_circle_outline,
                              size: 100,
                              color: Colors.white54,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              path.basename(file.path),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        )
                      : Image.file(File(file.path), fit: BoxFit.contain),
                ),
                Positioned(
                  top: 40,
                  right: 40,
                  child: IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 30,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Media Sorter App'),
        actions: [
          if (_currentDirectoryPath != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _loadDirectory(_currentDirectoryPath!),
              tooltip: 'Refresh directory',
            ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _pickDirectory,
            tooltip: 'Open folder',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _currentDirectoryPath == null
          ? const Center(child: Text('Select a folder to scan.'))
          : _files.isEmpty
          ? const Center(child: Text('No media files found.'))
          : Padding(
              padding: const EdgeInsets.all(8.0),
              child: ReorderableGridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _files.length,
                dragStartDelay: Duration.zero,
                itemBuilder: (context, index) {
                  final file = _files[index];
                  final fileName = path.basename(file.path);
                  final isVideo = _isVideo(file);

                  return Card(
                    key: ValueKey(file.path),
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: GestureDetector(
                      onTap: () => _showLightbox(file),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (isVideo)
                            Container(
                              color: Colors.grey.shade900,
                              child: const Center(
                                child: Icon(
                                  Icons.play_arrow,
                                  size: 48,
                                  color: Colors.white54,
                                ),
                              ),
                            )
                          else
                            Image.file(File(file.path), fit: BoxFit.cover),
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              color: Colors.black.withAlpha(
                                153,
                              ), // 0.6 * 255 = ~153
                              padding: const EdgeInsets.symmetric(
                                vertical: 4,
                                horizontal: 8,
                              ),
                              child: Text(
                                fileName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    final element = _files.removeAt(oldIndex);
                    _files.insert(newIndex, element);
                  });
                },
              ),
            ),
      floatingActionButton: _files.isNotEmpty
          ? FloatingActionButton(
              onPressed: _saveOrder,
              tooltip: 'Save order to json & copy to clipboard',
              child: const Icon(Icons.check),
            )
          : null,
    );
  }
}
