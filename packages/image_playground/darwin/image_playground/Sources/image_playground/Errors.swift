import Foundation

extension ImagePlaygroundPigeonError {
  convenience init(_ code: String, _ message: String) {
    self.init(code: code, message: message, details: nil)
  }
}

enum Errors {
  static func invalid(_ message: String) -> ImagePlaygroundPigeonError {
    ImagePlaygroundPigeonError("invalid_argument", message)
  }
  static func unsupported(_ message: String) -> ImagePlaygroundPigeonError {
    ImagePlaygroundPigeonError("unsupported", message)
  }
  static func translate(_ error: Error) -> ImagePlaygroundPigeonError {
    if let error = error as? ImagePlaygroundPigeonError { return error }
    let native = error as NSError
    return ImagePlaygroundPigeonError(code: "image_error", message: native.localizedDescription,
      details: "\(native.domain):\(native.code)")
  }
}
