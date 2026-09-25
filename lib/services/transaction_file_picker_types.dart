import 'dart:typed_data';

class PickedTransactionFile {
  final String name;
  final Uint8List? bytes;
  final int size;
  final String? contentType;

  PickedTransactionFile(
    this.name,
    this.bytes, {
    int? size,
    this.contentType,
  }) : size = size ?? bytes?.lengthInBytes ?? 0;
}

abstract class TransactionFilePicker {
  Future<List<PickedTransactionFile>?> pick({required bool allowMultiple});
}
