import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../models/academic_source.dart';

class AcademicSearchService {
  const AcademicSearchService();

  Future<List<AcademicSource>> searchSources(String query, {int maxResults = 8}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final merged = <String, AcademicSource>{};
    final queryVariants = _buildQueryVariants(trimmed);

    for (final variant in queryVariants) {
      final results = await Future.wait<List<AcademicSource>>([
        _searchOpenAlex(variant),
        _searchCrossref(variant),
        _searchArxiv(variant),
      ]);

      for (final providerResults in results) {
        for (final source in providerResults) {
          final key = _dedupeKey(source);
          final existing = merged[key];
          if (existing == null || source.relevanceScore > existing.relevanceScore) {
            merged[key] = source;
          }
        }
      }

      if (merged.length >= maxResults) {
        break;
      }
    }

    final sorted = merged.values.toList()
      ..sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));
    return sorted.take(maxResults).toList();
  }

  List<String> _buildQueryVariants(String query) {
    final variants = <String>[];

    void addVariant(String value) {
      final cleaned = value.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (cleaned.isEmpty) return;
      if (!variants.contains(cleaned)) {
        variants.add(cleaned);
      }
    }

    addVariant(query);

    final withoutQuestionLead = query
        .replaceFirst(RegExp(r'^(what|which|who|when|where|why|how)\b[:\s-]*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^(can you|could you|please|find|search for|look up)\b[:\s-]*', caseSensitive: false), '');
    addVariant(withoutQuestionLead);

    final normalized = query
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), ' ')
        .replaceAll(RegExp(r'\b(the|a|an|and|or|but|for|with|into|from|about|show|give|tell|explain|summarize|recent|latest|papers|paper|studies|study|research|sources|references|citation|citations)\b'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    addVariant(normalized);

    final keywordVariant = _extractCoreKeywords(query);
    addVariant(keywordVariant);

    return variants.take(4).toList();
  }

  String _extractCoreKeywords(String query, {int maxWords = 7}) {
    final words = query
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .where((word) => word.length > 2)
        .where((word) => !_searchStopWords.contains(word))
        .take(maxWords)
        .toList();
    return words.join(' ');
  }

  String buildGroundingBlock(List<AcademicSource> sources, {required String citationStyle, required String studyMode}) {
    if (sources.isEmpty) {
      return 'No reliable academic sources were retrieved. Do not fabricate references. Say clearly when evidence is missing.';
    }

    final buffer = StringBuffer()
      ..writeln('Use the academic evidence below for grounded answers.')
      ..writeln('Study mode: $studyMode')
      ..writeln('Citation style: $citationStyle')
      ..writeln('Rules:')
      ..writeln('- Cite only from the sources below or attached files.')
      ..writeln('- Do not invent authors, dates, journals, DOIs, or URLs.')
      ..writeln('- If evidence is weak or conflicting, say so explicitly.')
      ..writeln('- For academic writing help, improve structure without enabling misconduct.')
      ..writeln('- End grounded answers with a References section when sources were used.')
      ..writeln('Academic sources:');

    for (final source in sources) {
      buffer
        ..writeln('- Title: ${source.title}')
        ..writeln('  Provider: ${source.providerLabel}')
        ..writeln('  Authors: ${source.authorLine}')
        ..writeln('  Year: ${source.year?.toString() ?? 'Unknown'}')
        ..writeln('  Journal: ${source.journal ?? source.providerLabel}')
        ..writeln('  DOI: ${source.doi ?? 'Not available'}')
        ..writeln('  URL: ${source.url}')
        ..writeln('  Abstract: ${source.abstractText ?? 'No abstract available.'}');
    }
    return buffer.toString();
  }

  Future<List<AcademicSource>> _searchOpenAlex(String query) async {
    final uri = Uri.parse('https://api.openalex.org/works?search=${Uri.encodeQueryComponent(query)}&per-page=4&sort=relevance_score:desc');
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return const [];

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final results = (data['results'] as List<dynamic>? ?? const []);
    return results.asMap().entries.map((entry) {
      final item = entry.value as Map<String, dynamic>;
      final primaryLocation = item['primary_location'] as Map<String, dynamic>?;
      final citedByCount = item['cited_by_count'] as int?;
      return AcademicSource(
        id: 'openalex_${item['id'] ?? entry.key}',
        provider: 'OpenAlex',
        title: item['title'] as String? ?? 'Untitled source',
        authors: ((item['authorships'] as List<dynamic>? ?? const [])
                .map((author) => (author as Map<String, dynamic>)['author'] as Map<String, dynamic>?)
                .map((author) => author?['display_name'] as String?)
                .whereType<String>())
            .toList(),
        abstractText: _decodeOpenAlexAbstract(item['abstract_inverted_index'] as Map<String, dynamic>?),
        year: item['publication_year'] as int?,
        doi: (item['doi'] as String?)?.replaceFirst('https://doi.org/', ''),
        url: (primaryLocation?['landing_page_url'] as String?) ?? (item['id'] as String? ?? ''),
        journal: (primaryLocation?['source'] as Map<String, dynamic>?)?['display_name'] as String?,
        citationCount: citedByCount,
        relevanceScore: 100 - (entry.key * 8) + ((citedByCount ?? 0) / 100),
      );
    }).toList();
  }

  Future<List<AcademicSource>> _searchCrossref(String query) async {
    final uri = Uri.parse('https://api.crossref.org/works?query.bibliographic=${Uri.encodeQueryComponent(query)}&rows=4&sort=relevance&order=desc');
    final response = await http.get(uri, headers: {'User-Agent': 'BasoChatApp/1.0 (academic assistant)'}).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return const [];

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = ((data['message'] as Map<String, dynamic>?)?['items'] as List<dynamic>? ?? const []);
    return items.asMap().entries.map((entry) {
      final item = entry.value as Map<String, dynamic>;
      final issued = ((item['issued'] as Map<String, dynamic>?)?['date-parts'] as List<dynamic>?);
      final year = issued != null && issued.isNotEmpty && (issued.first as List).isNotEmpty
          ? (issued.first as List).first as int?
          : null;
      final doi = item['DOI'] as String?;
      return AcademicSource(
        id: 'crossref_${doi ?? entry.key}',
        provider: 'Crossref',
        title: ((item['title'] as List<dynamic>? ?? const [])).cast<String>().firstOrNull ?? 'Untitled source',
        authors: ((item['author'] as List<dynamic>? ?? const [])
                .map((author) => author as Map<String, dynamic>)
                .map((author) => [author['given'], author['family']].whereType<String>().join(' ').trim())
                .where((author) => author.isNotEmpty))
            .toList(),
        abstractText: _stripTags(item['abstract'] as String?),
        year: year,
        doi: doi,
        url: doi == null ? (item['URL'] as String? ?? '') : 'https://doi.org/$doi',
        journal: ((item['container-title'] as List<dynamic>? ?? const [])).cast<String>().firstOrNull,
        citationCount: item['is-referenced-by-count'] as int?,
        relevanceScore: 92 - (entry.key * 7) + (((item['is-referenced-by-count'] as int?) ?? 0) / 100),
      );
    }).toList();
  }

  Future<List<AcademicSource>> _searchArxiv(String query) async {
    final uri = Uri.parse('https://export.arxiv.org/api/query?search_query=all:${Uri.encodeQueryComponent(query)}&start=0&max_results=4');
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return const [];

    final document = XmlDocument.parse(response.body);
    final entries = document.findAllElements('entry').toList();
    return entries.asMap().entries.map((entry) {
      final node = entry.value;
      final id = node.getElement('id')?.innerText.trim() ?? 'arxiv_${entry.key}';
      return AcademicSource(
        id: 'arxiv_$id',
        provider: 'arXiv',
        title: node.getElement('title')?.innerText.replaceAll(RegExp(r'\s+'), ' ').trim() ?? 'Untitled source',
        authors: node.findElements('author').map((author) => author.getElement('name')?.innerText.trim()).whereType<String>().toList(),
        abstractText: node.getElement('summary')?.innerText.replaceAll(RegExp(r'\s+'), ' ').trim(),
        year: int.tryParse(node.getElement('published')?.innerText.substring(0, 4) ?? ''),
        url: id,
        journal: 'arXiv preprint',
        relevanceScore: 84 - (entry.key * 6),
      );
    }).toList();
  }

  String _dedupeKey(AcademicSource source) {
    if (source.doi != null && source.doi!.isNotEmpty) {
      return source.doi!.toLowerCase();
    }
    return source.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  String? _decodeOpenAlexAbstract(Map<String, dynamic>? invertedIndex) {
    if (invertedIndex == null || invertedIndex.isEmpty) return null;
    final pairs = <MapEntry<int, String>>[];
    invertedIndex.forEach((word, positions) {
      for (final position in (positions as List<dynamic>)) {
        pairs.add(MapEntry(position as int, word));
      }
    });
    pairs.sort((a, b) => a.key.compareTo(b.key));
    final text = pairs.map((entry) => entry.value).join(' ');
    return _truncate(text);
  }

  String? _stripTags(String? input) {
    if (input == null || input.isEmpty) return null;
    final withoutTags = input.replaceAll(RegExp(r'<[^>]+>'), ' ');
    return _truncate(withoutTags.replaceAll(RegExp(r'\s+'), ' ').trim());
  }

  String _truncate(String value, {int maxChars = 700}) {
    if (value.length <= maxChars) return value;
    return '${value.substring(0, maxChars - 3)}...';
  }
}

const Set<String> _searchStopWords = {
  'the',
  'and',
  'for',
  'with',
  'that',
  'this',
  'from',
  'into',
  'about',
  'what',
  'which',
  'when',
  'where',
  'why',
  'how',
  'can',
  'could',
  'would',
  'please',
  'find',
  'search',
  'look',
  'latest',
  'recent',
  'paper',
  'papers',
  'study',
  'studies',
  'research',
  'source',
  'sources',
  'reference',
  'references',
  'citation',
  'citations',
  'article',
  'articles',
  'journal',
  'journals',
  'information',
  'more',
};

extension _FirstOrNullExtension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}