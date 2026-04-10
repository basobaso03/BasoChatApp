import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:typed_data';

import '../models/academic_source.dart';
import 'academic_source_card.dart';

// ─── Design tokens ────────────────────────────────────────────────────────────
const _kAccent      = Color(0xFF00C9A7);
const _kBgUser1     = Color(0xFF0A5A4E);
const _kBgUser2     = Color(0xFF0C8A75);
const _kBgBot       = Color(0xFF0F1A28);
const _kBorderBot   = Color(0xFF1E3A54);
const _kTextPrimary = Color(0xFFE8F4F4);
const _kTextSecond  = Color(0xFF8BA3B0);
// ──────────────────────────────────────────────────────────────────────────────

class ChatMessageWidget extends StatefulWidget {
  final String? text;
  final Uint8List? imageBytes;
  final bool isUser;
  final int index;
  final bool isSelected;
  final bool isQueued;
  final bool isEdited;
  final String? webToolStatus;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onCopyMessage;
  final VoidCallback? onEditMessage;
  final VoidCallback? onRetryMessage;
  final List<AcademicSource> sources;
  final Set<String> savedSourceIds;
  final String citationStyle;
  final VoidCallback? onFactCheck;
  final VoidCallback? onBuildLiteratureReview;
  final ValueChanged<AcademicSource>? onToggleSourceSaved;

  const ChatMessageWidget({
    super.key,
    this.text,
    this.imageBytes,
    required this.isUser,
    required this.index,
    required this.isSelected,
    required this.isQueued,
    this.isEdited = false,
    this.webToolStatus,
    this.onTap,
    this.onLongPress,
    this.onCopyMessage,
    this.onEditMessage,
    this.onRetryMessage,
    this.sources = const [],
    this.savedSourceIds = const <String>{},
    this.citationStyle = 'APA',
    this.onFactCheck,
    this.onBuildLiteratureReview,
    this.onToggleSourceSaved,
  }) : assert(text != null || imageBytes != null,
            'ChatMessageWidget must have text or imageBytes');

  @override
  State<ChatMessageWidget> createState() => _ChatMessageWidgetState();
}

