#if canImport(ImagePlayground)
  import Foundation
  import ImagePlayground
  import PencilKit
  import CoreGraphics
  #if os(iOS)
    import UIKit
  #else
    import AppKit
  #endif

  @available(iOS 18.1, macOS 15.1, *)
  struct PreparedConfiguration: @unchecked Sendable {
    let message: ConfigurationMessage
    let concepts: [ImagePlaygroundConcept]
    let sourceImage: CGImage?

    static func decode(_ message: ConfigurationMessage) async throws -> PreparedConfiguration {
      do {
        let concepts = try message.concepts.map { concept -> ImagePlaygroundConcept in
          switch concept.kind {
          case .text, .extracted:
            guard let text = concept.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
              throw Errors.invalid("Text concepts cannot be blank.")
            }
            return concept.kind == .text ? .text(text) : .extracted(from: text, title: concept.title)
          case .image:
            guard let image = concept.image else { throw Errors.invalid("An image concept needs an image.") }
            return .image(try ImageBridge.decode(image))
          case .drawing:
            guard let data = concept.drawing?.data, !data.isEmpty, data.count <= ImageBridge.maxBytes else {
              throw Errors.invalid("A drawing needs PencilKit data, no larger than 64 MiB.")
            }
            return .drawing(try PKDrawing(data: data))
          }
        }
        return PreparedConfiguration(message: message, concepts: concepts,
          sourceImage: try message.sourceImage.map(ImageBridge.decode))
      } catch { throw Errors.translate(error) }
    }

    @MainActor
    func apply(to controller: ImagePlaygroundViewController) throws {
      controller.concepts = concepts
      if let sourceImage {
        #if os(iOS)
          controller.sourceImage = UIImage(cgImage: sourceImage)
        #else
          controller.sourceImage = NSImage(cgImage: sourceImage, size: .zero)
        #endif
      }
      if message.allowedStyles != nil || message.selectedStyle != nil {
        guard #available(iOS 18.4, macOS 15.4, *) else {
          throw Errors.unsupported("Style selection requires iOS 18.4 / macOS 15.4.")
        }
        if let allowed = message.allowedStyles {
          guard !allowed.isEmpty, Set(allowed).count == allowed.count else {
            throw Errors.invalid("Allowed styles must be nonempty and unique.")
          }
          controller.allowedGenerationStyles = try allowed.map(Self.style)
        }
        if let selected = message.selectedStyle {
          let style = try Self.style(selected)
          guard controller.allowedGenerationStyles.contains(style) else {
            throw Errors.invalid("The selected style must be in the allowed styles.")
          }
          controller.selectedGenerationStyle = style
        }
      }
      guard let options = message.options else { return }
      if options.variety != nil || options.strategy != nil || options.width != nil || options.height != nil {
        guard #available(iOS 26.4, macOS 26.4, *) else {
          throw Errors.unsupported("Generation options require iOS/macOS 26.4.")
        }
      }
      if #available(iOS 26.4, macOS 26.4, *) {
        var native = ImagePlaygroundOptions()
        if let personalization = options.personalization {
          switch personalization {
          case .automatic: native.personalization = .automatic
          case .enabled: native.personalization = .enabled
          case .disabled: native.personalization = .disabled
          }
        }
        if let variety = options.variety {
          switch variety {
          case .automatic: native.creationVariety = .automatic
          case .high: native.creationVariety = .high
          case .low: native.creationVariety = .low
          }
        }
        if options.strategy != nil || options.width != nil || options.height != nil {
          guard #available(iOS 27.0, macOS 27.0, *) else {
            throw Errors.unsupported("Creation strategy and size require iOS/macOS 27.")
          }
          if let strategy = options.strategy {
            switch strategy {
            case .automatic: native.creationStrategy = .automatic
            case .editExisting: native.creationStrategy = .editExisting
            case .generateNew: native.creationStrategy = .generateNew
            }
          }
          if options.width != nil || options.height != nil {
            guard let width = options.width, let height = options.height,
              width.isFinite, height.isFinite, width > 0, height > 0, width <= 16384, height <= 16384
            else { throw Errors.invalid("Size needs finite positive width and height, at most 16384.") }
            native.sizeSpecification = .closest(to: CGSize(width: width, height: height))
          }
        }
        controller.options = native
      } else if let personalization = options.personalization {
        guard #available(iOS 18.4, macOS 15.4, *) else {
          throw Errors.unsupported("Personalization requires iOS 18.4 / macOS 15.4.")
        }
        switch personalization {
        case .automatic: controller.personalizationPolicy = .automatic
        case .enabled: controller.personalizationPolicy = .enabled
        case .disabled: controller.personalizationPolicy = .disabled
        }
      }
    }

    @available(iOS 18.4, macOS 15.4, *)
    static func style(_ message: StyleMessage) throws -> ImagePlaygroundStyle {
      switch message {
      case .animation: return .animation
      case .illustration: return .illustration
      case .sketch: return .sketch
      case .emoji: return .emoji
      case .externalProvider:
        guard #available(iOS 26.0, macOS 26.0, *) else { throw Errors.unsupported("External providers require OS 26.") }
        return .externalProvider
      case .any:
        guard #available(iOS 27.0, macOS 27.0, *) else { throw Errors.unsupported("Any style requires OS 27.") }
        return .any
      }
    }

    @available(iOS 18.4, macOS 15.4, *)
    static func message(_ style: ImagePlaygroundStyle) -> StyleMessage? {
      if style == .animation { return .animation }
      if style == .illustration { return .illustration }
      if style == .sketch { return .sketch }
      if style == .emoji { return .emoji }
      if #available(iOS 26.0, macOS 26.0, *), style == .externalProvider { return .externalProvider }
      if #available(iOS 27.0, macOS 27.0, *), style == .any { return .any }
      return nil
    }
  }
#endif
