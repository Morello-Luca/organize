import 'package:file_picker/file_picker.dart';

class FileService {
  Future<String?> pickFolder() async {
    return await FilePicker.platform.getDirectoryPath();
  }
}
