import 'dart:js_interop';

@JS('qmLoadFirebase')
external JSPromise<JSAny?> _loadFirebase();

Future<void> prepareFirebaseWeb() async {
  await _loadFirebase().toDart;
}
