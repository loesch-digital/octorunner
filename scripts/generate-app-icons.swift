#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let masterIconPath = "docs/assets/app_icon.png"
let outputDir = "App/Resources/Assets.xcassets/AppIcon.appiconset"

let fileManager = FileManager.default
try fileManager.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

guard let nsImage = NSImage(contentsOfFile: masterIconPath),
      let masterCG = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("Could not load master icon at \(masterIconPath)")
}

struct IconSpec {
    let ptSize: Int
    let scale: Int
    var pixelSize: Int { ptSize * scale }
    var filename: String {
        scale == 1 ? "icon_\(ptSize)x\(ptSize).png" : "icon_\(ptSize)x\(ptSize)@2x.png"
    }
}

let specs: [IconSpec] = [
    .init(ptSize: 16, scale: 1),
    .init(ptSize: 16, scale: 2),
    .init(ptSize: 32, scale: 1),
    .init(ptSize: 32, scale: 2),
    .init(ptSize: 128, scale: 1),
    .init(ptSize: 128, scale: 2),
    .init(ptSize: 256, scale: 1),
    .init(ptSize: 256, scale: 2),
    .init(ptSize: 512, scale: 1),
    .init(ptSize: 512, scale: 2)
]

let colorSpace = CGColorSpaceCreateDeviceRGB()

for spec in specs {
    let px = spec.pixelSize
    guard let ctx = CGContext(
        data: nil,
        width: px,
        height: px,
        bitsPerComponent: 8,
        bytesPerRow: px * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Failed to create CGContext for \(px)x\(px)")
    }
    ctx.clear(CGRect(x: 0, y: 0, width: px, height: px))
    ctx.interpolationQuality = .high
    ctx.draw(masterCG, in: CGRect(x: 0, y: 0, width: px, height: px))

    guard let outCG = ctx.makeImage() else { fatalError() }
    let fileURL = URL(fileURLWithPath: "\(outputDir)/\(spec.filename)") as CFURL
    guard let dest = CGImageDestinationCreateWithURL(fileURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError()
    }
    CGImageDestinationAddImage(dest, outCG, nil)
    CGImageDestinationFinalize(dest)
}

let contentsJSON = """
{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""

try contentsJSON.write(toFile: "\(outputDir)/Contents.json", atomically: true, encoding: .utf8)
print("Generated all 10 macOS AppIcon resolutions with alpha transparency in \(outputDir)")
