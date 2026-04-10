import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/academic_source.dart';

class AcademicSourceCard extends StatelessWidget {
  final AcademicSource source;
  final String citationStyle;
  final bool isSaved;
  final VoidCallback? onToggleSaved;

  const AcademicSourceCard({
    super.key,
    required this.source,
    required this.citationStyle,
    required this.isSaved,
    this.onToggleSaved,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF00C9A7);
    const border = Color(0xFF1E3A54);

    return SizedBox(
      width: 280,
      child: Container(
        margin: const EdgeInsets.only(top: 10, right: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1826),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111E2E),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    source.providerLabel,
                    style: const TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
                const Spacer(),
                if (source.year != null)
                  Text(
                    source.year.toString(),
                    style: const TextStyle(color: Color(0xFF8BA3B0), fontSize: 12),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700, height: 1.3),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      source.authorLine,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF64D2FF), fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _metaPill(source.venueLabel),
                        if (source.citationCount != null) _metaPill('${source.citationCount} citations'),
                        if (source.doi != null && source.doi!.isNotEmpty) _metaPill('DOI'),
                      ],
                    ),
                    if (source.abstractText != null && source.abstractText!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        source.abstractText!,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFFCDE0EC), fontSize: 12, height: 1.35),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      source.formatCitation(citationStyle),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF8BA3B0), fontSize: 11, height: 1.35),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _footerAction(
                  icon: Icons.open_in_new_rounded,
                  label: 'Open',
                  color: Colors.white,
                  onTap: () => _openSource(source.url),
                ),
                const SizedBox(width: 8),
                _footerAction(
                  icon: Icons.content_copy_rounded,
                  label: 'Copy',
                  color: const Color(0xFF64D2FF),
                  onTap: () => Clipboard.setData(ClipboardData(text: source.formatCitation(citationStyle))),
                ),
                const SizedBox(width: 8),
                _footerAction(
                  icon: isSaved ? Icons.bookmark_rounded : Icons.bookmark_add_outlined,
                  label: isSaved ? 'Saved' : 'Save',
                  color: isSaved ? accent : Colors.white,
                  onTap: onToggleSaved,
                  filled: isSaved,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSource(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _metaPill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF111E2E),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Color(0xFF8BA3B0), fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _footerAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
    bool filled = false,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: filled ? const Color(0xFF0F5244) : const Color(0xFF111E2E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1E3A54)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}