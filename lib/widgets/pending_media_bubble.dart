import 'dart:io';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

/// Local preview stays separate from delivered Firestore messages.
class PendingMediaBubble extends StatelessWidget {
  const PendingMediaBubble(
      {super.key,
      required this.mediaType,
      this.filePath,
      this.failed = false,
      this.onRetry});
  final String mediaType;
  final String? filePath;
  final bool failed;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Align(
        alignment: Alignment.centerRight,
        child: Container(
          key: const ValueKey('pending-media'),
          width: 220,
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: const Color(0xFF252D3C),
              borderRadius: BorderRadius.circular(16)),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (mediaType == 'image' && filePath != null)
                  ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(File(filePath!),
                          width: 200,
                          height: 110,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stack) =>
                              const SizedBox(
                                  height: 40,
                                  child: Icon(Icons.image_outlined,
                                      color: Colors.white54))))
                else
                  const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Icon(Icons.graphic_eq_rounded,
                          color: Colors.white70, size: 32)),
                const SizedBox(height: 6),
                Row(children: [
                  Icon(failed ? Icons.error_outline : Icons.schedule,
                      size: 14, color: Colors.white54),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(
                          failed ? l10n.messageSendFailed : l10n.mediaSending,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12))),
                  if (failed && onRetry != null)
                    IconButton(
                        tooltip: l10n.retryMediaLabel,
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh,
                            color: Colors.white70, size: 18)),
                ]),
                if (!failed)
                  const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: LinearProgressIndicator(
                          minHeight: 2,
                          color: Color(0xFF9BA5B5),
                          backgroundColor: Color(0xFF353F50))),
              ]),
        ));
  }
}