class _ChatMessageWidgetState extends State<ChatMessageWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _fadeAnim = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: widget.isUser ? const Offset(0.25, 0) : const Offset(-0.25, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
    _entryCtrl.forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  Future<void> _launchUrl(String url, BuildContext ctx) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text('Could not launch $url'),
          backgroundColor: Colors.redAccent,
        ));
      }
      if (kDebugMode) debugPrint('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTyping = widget.text == '...' && !widget.isUser;

    return SlideTransition(
      position: _slideAnim,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: widget.isSelected ? 6.0 : 3.0,
            horizontal: 12.0,
          ),
          child: Column(
            crossAxisAlignment:
                widget.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment:
                    widget.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!widget.isUser) ...[
                    Container(
                      width: 28,
                      height: 28,
                      margin: const EdgeInsets.only(right: 8, bottom: 2),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Color(0xFF00C9A7), Color(0xFF0097A7)],
                        ),
                      ),
                      child: const Icon(Icons.auto_awesome_rounded,
                          size: 14, color: Colors.white),
                    ),
                  ],
                  if (widget.isQueued && widget.isUser)
                    Padding(
                      padding: const EdgeInsets.only(right: 6, bottom: 6),
                      child: Icon(Icons.schedule_outlined,
                          size: 13, color: _kTextSecond.withOpacity(0.6)),
                    ),
                  Flexible(
                    child: GestureDetector(
                      onTap: widget.onTap,
                      onLongPress: widget.onLongPress,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        constraints: BoxConstraints(
                          maxWidth: widget.isUser
                              ? screenWidth * 0.72
                              : screenWidth * 0.82,
                        ),
                        padding: widget.imageBytes != null
                            ? const EdgeInsets.all(4)
                            : isTyping
                                ? const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12)
                                : const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                        decoration: _bubbleDecoration(widget.isSelected),
                        child: isTyping
                            ? const _TypingDots()
                            : widget.imageBytes != null
                                ? _buildImage()
                                : _buildMarkdown(context),
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.isUser && (widget.onCopyMessage != null || widget.onEditMessage != null || widget.onRetryMessage != null))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (widget.isEdited)
                        _messageActionPill(
                          icon: Icons.edit_note_rounded,
                          label: 'Edited',
                          onTap: () {},
                          enabled: false,
                        ),
                      if (widget.onCopyMessage != null)
                        _messageActionPill(
                          icon: Icons.content_copy_rounded,
                          label: 'Copy',
                          onTap: widget.onCopyMessage!,
                        ),
                      if (widget.onEditMessage != null)
                        _messageActionPill(
                          icon: Icons.edit_outlined,
                          label: 'Edit',
                          onTap: widget.onEditMessage!,
                        ),
                      if (widget.onRetryMessage != null)
                        _messageActionPill(
                          icon: Icons.refresh_rounded,
                          label: 'Retry',
                          onTap: widget.onRetryMessage!,
                          accent: true,
                        ),
                    ],
                  ),
                ),
              if (!widget.isUser && widget.webToolStatus != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _buildWebToolStatusPill(),
                  ),
                ),
              if (!widget.isUser && widget.sources.isNotEmpty) ...[
                const SizedBox(height: 6),
                SizedBox(
                  height: 260,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.sources.length,
                    itemBuilder: (context, index) {
                      final source = widget.sources[index];
                      return AcademicSourceCard(
                        source: source,
                        citationStyle: widget.citationStyle,
                        isSaved: widget.savedSourceIds.contains(source.id),
                        onToggleSaved: widget.onToggleSourceSaved == null
                            ? null
                            : () => widget.onToggleSourceSaved!(source),
                      );
                    },
                  ),
                ),
              ],
              if (!widget.isUser && (widget.onFactCheck != null || widget.onBuildLiteratureReview != null))
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (widget.onFactCheck != null)
                      OutlinedButton.icon(
                        onPressed: widget.onFactCheck,
                        icon: const Icon(Icons.fact_check_outlined, size: 16),
                        label: const Text('Fact-check this answer'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF64D2FF),
                          side: const BorderSide(color: _kBorderBot),
                        ),
                      ),
                    if (widget.onBuildLiteratureReview != null && widget.sources.length > 1)
                      OutlinedButton.icon(
                        onPressed: widget.onBuildLiteratureReview,
                        icon: const Icon(Icons.auto_stories_outlined, size: 16),
                        label: const Text('Build literature review'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kAccent,
                          side: const BorderSide(color: _kBorderBot),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  BoxDecoration _bubbleDecoration(bool selected) {
    if (widget.isUser) {
      return BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: selected
              ? [_kBgUser2, _kBgUser2.withBlue(120)]
              : [_kBgUser1, _kBgUser2],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(4),
        ),
        boxShadow: [
          BoxShadow(
            color: _kAccent.withOpacity(selected ? 0.25 : 0.12),
            blurRadius: selected ? 14 : 8,
            offset: const Offset(0, 3),
          ),
        ],
        border: selected
            ? Border.all(color: _kAccent.withOpacity(0.5), width: 1.5)
            : null,
      );
    } else {
      return BoxDecoration(
        color: selected ? const Color(0xFF162534) : _kBgBot,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
        border: Border.all(
          color: selected
              ? _kAccent.withOpacity(0.4)
              : _kBorderBot.withOpacity(0.8),
          width: selected ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      );
    }
  }

  Widget _buildMarkdown(BuildContext context) {
    final textColor = widget.isUser ? _kTextPrimary : const Color(0xFFCDE0EC);
    return MarkdownBody(
      data: widget.text!,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(color: textColor, fontSize: 15, height: 1.45),
        code: TextStyle(
          color: _kAccent,
          backgroundColor: Colors.black.withOpacity(0.3),
          fontFamily: 'monospace',
          fontSize: 13,
        ),
        codeblockDecoration: BoxDecoration(
          color: const Color(0xFF0A1520),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _kBorderBot),
        ),
        blockquoteDecoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          border:
              const Border(left: BorderSide(color: _kAccent, width: 3)),
        ),
        blockquotePadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        h1: TextStyle(
            color: textColor, fontSize: 20, fontWeight: FontWeight.bold),
        h2: TextStyle(
            color: textColor, fontSize: 17, fontWeight: FontWeight.w600),
        h3: TextStyle(
            color: textColor, fontSize: 15, fontWeight: FontWeight.w600),
        strong: TextStyle(
            color: textColor, fontWeight: FontWeight.w700),
        em: TextStyle(
            color: textColor.withOpacity(0.85),
            fontStyle: FontStyle.italic),
        a: const TextStyle(
          color: Color(0xFF64D2FF),
          decoration: TextDecoration.underline,
          decorationColor: Color(0xFF64D2FF),
        ),
        listBullet: TextStyle(color: _kAccent),
        tableHead: TextStyle(
            color: textColor, fontWeight: FontWeight.bold),
        tableBody: TextStyle(color: textColor.withOpacity(0.85)),
        tableBorder: TableBorder.all(color: _kBorderBot, width: 0.5),
        horizontalRuleDecoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _kBorderBot)),
        ),
      ),
      onTapLink: (_, href, __) {
        if (href != null) _launchUrl(href, context);
      },
    );
  }

  Widget _buildImage() {
    return ClipRRect(
      borderRadius: BorderRadius.only(
        topLeft: const Radius.circular(16),
        topRight: const Radius.circular(16),
        bottomLeft:
            widget.isUser ? const Radius.circular(16) : const Radius.circular(0),
        bottomRight:
            widget.isUser ? const Radius.circular(0) : const Radius.circular(16),
      ),
      child: Image.memory(
        widget.imageBytes!,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Padding(
          padding: EdgeInsets.all(8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined, color: Colors.redAccent),
              SizedBox(width: 6),
              Text('Image Error', style: TextStyle(color: Colors.redAccent)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _messageActionPill({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool accent = false,
    bool enabled = true,
  }) {
    final foreground = accent ? _kAccent : _kTextSecond;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: enabled
              ? (accent ? const Color(0xFF0F2A3A) : const Color(0xFF111E2E))
              : const Color(0xFF0F1A28),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _kBorderBot),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: enabled ? foreground : _kTextSecond.withOpacity(0.7)),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: foreground, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildWebToolStatusPill() {
    final status = widget.webToolStatus ?? 'used';
    final icon = switch (status) {
      'used' => Icons.public_rounded,
      'used_no_results' => Icons.travel_explore_rounded,
      'skipped' => Icons.public_off_rounded,
      'unavailable' => Icons.cloud_off_rounded,
      _ => Icons.public_rounded,
    };
    final label = switch (status) {
      'used' => 'Web tool used',
      'used_no_results' => 'Web tool used: no matches',
      'skipped' => 'Web tool skipped',
      'unavailable' => 'Web tool unavailable',
      _ => 'Web tool used',
    };
    final accent = status == 'used' || status == 'used_no_results';
    return _messageActionPill(
      icon: icon,
      label: label,
      onTap: () {},
      accent: accent,
      enabled: false,
    );
  }
}

/// Animated three-dot typing indicator shown while the AI is thinking.
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final phase = ((_ctrl.value * 3) - i).clamp(0.0, 1.0);
          final bounce = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Transform.translate(
              offset: Offset(0, -4 * bounce),
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kAccent.withOpacity(0.3 + 0.7 * bounce),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
