/// Flutter bindings for Apple's MediaIntelligence framework: grouping faces
/// into people across a photo library, and finding video highlights and key
/// frames. Requires iOS 27 or macOS 27.
library;

export 'src/errors.dart'
    show MediaIntelligenceErrorCode, MediaIntelligenceException;
export 'src/face_groups.dart';
export 'src/media_intelligence.dart';
export 'src/video.dart';
