import 'package:go_router/go_router.dart';

// A replaced page may remain mounted during its outgoing animation. Mounted
// alone does not mean that its asynchronous startup work may still navigate.
bool mayCompleteStartup(GoRouter router) =>
    router.routeInformationProvider.value.uri.path == '/';
