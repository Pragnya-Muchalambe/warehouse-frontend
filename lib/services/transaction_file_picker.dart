import 'package:file_picker/file_picker.dart';

export 'transaction_file_picker_types.dart';

import 'transaction_file_picker_types.dart';

class PlatformTransactionFilePicker implements TransactionFilePicker {
  const PlatformTransactionFilePicker({FilePicker? picker}) : _picker = picker;

  factory PlatformTransactionFilePicker.initialized() =>
      PlatformTransactionFilePicker(picker: FilePicker.platform);

  final FilePicker? _picker;

  bool get isInitialized => _picker != null;

  @override
  Future<List<PickedTransactionFile>?> pick(
      {required bool allowMultiple}) async {
    final result = await (_picker ?? FilePicker.platform).pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      allowMultiple: allowMultiple,
      withData: true,
    );
    return result?.files
        .map((file) => PickedTransactionFile(
              file.name,
              file.bytes,
              size: file.size,
            ))
        .toList();
  }
}
