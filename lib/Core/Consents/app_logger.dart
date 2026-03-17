import 'package:logger/logger.dart';

class AppLogger {
  static final Logger log = Logger(
    // filter: ProductionFilter(),
    // printer: PrettyPrinter(
    //   methodCount: 0,
    //   errorMethodCount: 5,
    //   lineLength: 120,
    //   colors: false,
    //   printEmojis: false,
    //   printTime: true,
    // ),
  );
}
