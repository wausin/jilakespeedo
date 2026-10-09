import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'connectivity_service.dart';

/// Web [ConnectivityService]: listens to the browser's `online`/`offline`
/// window events, seeded from `navigator.onLine`.
class WebConnectivityService implements ConnectivityService {
  WebConnectivityService() {
    _controller = StreamController<bool>.broadcast(
      onListen: _attach,
      onCancel: _detach,
    );
  }

  late final StreamController<bool> _controller;
  JSFunction? _offlineListener;
  JSFunction? _onlineListener;

  void _attach() {
    _controller.add(!web.window.navigator.onLine);
    _offlineListener = ((web.Event _) {
      _controller.add(true);
    }).toJS;
    _onlineListener = ((web.Event _) {
      _controller.add(false);
    }).toJS;
    web.window.addEventListener('offline', _offlineListener!);
    web.window.addEventListener('online', _onlineListener!);
  }

  void _detach() {
    final offline = _offlineListener;
    final online = _onlineListener;
    if (offline != null) web.window.removeEventListener('offline', offline);
    if (online != null) web.window.removeEventListener('online', online);
    _offlineListener = null;
    _onlineListener = null;
  }

  @override
  Stream<bool> get offlineStream => _controller.stream;

  @override
  bool get isOffline => !web.window.navigator.onLine;
}
