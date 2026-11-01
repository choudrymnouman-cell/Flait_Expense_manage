{{flutter_js}}
{{flutter_build_config}}
// Flait's explicit sw.js owns offline caching. Do not register Flutter's
// deprecated service worker for the same scope.
_flutter.loader.load();
