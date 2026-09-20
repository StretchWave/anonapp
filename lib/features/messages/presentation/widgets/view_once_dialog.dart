import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/constants/supabase_constants.dart';
import '../../../../core/services/secure_screen_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/models/message.dart';

/// Full-screen viewer for view-once photos that burn upon closing or after 10 seconds.
/// Automatically blocks screenshots and screen recording via WindowManager.LayoutParams.FLAG_SECURE.
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
        pageBuilder: (ctx, animation, secondaryAnimation) =>
            ViewOnceDialog(message: message, onClosed: onClosed),
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

  // 10-second view once timer
  int _secondsRemaining = 10;
  Timer? _countdownTimer;
  bool _timerStarted = false;

  @override
  void initState() {
    super.initState();
    // Block screenshots and screen recording immediately upon opening
    SecureScreenService.enableSecure();
    _loadMedia();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    // Zeroize sensitive media memory buffer before garbage collection
    if (_bytes != null) {
      _bytes!.fillRange(0, _bytes!.length, 0);
      _bytes = null;
    }
    // Restore normal screenshot and recording capabilities upon exit
    SecureScreenService.disableSecure();
    super.dispose();
  }

  void _startCountdown() {
    if (_timerStarted) return;
    _timerStarted = true;
    _secondsRemaining = 10;

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _secondsRemaining--;
      });

      if (_secondsRemaining <= 0) {
        timer.cancel();
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    });
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
    // 0. If already opened/viewed, access has been removed!
    if (widget.message.isViewOnceOpened) {
      if (mounted) {
        setState(() {
          _bytes = null;
          _isLoading = false;
        });
      }
      return;
    }

    // 1. Try in-memory mediaData first
    if (widget.message.mediaData != null &&
        widget.message.mediaData!.isNotEmpty) {
      final decoded = _safeBase64Decode(widget.message.mediaData!);
      if (decoded != null) {
        if (mounted) {
          setState(() {
            _bytes = decoded;
            _isLoading = false;
          });
          _startCountdown();
        }
        return;
      }
    }

    // 2. If not in memory, fetch fresh from Supabase
    try {
      final row = await SupabaseService.client
          .from(SupabaseConstants.messagesTable)
          .select('media_data, viewed_at')
          .eq('id', widget.message.id)
          .maybeSingle();

      if (row != null && row['viewed_at'] != null) {
        // Already recorded as viewed, remove access
        if (mounted) {
          setState(() {
            _bytes = null;
            _isLoading = false;
          });
        }
        return;
      }

      if (row != null && row['media_data'] != null) {
        final decoded = _safeBase64Decode(row['media_data'] as String);
        if (decoded != null) {
          if (mounted) {
            setState(() {
              _bytes = decoded;
              _isLoading = false;
            });
            _startCountdown();
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('[ViewOnceDialog] Error fetching media: $e');
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
    final isCriticalTime = _secondsRemaining <= 3;
    final progress = _secondsRemaining / 10.0;

    return Scaffold(
      backgroundColor: Colors.black.withAlpha(245),
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
                  Icon(
                    Icons.looks_one_rounded,
                    size: 16,
                    color: AppColors.accent,
                  ),
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
            const SizedBox(width: 10),

            // 10-second Countdown Badge
            if (_bytes != null)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isCriticalTime
                      ? AppColors.error.withAlpha(70)
                      : Colors.white.withAlpha(30),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isCriticalTime ? AppColors.error : Colors.white54,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.timer_outlined,
                      size: 14,
                      color: isCriticalTime ? AppColors.error : Colors.white,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${_secondsRemaining}s',
                      style: TextStyle(
                        color: isCriticalTime ? AppColors.error : Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        bottom: (_bytes != null)
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isCriticalTime ? AppColors.error : AppColors.accent,
                  ),
                  minHeight: 3,
                ),
              )
            : null,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: Center(child: _buildBody())),
            if (widget.message.content != null &&
                widget.message.content!.isNotEmpty)
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
            'Loading photo...',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      );
    }

    if (_bytes != null) {
      return InteractiveViewer(
        minScale: 0.8,
        maxScale: 3.5,
        child: Image.memory(_bytes!, fit: BoxFit.contain),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          widget.message.isViewOnceOpened
              ? Icons.visibility_off_rounded
              : Icons.broken_image_rounded,
          color: Colors.white54,
          size: 48,
        ),
        const SizedBox(height: 12),
        Text(
          widget.message.isViewOnceOpened
              ? 'Photo removed • Already viewed'
              : 'Photo unavailable.',
          style: const TextStyle(color: Colors.white70),
        ),
      ],
    );
  }
}
