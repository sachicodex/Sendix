import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sendix/models/transfer.dart';

class FileManager {
  Future<List<TransferFile>> pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) return [];

    final files = <TransferFile>[];
    for (final platformFile in result.files) {
      final path = platformFile.path;
      if (path == null) continue;
      final file = File(path);
      final size = await file.length();
      files.add(
        TransferFile(
          name: p.basename(path),
          relativePath: p.basename(path),
          size: size,
          absolutePath: path,
        ),
      );
    }
    return files;
  }

  Future<List<TransferFile>> pickDirectory() async {
    final directoryPath = await FilePicker.platform.getDirectoryPath();
    if (directoryPath == null) return [];

    final root = Directory(directoryPath);
    if (!await root.exists()) return [];

    final files = <TransferFile>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final size = await entity.length();
        final relative = p.relative(entity.path, from: root.path);
        files.add(
          TransferFile(
            name: p.basename(entity.path),
            relativePath: p.join(p.basename(root.path), relative),
            size: size,
            absolutePath: entity.path,
          ),
        );
      }
    }
    return files;
  }

  Future<List<TransferFile>> transferFilesFromPaths(
    Iterable<String> paths,
  ) async {
    final files = <TransferFile>[];
    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) {
        final size = await file.length();
        files.add(
          TransferFile(
            name: p.basename(path),
            relativePath: p.basename(path),
            size: size,
            absolutePath: path,
          ),
        );
        continue;
      }

      final dir = Directory(path);
      if (await dir.exists()) {
        files.addAll(await _transferFilesFromDirectory(dir));
      }
    }
    return files;
  }

  Future<List<TransferFile>> _transferFilesFromDirectory(Directory root) async {
    final files = <TransferFile>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final size = await entity.length();
        final relative = p.relative(entity.path, from: root.path);
        files.add(
          TransferFile(
            name: p.basename(entity.path),
            relativePath: p.join(p.basename(root.path), relative),
            size: size,
            absolutePath: entity.path,
          ),
        );
      }
    }
    return files;
  }

  Future<String> getDefaultReceiveDirectoryPath() async {
    if (Platform.isAndroid) {
      final base =
          await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      return p.join(base.path, 'Sendix');
    }

    final downloads = await getDownloadsDirectory();
    final base = downloads ?? await getApplicationDocumentsDirectory();
    return p.join(base.path, 'Sendix');
  }

  Future<Directory> getReceiveDirectory({String? customPath}) async {
    final trimmed = (customPath ?? '').trim();
    final targetPath = trimmed.isEmpty
        ? await getDefaultReceiveDirectoryPath()
        : trimmed;

    if (Platform.isAndroid) {
      await _ensureStorageAccess();
    }

    final target = Directory(targetPath);
    await target.create(recursive: true);
    return target;
  }

  Future<void> _ensureStorageAccess() async {
    final status = await Permission.storage.request();
    if (status.isGranted) return;

    final manage = await Permission.manageExternalStorage.request();
    if (!manage.isGranted) {
      throw const FileSystemException('Storage permission denied.');
    }
  }
}
