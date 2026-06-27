// =============================================================================
// FramePreprocessor
// -----------------------------------------------------------------------------
// Pure-Dart YUV420 → RGB → resized Float32 tensor pipeline.
//
// Why a standalone class instead of an instance method on HazardDetector?
//   The ensemble runs FOUR YOLO models on every processed frame, all of which
//   expect the SAME 640×640 RGB Float32 input. Doing this conversion once per
//   model would quadruple our biggest cost (pure-Dart YUV→RGB is ~300–600 ms
//   per frame on this device). By isolating the work in this class the
//   ensemble can call it ONCE per frame and pass the resulting tensor by
//   reference into each interpreter.
// =============================================================================

import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

/// The square input size expected by all four YOLOv8n hazard models.
const int kInputSize = 640;

class FramePreprocessor {
  FramePreprocessor._(); // static-only

  /// Converts a [CameraImage] (YUV420 on Android) to a flat [Float32List]
  /// of shape [1 * kInputSize * kInputSize * 3] with RGB values normalised
  /// to [0.0, 1.0].
  ///
  /// Returns `null` only if the YUV→RGB conversion fails (very rare —
  /// indicates a malformed camera buffer).
  ///
  /// The returned tensor can be shared across multiple TFLite interpreters
  /// SAFELY because each interpreter copies the input into its own internal
  /// buffer before running the kernels; nothing mutates the tensor in place.
  static Float32List? preprocess(CameraImage image) {
    final img.Image? rgb = _yuv420ToRgb(image);
    if (rgb == null) return null;

    // Resize to the model's expected square input (stretches the frame;
    // this is fine for detection — YOLO is robust to moderate distortion).
    final img.Image resized = img.copyResize(
      rgb,
      width: kInputSize,
      height: kInputSize,
      interpolation: img.Interpolation.linear,
    );

    // Flatten to Float32List in row-major (H, W, C) order, values in [0,1].
    final Float32List tensor =
        Float32List(1 * kInputSize * kInputSize * 3);
    int idx = 0;
    for (int y = 0; y < kInputSize; y++) {
      for (int x = 0; x < kInputSize; x++) {
        final img.Pixel pixel = resized.getPixel(x, y);
        tensor[idx++] = pixel.r / 255.0;
        tensor[idx++] = pixel.g / 255.0;
        tensor[idx++] = pixel.b / 255.0;
      }
    }
    return tensor;
  }

  /// Converts Android's YUV_420_888 [CameraImage] to an [img.Image] (RGB).
  ///
  /// Android cameras produce semi-planar (NV12/NV21) or fully-planar YUV data.
  /// The [CameraImage.planes[1].bytesPerPixel] value indicates the stride
  /// between consecutive U (or V) samples:
  ///   - bytesPerPixel == 1  → fully planar (I420)
  ///   - bytesPerPixel == 2  → semi-planar (NV12 / NV21)
  static img.Image? _yuv420ToRgb(CameraImage image) {
    final int width = image.width;
    final int height = image.height;

    final Uint8List yBytes = image.planes[0].bytes;
    final Uint8List uBytes = image.planes[1].bytes;
    final Uint8List vBytes = image.planes[2].bytes;

    final int yRowStride = image.planes[0].bytesPerRow;
    final int uvRowStride = image.planes[1].bytesPerRow;
    final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

    final img.Image rgbImage = img.Image(width: width, height: height);

    for (int row = 0; row < height; row++) {
      for (int col = 0; col < width; col++) {
        final int yIndex = row * yRowStride + col;
        final int uvIndex =
            (row ~/ 2) * uvRowStride + (col ~/ 2) * uvPixelStride;

        // YUV → RGB conversion (BT.601 coefficients, offset chroma by 128).
        final int y = yBytes[yIndex];
        final int u = uBytes[uvIndex] - 128;
        final int v = vBytes[uvIndex] - 128;

        final int r = (y + 1.370705 * v).round().clamp(0, 255);
        final int g =
            (y - 0.337633 * u - 0.698001 * v).round().clamp(0, 255);
        final int b = (y + 1.732446 * u).round().clamp(0, 255);

        rgbImage.setPixelRgb(col, row, r, g, b);
      }
    }
    return rgbImage;
  }
}
