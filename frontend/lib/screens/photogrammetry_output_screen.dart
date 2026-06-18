import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import '../api/api_exception.dart';
import '../api/photogrammetry_api_service.dart';
import '../api/r2v_api.dart';
import '../utils/web_model_viewer_capture.dart';
import 'photo_scan_guided.dart';

class PhotogrammetryOutputScreen extends StatefulWidget {
  const PhotogrammetryOutputScreen({
    super.key,
    required this.jobId,
  });

  final String jobId;

  @override
  State<PhotogrammetryOutputScreen> createState() => _PhotogrammetryOutputScreenState();
}

class _PhotogrammetryOutputScreenState extends State<PhotogrammetryOutputScreen> {
  final GlobalKey _viewerKey = GlobalKey();
  late final String _viewerDomId = 'scan-model-viewer-${widget.jobId}';
  PhotogrammetryJobOutput? _output;
  String? _error;
  String? _downloadMessage;
  String? _assetMessage;
  bool _isLoading = true;
  String? _downloadingFile;
  bool _savingAsset = false;
  bool _publishingAsset = false;

  Future<String> _captureAndUploadThumbnail() async {
    Uint8List? bytes;
    if (kIsWeb) {
      bytes = await captureModelViewerPng(_viewerDomId);
    } else {
      final boundary = _viewerKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 2.0);
        final data = await image.toByteData(format: ImageByteFormat.png);
        if (data != null) {
          bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        }
      }
    }
    if (bytes == null || bytes.isEmpty) {
      throw Exception('Preview is not ready for thumbnail capture yet.');
    }

    final filename = 'scan-${widget.jobId.substring(0, 8)}-thumbnail.png';
    final presign = await r2vMarketplace.presignAssetUpload(
      filename: filename,
      contentType: 'image/png',
      kind: 'thumb',
    );
    final url = presign['url'] ?? '';
    final key = presign['key'] ?? '';
    if (url.isEmpty || key.isEmpty) {
      throw Exception('Unable to prepare thumbnail upload.');
    }
    await r2vMarketplace.uploadToPresignedUrl(url, bytes, contentType: 'image/png');
    return key;
  }

  @override
  void initState() {
    super.initState();
    _loadOutputs();
  }

  Future<void> _loadOutputs() async {
    try {
      final output = await r2vPhotogrammetry.getJobOutput(widget.jobId);
      if (!mounted) {
        return;
      }
      setState(() {
        _output = output;
        _error = null;
        _isLoading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.message;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Unable to load photogrammetry outputs right now.';
        _isLoading = false;
      });
    }
  }

  Future<void> _download(PhotogrammetryOutputFile file) async {
    setState(() {
      _downloadingFile = file.filename;
      _downloadMessage = null;
    });
    try {
      final location = await r2vPhotogrammetry.downloadOutputFile(file);
      if (!mounted) {
        return;
      }
      setState(() {
        _downloadMessage = 'Saved ${file.filename.split('/').last} to $location';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _downloadMessage = 'Download failed for ${file.filename}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _downloadingFile = null;
        });
      }
    }
  }

  Future<void> _saveAsset({required bool publish}) async {
    final title = 'Scan ${widget.jobId.substring(0, 8)}';
    setState(() {
      _assetMessage = null;
      _savingAsset = !publish;
      _publishingAsset = publish;
    });
    try {
      final thumbObjectKey = await _captureAndUploadThumbnail();
      final asset = await r2vMarketplace.createFromPhotogrammetryJob(
        jobId: widget.jobId,
        title: title,
        publish: publish,
        description: 'Generated from a photogrammetry scan.',
        thumbObjectKey: thumbObjectKey,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _assetMessage = publish
            ? 'Published $title to the marketplace.'
            : 'Saved $title to your profile drafts.';
      });
      if (publish) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Published ${asset.title}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = error.toString().replaceFirst('Exception: ', '').trim();
      setState(() {
        _assetMessage = message.isEmpty
            ? (publish
                ? 'Unable to publish this scan right now.'
                : 'Unable to save this scan to your profile right now.')
            : message;
      });
    } finally {
      if (mounted) {
        setState(() {
          _savingAsset = false;
          _publishingAsset = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final glbFile = _output?.files.where((file) => file.isGlb).firstOrNull;

    return Stack(
      children: [
        const Positioned.fill(child: NebulaMeshBackground()),
        Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _OutputTopBar(
                        title: 'Scan Outputs',
                        subtitle: 'Preview and download reconstructed assets',
                        onBack: () => Navigator.pop(context),
                      ),
                      const SizedBox(height: 18),
                      Expanded(
                        child: _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : _error != null
                                ? _OutputShell(
                                    child: Center(
                                      child: Text(
                                        _error!,
                                        style: const TextStyle(color: Color(0xFFFF7B7B), fontWeight: FontWeight.w700),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  )
                                : _OutputShell(
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          flex: 3,
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Job ${widget.jobId}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 24,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              const SizedBox(height: 10),
                                              Text(
                                                'Your reconstruction package is ready. Download the formats you need or inspect the `.glb` preview here.',
                                                style: TextStyle(
                                                  color: Colors.white.withOpacity(0.72),
                                                  fontSize: 15,
                                                  height: 1.35,
                                                ),
                                              ),
                                              const SizedBox(height: 18),
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: ElevatedButton.icon(
                                                      onPressed: _savingAsset || _publishingAsset
                                                          ? null
                                                          : () => _saveAsset(publish: false),
                                                      icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                                                      label: Text(_savingAsset ? 'Saving...' : 'Save to Profile'),
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor: const Color(0xFF4CC9F0),
                                                        foregroundColor: Colors.white,
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius: BorderRadius.circular(16),
                                                        ),
                                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: ElevatedButton.icon(
                                                      onPressed: _savingAsset || _publishingAsset
                                                          ? null
                                                          : () => _saveAsset(publish: true),
                                                      icon: const Icon(Icons.storefront_rounded, size: 18),
                                                      label: Text(_publishingAsset ? 'Publishing...' : 'Publish'),
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor: const Color(0xFF8A4FFF),
                                                        foregroundColor: Colors.white,
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius: BorderRadius.circular(16),
                                                        ),
                                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              if (_assetMessage != null) ...[
                                                const SizedBox(height: 10),
                                                Text(
                                                  _assetMessage!,
                                                  style: const TextStyle(
                                                    color: Color(0xFF9AE6B4),
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                              const SizedBox(height: 18),
                                              Expanded(
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    color: Colors.white.withOpacity(0.05),
                                                    borderRadius: BorderRadius.circular(24),
                                                    border: Border.all(color: Colors.white.withOpacity(0.10)),
                                                  ),
                                                  child: glbFile == null
                                                      ? Center(
                                                          child: Text(
                                                            'No GLB preview available for this job.',
                                                            style: TextStyle(color: Colors.white.withOpacity(0.72)),
                                                          ),
                                                        )
                                                      : ClipRRect(
                                                          borderRadius: BorderRadius.circular(24),
                                                          child: RepaintBoundary(
                                                            key: _viewerKey,
                                                            child: ModelViewer(
                                                              id: _viewerDomId,
                                                              src: r2vPhotogrammetry.buildAbsoluteUrl(glbFile.downloadUrl),
                                                              alt: 'Photogrammetry preview',
                                                              ar: false,
                                                              autoRotate: true,
                                                              cameraControls: true,
                                                              backgroundColor: Colors.transparent,
                                                              environmentImage: 'neutral',
                                                              exposure: 1.0,
                                                              shadowIntensity: 0.8,
                                                              shadowSoftness: 1,
                                                            ),
                                                          ),
                                                        ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 18),
                                        Expanded(
                                          flex: 2,
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              _OutputBadgeRow(fileCount: _output?.files.length ?? 0),
                                              const SizedBox(height: 14),
                                              Expanded(
                                                child: Container(
                                                  padding: const EdgeInsets.all(18),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white.withOpacity(0.06),
                                                    borderRadius: BorderRadius.circular(24),
                                                    border: Border.all(color: Colors.white.withOpacity(0.10)),
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        'Available Files',
                                                        style: TextStyle(
                                                          color: Colors.white.withOpacity(0.92),
                                                          fontWeight: FontWeight.w800,
                                                          fontSize: 16,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 12),
                                                      Expanded(
                                                        child: ListView.separated(
                                                          itemCount: _output?.files.length ?? 0,
                                                          separatorBuilder: (_, __) => Divider(
                                                            color: Colors.white.withOpacity(0.08),
                                                            height: 18,
                                                          ),
                                                          itemBuilder: (context, index) {
                                                            final file = _output!.files[index];
                                                            final downloading = _downloadingFile == file.filename;
                                                            return Row(
                                                              crossAxisAlignment: CrossAxisAlignment.start,
                                                              children: [
                                                                Container(
                                                                  width: 42,
                                                                  height: 42,
                                                                  decoration: BoxDecoration(
                                                                    color: const Color(0xFFBC70FF).withOpacity(0.18),
                                                                    borderRadius: BorderRadius.circular(14),
                                                                  ),
                                                                  child: const Icon(
                                                                    Icons.insert_drive_file_rounded,
                                                                    color: Color(0xFFBC70FF),
                                                                  ),
                                                                ),
                                                                const SizedBox(width: 12),
                                                                Expanded(
                                                                  child: Column(
                                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                                    children: [
                                                                      Text(
                                                                        file.filename,
                                                                        style: const TextStyle(
                                                                          color: Colors.white,
                                                                          fontWeight: FontWeight.w700,
                                                                        ),
                                                                      ),
                                                                      const SizedBox(height: 4),
                                                                      Text(
                                                                        _formatBytes(file.fileSize),
                                                                        style: TextStyle(color: Colors.white.withOpacity(0.6)),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                                const SizedBox(width: 10),
                                                                ElevatedButton(
                                                                  onPressed: downloading ? null : () => _download(file),
                                                                  style: ElevatedButton.styleFrom(
                                                                    backgroundColor: const Color(0xFF8A4FFF),
                                                                    foregroundColor: Colors.white,
                                                                    shape: RoundedRectangleBorder(
                                                                      borderRadius: BorderRadius.circular(14),
                                                                    ),
                                                                  ),
                                                                  child: Text(downloading ? 'Saving...' : 'Download'),
                                                                ),
                                                              ],
                                                            );
                                                          },
                                                        ),
                                                      ),
                                                      if (_downloadMessage != null) ...[
                                                        const SizedBox(height: 14),
                                                        Text(
                                                          _downloadMessage!,
                                                          style: const TextStyle(
                                                            color: Color(0xFF9AE6B4),
                                                            fontWeight: FontWeight.w700,
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _OutputTopBar extends StatelessWidget {
  const _OutputTopBar({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.28),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: Row(
            children: [
              InkWell(
                onTap: onBack,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.10),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.12)),
                  ),
                  child: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Colors.white),
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.view_in_ar_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OutputShell extends StatelessWidget {
  const _OutputShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.18),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _OutputBadgeRow extends StatelessWidget {
  const _OutputBadgeRow({required this.fileCount});

  final int fileCount;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _OutputBadge(
          text: '$fileCount file${fileCount == 1 ? '' : 's'}',
          color: const Color(0xFF4CC9F0),
        ),
        const _OutputBadge(
          text: 'Ready to download',
          color: Color(0xFF22C55E),
        ),
      ],
    );
  }
}

class _OutputBadge extends StatelessWidget {
  const _OutputBadge({
    required this.text,
    required this.color,
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
