import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Player for voice note messages with play/pause button, waveform bar, and duration.
class VoicePlayer extends StatefulWidget {
  const VoicePlayer({
    super.key,
    required this.base64Audio,
    required this.isMine,
    this.totalDurationMs,
  });

  final String base64Audio;
  final bool isMine;
  final int? totalDurationMs;

  @override
  State<VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<VoicePlayer> {
  late final AudioPlayer _player;
  bool _isPlaying = false;
  double _playbackRate = 1.0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription<PlayerState>? _stateSubscription;
  StreamSubscription<Duration>? _posSubscription;
  StreamSubscription<Duration>? _durSubscription;
  Uint8List? _audioBytes;

  void _cycleSpeed() {
    setState(() {
      if (_playbackRate == 1.0) {
        _playbackRate = 1.5;
      } else if (_playbackRate == 1.5) {
        _playbackRate = 2.0;
      } else {
        _playbackRate = 1.0;
      }
    });
    _player.setPlaybackRate(_playbackRate);
  }

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    if (widget.totalDurationMs != null) {
      _duration = Duration(milliseconds: widget.totalDurationMs!);
    }

    try {
      _audioBytes = base64Decode(widget.base64Audio);
    } catch (_) {
      _audioBytes = null;
    }

    _stateSubscription = _player.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
          if (state == PlayerState.completed) {
            _position = Duration.zero;
          }
        });
      }
    });

    _posSubscription = _player.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });

    _durSubscription = _player.onDurationChanged.listen((dur) {
      if (mounted && dur > Duration.zero) setState(() => _duration = dur);
    });
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _posSubscription?.cancel();
    _durSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_audioBytes == null) return;

    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play(BytesSource(_audioBytes!));
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    if (_audioBytes == null || _audioBytes!.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.mic_off_rounded,
              size: 20,
              color: widget.isMine ? Colors.white70 : AppColors.textMutedDark,
            ),
            const SizedBox(width: 8),
            Text(
              'Voice message unavailable',
              style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: widget.isMine ? Colors.white70 : AppColors.textMutedDark,
              ),
            ),
          ],
        ),
      );
    }

    final effectiveDuration = _duration > Duration.zero
        ? _duration
        : Duration(milliseconds: widget.totalDurationMs ?? 0);

    final progress = effectiveDuration.inMilliseconds > 0
        ? (_position.inMilliseconds / effectiveDuration.inMilliseconds).clamp(
            0.0,
            1.0,
          )
        : 0.0;

    final activeColor = widget.isMine ? Colors.white : AppColors.primary;
    final inactiveColor = widget.isMine
        ? Colors.white38
        : AppColors.primary.withAlpha(77);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Play / Pause circular button
          InkWell(
            onTap: _togglePlay,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isMine
                    ? Colors.white.withAlpha(51)
                    : AppColors.primary.withAlpha(38),
              ),
              child: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: activeColor,
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Waveform / Slider progress bar
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 10,
                    ),
                    activeTrackColor: activeColor,
                    inactiveTrackColor: inactiveColor,
                    thumbColor: activeColor,
                  ),
                  child: Slider(
                    value: progress,
                    onChanged: (val) {
                      final seekMs = (val * effectiveDuration.inMilliseconds)
                          .round();
                      _player.seek(Duration(milliseconds: seekMs));
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(
                          _isPlaying ? _position : effectiveDuration,
                        ),
                        style: TextStyle(
                          fontSize: 11,
                          color: widget.isMine
                              ? Colors.white70
                              : AppColors.textSecondaryDark,
                          fontFamily: 'monospace',
                        ),
                      ),
                      Row(
                        children: [
                          InkWell(
                            onTap: _cycleSpeed,
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: widget.isMine
                                    ? Colors.white.withAlpha(45)
                                    : AppColors.primary.withAlpha(35),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: widget.isMine
                                      ? Colors.white24
                                      : AppColors.primaryLight.withAlpha(80),
                                  width: 0.6,
                                ),
                              ),
                              child: Text(
                                '${_playbackRate == 1.0 ? "1" : _playbackRate}x',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: widget.isMine
                                      ? Colors.white
                                      : AppColors.primaryLight,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.mic_rounded,
                            size: 12,
                            color: widget.isMine
                                ? Colors.white70
                                : AppColors.textMutedDark,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            'Voice note',
                            style: TextStyle(
                              fontSize: 10,
                              color: widget.isMine
                                  ? Colors.white70
                                  : AppColors.textMutedDark,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
