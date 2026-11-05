String trackingDraftInput(Map<String, dynamic> line) {
  final allocations = line['lotAllocations'];
  if (allocations is List && allocations.isNotEmpty) {
    return allocations
        .map((lot) {
          final quantity = (lot['quantity'] as int) / 1000;
          final text = quantity.toString();
          return "${lot['lotId']}:${text.endsWith('.0') ? text.substring(0, text.length - 2) : text}";
        })
        .join('; ');
  }
  return (line['lotId'] as String?) ??
      (line['serials'] as List? ?? []).join(', ');
}
