import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Listens to web DOM events (tab visibility change, window blur/focus, beforeunload, pagehide)
/// to detect when the tab/browser is minimized, closed, changed, or locked.
StreamSubscription<dynamic>? initWebPresenceListeners({
  required void Function() onHide,
  required void Function() onShow,
}) {
  final onVisibilityChange = (web.Event event) {
    if (web.document.hidden) {
      onHide();
    } else {
      onShow();
    }
  }.toJS;

  final onBlur = (web.Event event) {
    if (web.document.hidden) {
      onHide();
    }
  }.toJS;

  final onFocus = (web.Event event) {
    if (!web.document.hidden) {
      onShow();
    }
  }.toJS;

  final onBeforeUnload = (web.Event event) {
    onHide();
  }.toJS;

  final onPageHide = (web.Event event) {
    onHide();
  }.toJS;

  web.document.addEventListener('visibilitychange', onVisibilityChange);
  web.window.addEventListener('blur', onBlur);
  web.window.addEventListener('focus', onFocus);
  web.window.addEventListener('beforeunload', onBeforeUnload);
  web.window.addEventListener('pagehide', onPageHide);

  return _WebPresenceSubscription(() {
    web.document.removeEventListener('visibilitychange', onVisibilityChange);
    web.window.removeEventListener('blur', onBlur);
    web.window.removeEventListener('focus', onFocus);
    web.window.removeEventListener('beforeunload', onBeforeUnload);
    web.window.removeEventListener('pagehide', onPageHide);
  });
}

class _WebPresenceSubscription implements StreamSubscription<void> {
  _WebPresenceSubscription(this._onCancel);
  final void Function() _onCancel;
  bool _isCanceled = false;

  @override
  Future<void> cancel() async {
    if (!_isCanceled) {
      _isCanceled = true;
      _onCancel();
    }
  }

  @override
  void onData(void Function(void data)? handleData) {}

  @override
  void onError(Function? handleError) {}

  @override
  void onDone(void Function()? handleDone) {}

  @override
  void pause([Future<void>? resumeSignal]) {}

  @override
  void resume() {}

  @override
  bool get isPaused => false;

  @override
  Future<E> asFuture<E>([E? futureValue]) async {
    return futureValue as E;
  }
}

/// Checks if document is currently hidden in the web browser.
bool isWebDocumentHidden() {
  try {
    return web.document.hidden;
  } catch (_) {
    return false;
  }
}
