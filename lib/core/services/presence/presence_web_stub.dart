import 'dart:async';

/// Stub for non-web platforms. Web listeners are no-ops on mobile and desktop.
StreamSubscription<dynamic>? initWebPresenceListeners({
  required void Function() onHide,
  required void Function() onShow,
}) {
  return null;
}

/// On non-web platforms, document is never considered hidden.
bool isWebDocumentHidden() => false;
