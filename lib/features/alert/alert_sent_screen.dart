import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import '../../core/constants/colors.dart';
import '../../core/providers/app_providers.dart';

class AlertSentScreen extends ConsumerWidget {
  const AlertSentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertState = ref.watch(activeAlertStateProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // If active alert is null, redirect to home
    if (alertState == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.go('/home');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final timestampStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(alertState.timestamp);
    final contacts = alertState.contactsNotified;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                const SizedBox(height: 12),
                // Success Checkmark Icon
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.severityHigh.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.severityHigh, width: 3),
                  ),
                  child: const Icon(
                    Icons.check_circle_outline,
                    size: 80,
                    color: AppColors.severityHigh,
                  ),
                ),
                const SizedBox(height: 32),
                
                // Header
                const Text(
                  'EMERGENCY ALERT SENT',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                    color: AppColors.severityHigh,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Emergency dispatch has successfully broadcasted your coordinates.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
                const SizedBox(height: 24),

                // Video Evidence Player
                if (alertState.videoUrl != null) ...[
                  CrashVideoPlayer(videoUrl: alertState.videoUrl!),
                  const SizedBox(height: 24),
                ],
                
                // Metadata Box
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isDark ? AppColors.darkDivider : AppColors.lightDivider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildMetaItem('Timestamp', timestampStr),
                      const Divider(height: 20),
                      _buildMetaItem('GPS Location', '${alertState.latitude.toStringAsFixed(6)}, ${alertState.longitude.toStringAsFixed(6)}'),
                      const Divider(height: 20),
                      _buildMetaItem('Severity Level', alertState.severityLevel, color: AppColors.severityHigh),
                      if (alertState.severityScore > 0) ...[
                        const Divider(height: 20),
                        _buildMetaItem('Calculated Impact', '${alertState.severityScore.toStringAsFixed(1)} score', color: Colors.amber),
                        if (alertState.baseScore != null) ...[
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.only(left: 12.0),
                            child: _buildMetaItem('↳ Base IMU/G Score', alertState.baseScore!.toStringAsFixed(1), isSubItem: true),
                          ),
                        ],
                        if (alertState.aiBonus != null) ...[
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.only(left: 12.0),
                            child: _buildMetaItem('↳ Edge AI Severity Bonus', '+${alertState.aiBonus!.toStringAsFixed(1)}', color: Colors.greenAccent, isSubItem: true),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                
                // Notified Contacts list
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isDark ? AppColors.darkDivider : AppColors.lightDivider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'NOTIFIED EMERGENCY CONTACTS:',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      if (contacts.isEmpty)
                        const Text('No contacts were registered.', style: TextStyle(color: Colors.grey))
                      else
                        ...contacts.map((c) => Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Row(
                                children: [
                                  const Icon(Icons.check, color: Colors.green, size: 18),
                                  const SizedBox(width: 8),
                                  Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  const Spacer(),
                                  Text(c.phoneNumber, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                                ],
                              ),
                            )),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                
                // Return Home Button
                ElevatedButton(
                  onPressed: () {
                    ref.read(activeAlertStateProvider.notifier).dismissAlert();
                    context.go('/home');
                  },
                  child: const Text('Return to Control Panel'),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetaItem(String title, String value, {Color? color, bool isSubItem = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            color: isSubItem ? Colors.grey[600] : Colors.grey,
            fontSize: isSubItem ? 12 : 13,
            fontStyle: isSubItem ? FontStyle.italic : null,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: isSubItem ? FontWeight.normal : FontWeight.bold,
            fontFamily: title.contains('GPS') ? 'monospace' : null,
            color: color ?? (isSubItem ? Colors.grey[400] : null),
            fontSize: isSubItem ? 12 : 13,
          ),
        ),
      ],
    );
  }
}

class CrashVideoPlayer extends StatefulWidget {
  final String videoUrl;
  const CrashVideoPlayer({super.key, required this.videoUrl});

  @override
  State<CrashVideoPlayer> createState() => _CrashVideoPlayerState();
}

class _CrashVideoPlayerState extends State<CrashVideoPlayer> {
  late VideoPlayerController _controller;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  String _normalizeVideoUrl(String url) {
    if (url.startsWith('http://') && url.contains(':8080/')) {
      try {
        final uri = Uri.parse(url);
        final filename = uri.pathSegments.last;
        return 'https://firebasestorage.googleapis.com/v0/b/vehisafe-alert.firebasestorage.app/o/$filename?alt=media';
      } catch (e) {
        debugPrint('Failed parsing local fallback URL $url: $e');
      }
    }
    return url;
  }

  void _initializePlayer() {
    _hasError = false;
    _errorMessage = '';
    final normalizedUrl = _normalizeVideoUrl(widget.videoUrl);
    _controller = VideoPlayerController.networkUrl(Uri.parse(normalizedUrl))
      ..initialize().then((_) {
        setState(() {});
        _controller.play(); // Auto-play on load
      }).catchError((error) {
        debugPrint('Error initializing video player: $error');
        setState(() {
          _hasError = true;
          _errorMessage = error.toString();
        });
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isInitialized = _controller.value.isInitialized;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.1),
            blurRadius: 10,
            spreadRadius: 2,
          )
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.red.withValues(alpha: 0.2),
            child: const Row(
              children: [
                Icon(Icons.video_camera_back, color: Colors.red, size: 18),
                SizedBox(width: 8),
                Text(
                  'CRASH EVIDENCE PLAYBACK (EDGE AI)',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          AspectRatio(
            aspectRatio: isInitialized ? _controller.value.aspectRatio : 16 / 9,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (isInitialized)
                  VideoPlayer(_controller)
                else if (_hasError)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 40),
                        const SizedBox(height: 8),
                        const Text(
                          'Failed to load Edge Video',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        if (_errorMessage.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            _errorMessage,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          widget.videoUrl,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey, fontSize: 10),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _initializePlayer,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Retry'),
                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                        )
                      ],
                    ),
                  )
                else
                  const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Colors.red)),
                      SizedBox(height: 12),
                      Text(
                        'Buffering edge crash video...',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                if (isInitialized)
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _controller.value.isPlaying ? _controller.pause() : _controller.play();
                        });
                      },
                      child: Container(
                        color: Colors.transparent,
                        child: AnimatedOpacity(
                          opacity: _controller.value.isPlaying ? 0.0 : 1.0,
                          duration: const Duration(milliseconds: 300),
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.4),
                            child: Icon(
                              _controller.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                              color: Colors.white,
                              size: 64,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (isInitialized)
            Column(
              children: [
                VideoProgressIndicator(
                  _controller,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Colors.red,
                    bufferedColor: Colors.grey,
                    backgroundColor: Colors.black,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 20,
                        ),
                        onPressed: () {
                          setState(() {
                            _controller.value.isPlaying ? _controller.pause() : _controller.play();
                          });
                        },
                      ),
                      IconButton(
                        icon: Icon(
                          _controller.value.volume > 0 ? Icons.volume_up : Icons.volume_off,
                          color: Colors.white,
                          size: 20,
                        ),
                        onPressed: () {
                          setState(() {
                            _controller.setVolume(_controller.value.volume > 0 ? 0.0 : 1.0);
                          });
                        },
                      ),
                      const Spacer(),
                      Text(
                        '${_printDuration(_controller.value.position)} / ${_printDuration(_controller.value.duration)}',
                        style: const TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _printDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}
