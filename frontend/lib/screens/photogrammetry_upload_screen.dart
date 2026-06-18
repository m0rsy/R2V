import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api/api_exception.dart';
import '../api/photogrammetry_api_service.dart';
import '../api/r2v_api.dart';

class PhotogrammetryUploadScreen extends StatefulWidget {
  const PhotogrammetryUploadScreen({super.key});

  @override
  State<PhotogrammetryUploadScreen> createState() => _PhotogrammetryUploadScreenState();
}

class _PhotogrammetryUploadScreenState extends State<PhotogrammetryUploadScreen> {
  final List<PhotogrammetryUploadFile> _selectedFiles = [];
  bool _isPicking = false;
  bool _isSubmitting = false;
  String? _error;

  Future<void> _pickImages() async {
    setState(() {
      _isPicking = true;
      _error = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      );
      if (result == null) {
        return;
      }

      final nextFiles = result.files
          .where((file) => file.bytes != null)
          .map(
            (file) => PhotogrammetryUploadFile(
              filename: file.name,
              bytes: file.bytes!,
              contentType: _contentTypeFor(file.name),
            ),
          )
          .toList();

      if (!mounted) {
        return;
      }
      setState(() {
        _selectedFiles
          ..clear()
          ..addAll(nextFiles);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Unable to pick images right now.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isPicking = false;
        });
      }
    }
  }

  Future<void> _startProcessing() async {
    if (_selectedFiles.isEmpty) {
      setState(() {
        _error = 'Select at least one image to start.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final created = await r2vPhotogrammetry.createJob(_selectedFiles);
      if (!mounted) {
        return;
      }
      Navigator.pushNamed(
        context,
        '/photogrammetry/status',
        arguments: {'jobId': created.jobId},
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Unable to start photogrammetry processing.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Photogrammetry Upload')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Upload a photo set',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Choose multiple images, review them, then send the set to the reconstruction pipeline.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: _isPicking ? null : _pickImages,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(_isPicking ? 'Opening picker...' : 'Choose Images'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _selectedFiles.isEmpty
                        ? null
                        : () {
                            setState(() {
                              _selectedFiles.clear();
                            });
                          },
                    icon: const Icon(Icons.clear_all),
                    label: const Text('Clear'),
                  ),
                  FilledButton(
                    onPressed: _isSubmitting ? null : _startProcessing,
                    child: Text(_isSubmitting ? 'Starting...' : 'Start Processing'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Selected images: ${_selectedFiles.length}'),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ],
              const SizedBox(height: 16),
              if (_selectedFiles.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: Text('No images selected yet.')),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _selectedFiles.length,
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 220,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1,
                      ),
                      itemBuilder: (context, index) {
                        final file = _selectedFiles[index];
                        return _PreviewTile(file: file);
                      },
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _contentTypeFor(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }
}

class _PreviewTile extends StatelessWidget {
  const _PreviewTile({required this.file});

  final PhotogrammetryUploadFile file;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: GridTile(
        footer: Container(
          color: Colors.black54,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(
            file.filename,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white),
          ),
        ),
        child: Image.memory(
          file.bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}
