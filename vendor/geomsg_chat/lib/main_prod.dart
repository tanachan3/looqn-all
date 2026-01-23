import 'package:geomsg_chat/firebase_options.dart' show AppFlavor;
import 'package:geomsg_chat/main.dart' as app;

import 'firebase_options_prod.dart' as firebase_options;

Future<void> main() async {
  await app.runGeomsgApp(
    firebaseOptions: firebase_options.DefaultFirebaseOptions.currentPlatform,
    flavor: AppFlavor.prod,
  );
}
