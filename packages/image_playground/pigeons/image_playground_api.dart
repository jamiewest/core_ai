import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    swiftOut:
        'darwin/image_playground/Sources/image_playground/Messages.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'ImagePlaygroundPigeonError'),
    dartPackageName: 'image_playground',
    copyrightHeader: 'pigeons/copyright.txt',
  ),
)
enum ImageKindMessage { file, encoded, pixels }

enum ConceptKindMessage { text, extracted, image, drawing }

enum StyleMessage {
  animation,
  illustration,
  sketch,
  emoji,
  externalProvider,
  any,
}

enum PersonalizationMessage { automatic, enabled, disabled }

enum VarietyMessage { automatic, high, low }

enum StrategyMessage { automatic, editExisting, generateNew }

class ImageInputMessage {
  ImageInputMessage({
    required this.kind,
    this.path,
    this.bytes,
    this.width,
    this.height,
    this.bytesPerRow,
  });
  ImageKindMessage kind;
  String? path;
  Uint8List? bytes;
  int? width;
  int? height;
  int? bytesPerRow;
}

class ConceptMessage {
  ConceptMessage({
    required this.kind,
    this.text,
    this.title,
    this.image,
    this.drawing,
  });
  ConceptKindMessage kind;
  String? text;
  String? title;
  ImageInputMessage? image;
  Uint8List? drawing;
}

class OptionsMessage {
  OptionsMessage({
    this.personalization,
    this.variety,
    this.strategy,
    this.width,
    this.height,
  });
  PersonalizationMessage? personalization;
  VarietyMessage? variety;
  StrategyMessage? strategy;
  double? width;
  double? height;
}

class ConfigurationMessage {
  ConfigurationMessage({
    required this.concepts,
    this.sourceImage,
    this.allowedStyles,
    this.selectedStyle,
    this.options,
  });
  List<ConceptMessage> concepts;
  ImageInputMessage? sourceImage;
  List<StyleMessage>? allowedStyles;
  StyleMessage? selectedStyle;
  OptionsMessage? options;
}

class CapabilitiesMessage {
  CapabilitiesMessage({
    required this.isSupported,
    required this.isAvailable,
    required this.supportsStyles,
    required this.supportsOptions,
    required this.supportsVersion27Options,
    required this.styles,
  });
  bool isSupported;
  bool isAvailable;
  bool supportsStyles;
  bool supportsOptions;
  bool supportsVersion27Options;
  List<StyleMessage> styles;
}

class SessionInfoMessage {
  SessionInfoMessage({
    required this.conceptCount,
    required this.hasSourceImage,
    required this.allowedStyles,
    this.selectedStyle,
    required this.isPresenting,
  });
  int conceptCount;
  bool hasSourceImage;
  List<StyleMessage> allowedStyles;
  StyleMessage? selectedStyle;
  bool isPresenting;
}

class ResultMessage {
  ResultMessage({
    required this.bytes,
    required this.typeIdentifier,
    required this.width,
    required this.height,
    this.contentIdentifier,
    this.contentDescription,
  });
  Uint8List bytes;
  String typeIdentifier;
  int width;
  int height;
  String? contentIdentifier;
  String? contentDescription;
}

@HostApi()
abstract class ImagePlaygroundPlatformApi {
  bool isSupported();
  CapabilitiesMessage capabilities();
}

@HostApi()
abstract class ImagePlaygroundHostApi {
  @async
  int prepare(ConfigurationMessage configuration);

  /// Completes with null for user or programmatic cancellation.
  @async
  ResultMessage? present(int handle);
  @async
  SessionInfoMessage info(int handle);
  @async
  void cancel(int handle);
  @async
  void release(int handle);
  @async
  int releaseAll();
  int liveHandleCount();
}
