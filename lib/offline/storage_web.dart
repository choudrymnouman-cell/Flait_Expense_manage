import 'package:sembast_web/sembast_web.dart';

Future<Database> openDeviceDatabase() =>
    databaseFactoryWeb.openDatabase('flait-offline-v2');
