/// A user-created Discover slider, stored locally. Backs a row on the Seerr
/// Discover home from a movie/TV genre or a keyword search.
class SeerrCustomSlider {
  final String id;
  final String title;
  final String type; // 'movieGenre' | 'tvGenre' | 'keyword'
  final String data; // genre id (as string) or the keyword text

  const SeerrCustomSlider({
    required this.id,
    required this.title,
    required this.type,
    required this.data,
  });

  int get genreId => int.tryParse(data) ?? 0;

  Map<String, dynamic> toMap() =>
      {'id': id, 'title': title, 'type': type, 'data': data};

  factory SeerrCustomSlider.fromMap(Map<String, dynamic> m) => SeerrCustomSlider(
        id: '${m['id'] ?? ''}',
        title: '${m['title'] ?? ''}',
        type: '${m['type'] ?? 'keyword'}',
        data: '${m['data'] ?? ''}',
      );
}
