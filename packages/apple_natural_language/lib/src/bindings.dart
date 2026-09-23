import 'dart:async';

import 'messages.g.dart';

/// The platform APIs the apple_natural_language library talks to.
///
/// Replace [instance] in tests to run the Dart layer against fakes.
class NaturalLanguageBindings {
  /// Creates bindings, defaulting to the real platform channels.
  NaturalLanguageBindings({
    AppleNaturalLanguageHostApi? host,
    AppleNaturalLanguagePlatformApi? platform,
  }) : host = host ?? AppleNaturalLanguageHostApi(),
       platform = platform ?? AppleNaturalLanguagePlatformApi();

  /// The bindings every object uses.
  static NaturalLanguageBindings instance = NaturalLanguageBindings();

  /// The Natural Language API.
  final AppleNaturalLanguageHostApi host;

  /// The always-available platform API.
  final AppleNaturalLanguagePlatformApi platform;

  /// Releases native handles whose Dart owners were garbage collected.
  late final Finalizer<int> finalizer = Finalizer<int>(
    (handle) => unawaited(host.release(handle).catchError((Object _) {})),
  );
}
