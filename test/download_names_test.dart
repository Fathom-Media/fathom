import 'package:fathom/models/base_item.dart';
import 'package:fathom/state/downloads.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mediaFileExtension', () {
    test("uses the original file's own extension when the server sends it", () {
      expect(
          mediaFileExtension({
            'Container': 'mov,mp4,m4a,3gp,3g2,mj2',
            'Path': '/media/Shows/Pioneer One (2010)/Season 1/'
                'Pioneer One - S01E01 - Earthfall.mp4',
          }),
          'mp4');
      expect(
          mediaFileExtension({
            'MediaSources': [
              {'Container': 'mkv', 'Path': r'D:\Movies\Bullet Train (2022).MKV'}
            ],
          }),
          'mkv');
    });

    test("falls back to the media source's format", () {
      expect(
          mediaFileExtension({
            'MediaSources': [
              {'Container': 'mp4'}
            ],
          }),
          'mp4');
    });

    test('translates the format list item lists always carry', () {
      // Episodes listed for a season come without Path or MediaSources.
      expect(mediaFileExtension({'Container': 'mov,mp4,m4a,3gp,3g2,mj2'}),
          'mp4');
      expect(
          mediaFileExtension(
              {'Type': 'Audio', 'Container': 'mov,mp4,m4a,3gp,3g2,mj2'}),
          'm4a');
      expect(mediaFileExtension({'Container': 'matroska,webm'}), 'mkv');
      expect(mediaFileExtension({'Container': 'mpegts'}), 'ts');
      expect(mediaFileExtension({'Type': 'Audio', 'Container': 'flac'}),
          'flac');
      expect(mediaFileExtension({'Type': 'Audio', 'Container': 'mp3'}), 'mp3');
    });

    test('gives up rather than guessing', () {
      expect(mediaFileExtension({}), isNull);
      expect(mediaFileExtension({'Path': '/media/odd/no-extension'}), isNull);
    });
  });

  group('downloadFileName', () {
    BaseItemDto item(Map<String, dynamic> json) =>
        BaseItemDto.fromJson({'Id': 'abc123', ...json});

    test('names media the way Jellyfin does, with its real extension', () {
      expect(
          downloadFileName(
              item({
                'Name': 'Bullet Train',
                'Type': 'Movie',
                'ProductionYear': 2022,
                'Container': 'matroska,webm',
              }),
              type: 'Movie'),
          (base: 'Bullet Train (2022)', extension: 'mkv'));
      expect(
          downloadFileName(
              item({
                'Name': 'Earthfall',
                'Type': 'Episode',
                'SeriesName': 'Pioneer One',
                'ParentIndexNumber': 1,
                'IndexNumber': 2,
                'Container': 'mov,mp4,m4a,3gp,3g2,mj2',
              }),
              type: 'Episode'),
          (base: 'Pioneer One - S01E02 - Earthfall', extension: 'mp4'));
      expect(
          downloadFileName(
              item({
                'Name': 'Bend',
                'Type': 'Audio',
                'AlbumArtist': 'Binaerpilot',
                'Container': 'mp3',
              }),
              type: 'Audio'),
          (base: 'Binaerpilot - Bend', extension: 'mp3'));
    });

    test('strips what filesystems refuse', () {
      expect(
          downloadFileName(item({'Name': 'What: A "Movie"? / Part 1'}),
                  type: 'Recording')
              .base,
          'What A Movie Part 1');
    });

    test('falls back to the item id when nothing usable is left', () {
      expect(downloadFileName(item({'Name': '???'}), type: 'Movie').base,
          'abc123');
    });
  });
}
