import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct ClipboardImageAnnotationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let imageURL: URL
    let onSave: (Data) async -> Bool

    @State private var image: CGImage?
    @State private var strokes: [[CGPoint]] = []
    @State private var activeStroke: Int?
    @State private var isSaving = false
    @State private var loadFailed = false
    @State private var saveFailed = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Annotate Image")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .disabled(isSaving)
                Button {
                    saveCopy()
                } label: {
                    Label(isSaving ? "Saving…" : "Save Copy", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(image == nil || strokes.isEmpty || isSaving)
            }
            .padding()

            GeometryReader { geometry in
                ZStack {
                    Color.black.opacity(0.04)
                    if let image {
                        let size = fittedSize(for: image, in: geometry.size)
                        Canvas { context, canvasSize in
                            context.draw(
                                context.resolve(Image(decorative: image, scale: 1)),
                                in: CGRect(origin: .zero, size: canvasSize))
                            for stroke in strokes {
                                guard let first = stroke.first else { continue }
                                var path = Path()
                                path.move(
                                    to: CGPoint(
                                        x: first.x * canvasSize.width,
                                        y: first.y * canvasSize.height))
                                for point in stroke.dropFirst() {
                                    path.addLine(
                                        to: CGPoint(
                                            x: point.x * canvasSize.width,
                                            y: point.y * canvasSize.height))
                                }
                                context.stroke(
                                    path, with: .color(.red),
                                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                            }
                        }
                        .frame(width: size.width, height: size.height)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard size.width > 0, size.height > 0 else { return }
                                    let point = CGPoint(
                                        x: min(1, max(0, value.location.x / size.width)),
                                        y: min(1, max(0, value.location.y / size.height)))
                                    if let activeStroke {
                                        strokes[activeStroke].append(point)
                                    } else {
                                        strokes.append([point])
                                        activeStroke = strokes.index(before: strokes.endIndex)
                                    }
                                }
                                .onEnded { _ in activeStroke = nil })
                    } else if loadFailed {
                        Text("Could not load this image.")
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal)
            .padding(.bottom)

            HStack {
                Text(
                    saveFailed
                        ? "Could not save the annotated image."
                        : "Draw on the image. Save Copy adds a separate history entry."
                )
                .font(.callout)
                .foregroundColor(saveFailed ? .red : .secondary)
                Spacer()
            }
            .padding([.horizontal, .bottom])
        }
        .task(id: imageURL) {
            image = await Task.detached(priority: .userInitiated) {
                Self.loadImage(at: imageURL)
            }.value
            loadFailed = image == nil
        }
    }

    private func fittedSize(for image: CGImage, in available: CGSize) -> CGSize {
        guard available.width > 0, available.height > 0 else { return .zero }
        let scale = min(
            available.width / CGFloat(image.width), available.height / CGFloat(image.height))
        return CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
    }

    private func saveCopy() {
        guard let image, !strokes.isEmpty else { return }
        isSaving = true
        saveFailed = false
        let strokes = strokes
        Task {
            let data = await Task.detached(priority: .userInitiated) {
                Self.annotatedPNG(image, strokes: strokes)
            }.value
            guard let data else {
                isSaving = false
                saveFailed = true
                return
            }
            guard await onSave(data) else {
                isSaving = false
                saveFailed = true
                return
            }
            dismiss()
        }
    }

    private nonisolated static func loadImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(
            source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    private nonisolated static func annotatedPNG(_ image: CGImage, strokes: [[CGPoint]]) -> Data? {
        guard
            let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.draw(image, in: rect)
        context.setStrokeColor(CGColor(red: 1, green: 0.12, blue: 0.2, alpha: 0.95))
        context.setLineWidth(max(2, CGFloat(image.width) * 0.006))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for stroke in strokes {
            guard let first = stroke.first else { continue }
            context.beginPath()
            context.move(
                to: CGPoint(x: first.x * rect.width, y: (1 - first.y) * rect.height))
            for point in stroke.dropFirst() {
                context.addLine(
                    to: CGPoint(x: point.x * rect.width, y: (1 - point.y) * rect.height))
            }
            context.strokePath()
        }

        guard let outputImage = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, outputImage, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
