// Driver for running the integration tests on a physical device:
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/apple_vision_test.dart -d <device> \
//     --publish-port
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
