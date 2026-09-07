import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/constants/supabase_constants.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/models/message.dart';

/// Full-screen viewer for view-once photos that burn upon closing.
class ViewOnceDialog extends StatefulWidget {
  const ViewOnceDialog({
    super.key,
    required this.message,
    required this.onClosed,
  });

  final Message message;
  final VoidCallback onClosed;

  static Future<void> show(
    BuildContext context, {
    required Message message,
    required VoidCallback onClosed,
  }) async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        pageBuilder: (ctx, animation, secondaryAnimation) => ViewOnceDialog(
          message: message,
          onClosed: onClosed,
        ),
      ),
    );
    onClosed();
  }

  @override
  State<ViewOnceDialog> createState() => _ViewOnceDialogState();
}

class _ViewOnceDialogState extends State<ViewOnceDialog> {
  Uint8List? _bytes;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  Uint8List? _safeBase64Decode(String raw) {
    try {
      var clean = raw.trim();
      if (clean.contains(',')) {
        clean = clean.split(',').last;
      }
      return base64Decode(clean);
    } catch (e) {
      debugPrint('[ViewOnceDialog] Base64 decode error: $e');
      return null;
    }
  }

  Future<void> _loadMedia() async {
    // 1. Try in-memory mediaData first
    if (widget.message.mediaData != null && widget.message.mediaData!.isNotEmpty) {
      final decoded = _safeBase64Decode(widget.message.mediaData!);
      if (decoded != null) {
        if (mounted) {
          setState(() {
            _bytes = decoded;
            _isLoading = false;
          });
        }
        return;
      }
    }

    // 2. If not in memory and not marked viewed, fetch fresh from Supabase
    if (!widget.message.isViewOnceOpened) {
      try {
        final row = await SupabaseService.client
            .from(SupabaseConstants.messagesTable)
            .select('media_data, viewed_at')
            .eq('id', widget.message.id)
            .maybeSingle();

        if (row != null && row['media_data'] != null) {
          final decoded = _safeBase64Decode(row['media_data'] as String);
          if (decoded != null) {
            if (mounted) {
              setState(() {
                _bytes = decoded;
                _isLoading = false;
              });
            }
            return;
          }
        }
      } catch (e) {
        debugPrint('[ViewOnceDialog] Error fetching media: $e');
      }
    }

    // 3. Media is expired or unavailable
    if (mounted) {
      setState(() {
        _bytes = null;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withAlpha(240),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.accent.withAlpha(51),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.accent, width: 1),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.looks_one_rounded, size: 16, color: AppColors.accent),
                  SizedBox(width: 6),
                  Text(
                    'View Once',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.visibility_off_outlined, color: Colors.white70, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'This photo will be permanently deleted after closing.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: _buildBody(),
              ),
            ),
            if (widget.message.content != null && widget.message.content!.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                width: double.infinity,
                color: Colors.black54,
                child: Text(
                  widget.message.content!,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
          ),
          SizedBox(height: 16),
          Text(
            'Opening secure photo...',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      );
    }

    if (_bytes != null) {
      return InteractiveViewer(
        minScale: 0.8,
        maxScale: 3.5,
        child: Image.memory(
          _bytes!,
          fit: BoxFit.contain,
        ),
      );
    }

    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.lock_outline_rounded, color: Colors.white54, size: 48),
        SizedBox(height: 12),
        Text(
          'This photo has already expired.',
          style: TextStyle(color: Colors.white70),
        ),
      ],
    );
  }
}
