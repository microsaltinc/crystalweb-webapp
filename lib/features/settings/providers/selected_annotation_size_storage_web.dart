import 'package:web/web.dart' as web;

const _key = 'crystalweb.selectedAnnotationSize';

String? readSelectedAnnotationSize() => web.window.localStorage.getItem(_key);

void writeSelectedAnnotationSize(int value) {
  web.window.localStorage.setItem(_key, value.toString());
}
