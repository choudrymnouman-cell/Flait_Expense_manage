import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:sembast/sembast_io.dart';

Future<Database> openDeviceDatabase() async {
  final directory = await getApplicationSupportDirectory();
  return databaseFactoryIo
      .openDatabase(path.join(directory.path, 'flait-offline-v2.db'));
}
