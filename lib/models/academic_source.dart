import 'dart:convert';

class AcademicSource {
  final String id;
  final String provider;
  final String title;
  final List<String> authors;
  final String? abstractText;
  final int? year;
  final String? doi;
  final String url;
  final String? journal;
  final int? citationCount;
  final double relevanceScore;
  final bool isSaved;
  final String? messageId;
  final String? queryText;

  const AcademicSource({
    required this.id,
    required this.provider,
    required this.title,
    required this.authors,
    required this.url,
    this.abstractText,
    this.year,
    this.doi,
    this.journal,
    this.citationCount,
    this.relevanceScore = 0,
    this.isSaved = false,
    this.messageId,
    this.queryText,
  });

  AcademicSource copyWith({
    bool? isSaved,
    String? messageId,
    String? queryText,
  }) {
    return AcademicSource(
      id: id,
      provider: provider,
      title: title,
      authors: authors,
      abstractText: abstractText,
      year: year,
      doi: doi,
      url: url,
      journal: journal,
      citationCount: citationCount,
      relevanceScore: relevanceScore,
      isSaved: isSaved ?? this.isSaved,
      messageId: messageId ?? this.messageId,
      queryText: queryText ?? this.queryText,
    );
  }

  String get authorLine {
    if (authors.isEmpty) return 'Unknown author';
    if (authors.length == 1) return authors.first;
    if (authors.length == 2) return '${authors[0]} and ${authors[1]}';
    return '${authors.first} et al.';
  }

  String get providerLabel {
    switch (provider.toLowerCase()) {
      case 'openalex':
        return 'OpenAlex';
      case 'crossref':
        return 'Crossref';
      case 'arxiv':
        return 'arXiv';
      default:
        return provider;
    }
  }

  String get conciseReference {
    final yearLabel = year?.toString() ?? 'n.d.';
    return '$authorLine ($yearLabel). $title';
  }

  String get venueLabel => journal?.trim().isNotEmpty == true ? journal!.trim() : providerLabel;

  String get doiUrl => doi != null && doi!.isNotEmpty ? 'https://doi.org/$doi' : url;

  String formatCitation(String style) {
    final yearLabel = year?.toString() ?? 'n.d.';
    final authorsText = authors.isEmpty ? 'Unknown author' : authors.join(', ');
    final titleText = title.trim();
    final journalText = journal?.trim();
    final doiText = doiUrl;

    switch (style.toUpperCase()) {
      case 'MLA':
        return '$authorsText. "$titleText." ${journalText ?? providerLabel}, $yearLabel, $doiText.';
      case 'CHICAGO':
        return '$authorsText. $yearLabel. "$titleText." ${journalText ?? providerLabel}. $doiText.';
      case 'HARVARD':
        return '$authorsText ($yearLabel) $titleText. ${journalText ?? providerLabel}. Available at: $doiText';
      case 'IEEE':
        return '[$providerLabel] $authorsText, "$titleText," ${journalText ?? providerLabel}, $yearLabel. [Online]. Available: $doiText';
      case 'APA':
      default:
        return '$authorsText ($yearLabel). $titleText. ${journalText ?? providerLabel}. $doiText';
    }
  }

  String toMarkdownCitation(String style) {
    return '- ${formatCitation(style)}';
  }

  String toBibTex() {
    final keyBase = (authors.isNotEmpty ? authors.first.split(' ').last : providerLabel)
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
        .toLowerCase();
    final yearLabel = year?.toString() ?? 'nodate';
    final titleValue = title.replaceAll('{', '').replaceAll('}', '');
    final authorValue = authors.isEmpty ? 'Unknown author' : authors.join(' and ');
    final fields = <String, String>{
      'title': titleValue,
      'author': authorValue,
      'year': yearLabel,
      'journal': venueLabel,
      'url': url,
    };
    if (doi != null && doi!.isNotEmpty) {
      fields['doi'] = doi!;
    }
    final buffer = StringBuffer('@article{$keyBase$yearLabel,\n');
    final entries = fields.entries.toList();
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      final isLast = index == entries.length - 1;
      buffer.writeln('  ${entry.key} = {${entry.value}}${isLast ? '' : ','}');
    }
    buffer.write('}');
    return buffer.toString();
  }

  Map<String, dynamic> toExportMap(String citationStyle) {
    return {
      'id': id,
      'provider': providerLabel,
      'title': title,
      'authors': authors,
      'year': year,
      'journal': venueLabel,
      'doi': doi,
      'url': url,
      'abstract': abstractText,
      'citationCount': citationCount,
      'relevanceScore': relevanceScore,
      'citation': formatCitation(citationStyle),
    };
  }

  Map<String, dynamic> toDatabaseMap(String sessionId, int createdAt) {
    return {
      'id': id,
      'session_id': sessionId,
      'message_id': messageId,
      'provider': provider,
      'title': title,
      'authors_json': jsonEncode(authors),
      'abstract_text': abstractText,
      'year': year,
      'doi': doi,
      'url': url,
      'journal': journal,
      'citation_count': citationCount,
      'relevance_score': relevanceScore,
      'query_text': queryText,
      'created_at': createdAt,
      'is_saved': isSaved ? 1 : 0,
    };
  }

  factory AcademicSource.fromDatabaseMap(Map<String, dynamic> map) {
    final authorsJson = map['authors_json'] as String?;
    return AcademicSource(
      id: map['id'] as String,
      provider: map['provider'] as String? ?? 'Unknown',
      title: map['title'] as String? ?? 'Untitled source',
      authors: authorsJson == null
          ? const []
          : List<String>.from(jsonDecode(authorsJson) as List<dynamic>),
      abstractText: map['abstract_text'] as String?,
      year: map['year'] as int?,
      doi: map['doi'] as String?,
      url: map['url'] as String? ?? '',
      journal: map['journal'] as String?,
      citationCount: map['citation_count'] as int?,
      relevanceScore: (map['relevance_score'] as num?)?.toDouble() ?? 0,
      isSaved: (map['is_saved'] as int? ?? 0) == 1,
      messageId: map['message_id'] as String?,
      queryText: map['query_text'] as String?,
    );
  }
}