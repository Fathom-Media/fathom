import 'base_item.dart';

/// A page of items plus the total count, for paged browsing and search.
class ItemsResult {
  final List<BaseItemDto> items;
  final int totalRecordCount;

  const ItemsResult({required this.items, required this.totalRecordCount});
}
