import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/book_content.dart';

String fixture(String name) =>
    File('test/fixtures/$name').readAsStringSync().trim();

void main() {
  group('parseBookContent — tolerance for real feed markup', () {
    test('a bare <br> does not abort the parse', () {
      final content = parseBookContent('<p>one</p><br><p>two</p>');
      expect(content.blurb.whereType<ContentParagraph>().map((p) => p.text), [
        'one',
        'two',
      ]);
    });

    test('an undeclared namespace prefix is not an error', () {
      final content = parseBookContent(
        '<p><b><image l:href="#juf.png"/></b></p><p>text</p>',
      );
      expect(content.blurb.whereType<ContentParagraph>().map((p) => p.text), [
        'text',
      ]);
    });

    test('unknown elements are unwrapped, not dropped with their children', () {
      final content = parseBookContent(
        '<div><section><p>kept</p></section></div>',
      );
      expect(content.blurb.whereType<ContentParagraph>().map((p) => p.text), [
        'kept',
      ]);
    });

    test('empty paragraphs are dropped', () {
      final content = parseBookContent('<p>  </p><p></p><p>real</p>');
      expect(content.blurb, hasLength(1));
    });

    test('emphasis and links survive as spans', () {
      final content = parseBookContent(
        '<p>plain <b>bold</b> <i>it</i> <a href="https://x.test">link</a></p>',
      );
      final spans = (content.blurb.single as ContentParagraph).spans;
      expect(spans.map((s) => s.text).join(), 'plain bold it link');
      expect(spans.firstWhere((s) => s.text == 'bold').bold, isTrue);
      expect(spans.firstWhere((s) => s.text == 'it').italic, isTrue);
      expect(spans.firstWhere((s) => s.text == 'link').href, 'https://x.test');
    });
  });

  group('parseBookContent — rule 1, content with headings', () {
    late BookContent content;
    setUp(
      () => content = parseBookContent(fixture('content_with_headings.html')),
    );

    test('the blurb is everything before the first heading', () {
      final texts = content.blurb
          .whereType<ContentParagraph>()
          .map((p) => p.text)
          .toList();
      expect(texts.first, startsWith('Каждый здравомыслящий человек'));
      expect(texts.any((t) => t.contains('Fb2 инфо')), isFalse);
      expect(texts.any((t) => t.contains('ISBN')), isFalse);
    });

    test('the stray FB2 image tag leaves nothing behind', () {
      expect(
        content.blurb.whereType<ContentParagraph>().map((p) => p.text),
        isNot(anyElement(contains('juf.png'))),
      );
    });

    test('every heading becomes a section, in document order', () {
      expect(content.hasDetails, isTrue);
      expect(content.details.map((s) => s.label), [
        'Fb2 инфо',
        'Общая информация',
        'Издательская информация',
        'Информация о документе (OCR)',
        'Inpx инфо',
        'Информация о файле',
        'Общая информация',
      ]);
      expect(content.details.first.level, 2);
      expect(content.details[1].level, 3);
    });

    test('key: value paragraphs become rows under their section', () {
      final general = content.details[1];
      expect(general.rows.map((r) => r.label), [
        'Автор(ы)',
        'Название',
        'Серия',
        'Жанр',
        'Дата',
        'Язык книги',
      ]);
      expect(general.rows.first.value, 'Громыко Ольга');
    });

    test('a value containing a colon is split only at the first one', () {
      final general = content.details[1];
      final title = general.rows.firstWhere((r) => r.label == 'Название');
      expect(title.value, 'Профессия: ведьма');
    });

    test('a section with no rows of its own is still emitted', () {
      expect(content.details.first.rows, isEmpty);
    });
  });

  group('parseBookContent — rule 2, content without headings', () {
    late BookContent content;
    setUp(
      () => content = parseBookContent(fixture('content_no_headings.html')),
    );

    test('there is no Details section at all', () {
      expect(content.hasDetails, isFalse);
      expect(content.details, isEmpty);
    });

    test('the whole text stays in the blurb, key: value lines included', () {
      expect(content.blurb, isNotEmpty);
      expect(content.blurbText, startsWith('This edition has images.'));
      expect(content.blurbText, contains('EBook No.: 2701'));
    });
  });

  group('parseBookContent — degenerate input', () {
    test('empty markup yields empty content', () {
      final content = parseBookContent('');
      expect(content.blurb, isEmpty);
      expect(content.hasDetails, isFalse);
    });

    test('a heading first means an empty blurb', () {
      final content = parseBookContent('<h2>Info</h2><p>Size: 4 MB</p>');
      expect(content.blurb, isEmpty);
      expect(content.details.single.rows.single.label, 'Size');
    });

    test('a long sentence with a colon stays a paragraph, not a row', () {
      final content = parseBookContent(
        '<h2>Info</h2>'
        '<p>Every sensible person knows this much for certain: vampires '
        'do not exist at all.</p>',
      );
      expect(content.details.single.rows, isEmpty);
      expect(content.details.single.notes, hasLength(1));
    });

    test('a key with no value stays a paragraph', () {
      final content = parseBookContent('<h2>Info</h2><p>История: </p>');
      expect(content.details.single.rows, isEmpty);
      expect(content.details.single.notes, hasLength(1));
    });
  });
}
