import Accelerate
import AVFoundation
import CoreImage
import Foundation

/// A type that renders a screen object.
public protocol ScreenRenderer: AnyObject {
    /// The CIContext instance.
    var context: CIContext { get }
    /// Specifies the backgroundColor for output video.
    var backgroundColor: CGColor { get set }
    /// Layouts a screen object.
    func layout(_ screenObject: ScreenObject)
    /// Draws a sceen object.
    func draw(_ screenObject: ScreenObject)
    /// Sets up the render target.
    func setTarget(_ pixelBuffer: CVPixelBuffer?)
}

final class ScreenRendererByCPU: ScreenRenderer {
    private static var format = vImage_CGImageFormat(
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        colorSpace: nil,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue),
        version: 0,
        decode: nil,
        renderingIntent: .defaultIntent)

    lazy var context = {
        guard let deive = MTLCreateSystemDefaultDevice() else {
            return CIContext(options: nil)
        }
        return CIContext(mtlDevice: deive)
    }()

    var backgroundColor = CGColor(red: 0x00, green: 0x00, blue: 0x00, alpha: 0x00) {
        didSet {
            guard backgroundColor != oldValue, let components = backgroundColor.components else {
                return
            }
            switch components.count {
            case 2:
                backgroundColorUInt8Array = [
                    UInt8(components[1] * 255),
                    UInt8(components[0] * 255),
                    UInt8(components[0] * 255),
                    UInt8(components[0] * 255)
                ]
            case 3:
                backgroundColorUInt8Array = [
                    UInt8(components[2] * 255),
                    UInt8(components[0] * 255),
                    UInt8(components[1] * 255),
                    UInt8(components[1] * 255)
                ]
            case 4:
                backgroundColorUInt8Array = [
                    UInt8(components[3] * 255),
                    UInt8(components[0] * 255),
                    UInt8(components[1] * 255),
                    UInt8(components[2] * 255)
                ]
            default:
                break
            }
        }
    }
    private var masks: [ScreenObject: vImage_Buffer] = [:]
    private var images: [ScreenObject: vImage_Buffer] = [:]
    private var canvas: vImage_Buffer = .init()
    private var converter: vImageConverter?
    private var pixelFormatType: OSType? {
        didSet {
            guard pixelFormatType != oldValue else {
                return
            }
            converter = nil
        }
    }
    private var backgroundColorUInt8Array: [UInt8] = [0x00, 0x00, 0x00, 0x00]

    func setTarget(_ pixelBuffer: CVPixelBuffer?) {
        guard let pixelBuffer else {
            return
        }
        pixelFormatType = pixelBuffer.pixelFormatType
        if converter == nil {
            let cvImageFormat = vImageCVImageFormat_CreateWithCVPixelBuffer(pixelBuffer).takeRetainedValue()
            vImageCVImageFormat_SetColorSpace(cvImageFormat, CGColorSpaceCreateDeviceRGB())
            converter = try? vImageConverter.make(
                sourceFormat: cvImageFormat,
                destinationFormat: Self.format
            )
        }
        guard let converter else {
            return
        }
        vImageBuffer_InitForCopyFromCVPixelBuffer(
            &canvas,
            converter,
            pixelBuffer,
            vImage_Flags(kvImageNoAllocate)
        )
        switch pixelFormatType {
        case kCVPixelFormatType_32ARGB:
            vImageBufferFill_ARGB8888(
                &canvas,
                &backgroundColorUInt8Array,
                vImage_Flags(kvImageNoFlags)
            )
        default:
            break
        }
    }

    func layout(_ screenObject: ScreenObject) {
        autoreleasepool {
            guard let image = screenObject.makeImage(self) else {
                return
            }
            do {
                images[screenObject]?.free()
                images[screenObject] = try vImage_Buffer(cgImage: image, format: Self.format)
                if 0 < screenObject.cornerRadius {
                    masks[screenObject] = ShapeFactory.shared.cornerRadius(screenObject.bounds.size, cornerRadius: screenObject.cornerRadius)
                } else {
                    masks[screenObject] = nil
                }
            } catch {
            }
        }
    }

    func draw(_ screenObject: ScreenObject) {
        guard var image = images[screenObject] else {
            return
        }

        if var mask = masks[screenObject] {
            vImageSelectChannels_ARGB8888(&mask, &image, &image, 0x8, vImage_Flags(kvImageNoFlags))
        }

        let origin = screenObject.bounds.origin
        let start = Int(origin.y) * canvas.rowBytes + Int(origin.x) * 4
        var destination = vImage_Buffer(
            data: canvas.data.advanced(by: start),
            height: image.height,
            width: image.width,
            rowBytes: canvas.rowBytes
        )

        switch pixelFormatType {
        case kCVPixelFormatType_32ARGB:
            vImageAlphaBlend_ARGB8888(
                &image,
                &destination,
                &destination,
                vImage_Flags(kvImageDoNotTile)
            )
        default:
            break
        }
    }
}