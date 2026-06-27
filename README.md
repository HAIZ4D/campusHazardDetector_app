<div align="center">

# Campus Hazard Detector

### Real-time campus safety detection powered by a 4-model YOLO ensemble, a neural meta-classifier, and Google Gemini for actionable AI guidance.

[![Flutter](https://img.shields.io/badge/Flutter-3.7%2B-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![TFLite](https://img.shields.io/badge/TensorFlow_Lite-FF6F00?logo=tensorflow&logoColor=white)](https://www.tensorflow.org/lite)
[![Gemini](https://img.shields.io/badge/Gemini_2.5_Flash-8E75B2?logo=google&logoColor=white)](https://ai.google.dev/)
[![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?logo=android&logoColor=white)](https://www.android.com)
[![Course](https://img.shields.io/badge/Course-CSC4602-FF7043)]()
[![License](https://img.shields.io/badge/License-MIT-blue.svg)]()

---

**4 YOLO models** &nbsp;·&nbsp; **2 meta-classifiers** &nbsp;·&nbsp; **17 hazards** &nbsp;·&nbsp; **4 risk families** &nbsp;·&nbsp; **on-device inference** &nbsp;·&nbsp; **AI safety advice**

</div>

---

## Table of contents

1. [Overview](#overview)
2. [Key features](#key-features)
3. [Architecture](#architecture)
4. [Tech stack](#tech-stack)
5. [Hazard catalogue](#hazard-catalogue)
6. [Getting started](#getting-started)
7. [Configuration](#configuration)
8. [How the ensemble works](#how-the-ensemble-works)
9. [Project structure](#project-structure)
10. [Team](#team)
11. [License](#license)

---

## Overview

The **Campus Hazard Detector** is a Flutter Android app built for the CSC4602 group assignment. It identifies 17 distinct campus safety hazards in real time through the phone camera, then asks Google's Gemini API for a short, friendly, action-oriented safety note for each saved detection.

What sets this project apart from a typical single-model object detector:

| | |
|---|---|
| **Ensemble of 4 independently-trained YOLOv8 models** | Each team member trained their own model; the app fuses all four at inference time. |
| **Neural meta-classifier with agreement features** | A small dense NN takes per-model confidences + cross-model agreement signals and outputs a refined verdict. |
| **Two-tier classification with fallback** | Always shows a specific hazard label; falls back to a general category when the specific classifier isn't confident enough. |
| **AI-generated safety guidance** | Gemini 2.5 Flash returns a 3-section, ~150-word, conversational safety note per saved detection. Cached on disk to avoid repeat API costs. |
| **Persistent, report-friendly history** | Every saved record carries full provenance (which models fired, with what confidence) so the technical report can quote real numbers. |

---

## Key features

### Live detection
- 4 YOLOv8n models running sequentially on every Nth camera frame (user-tunable from Settings)
- Cross-model bounding box matching via IoU ≥ 0.3
- Bounding boxes coloured by parent hazard category
- "General hazard" fallback when the specific classifier dips below 50% confidence
- Floating glass-style overlay chips for zone + detection count

### Capture + evidence
- One-tap full-resolution JPEG capture of the current frame
- Each record stores the meta-classifier verdict, per-model confidences, zone, severity, and Gemini cache
- Saved records survive app restarts (JSON-on-disk persistence)
- History stats header for the report: multi-model vs single-model %, group-size histogram

### AI safety guidance
- Structured 5-field prompt (hazard type, parent, zone, severity, confidence)
- Gemini returns exactly three sections: *What this means / Why it matters / What to do*
- 120–200 words, conversational tone, no clinical jargon
- Cached per-record — never re-called on revisit
- Regenerate on demand with one tap; loading and error states preserve the existing text

### Reference + settings
- Hazards catalogue tab listing all 17 detectable hazards grouped by parent
- Settings tab with live frame-skip slider, Gemini connection self-test, and storage controls
- Persisted user settings (frame skip + last-used zone restored on next launch)

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                       Per-frame pipeline                          │
└──────────────────────────────────────────────────────────────────┘

                        Camera frame  (YUV420)
                              │
                              ▼
                    ┌─────────────────────┐
            STAGE 1 │  Preprocess (once)  │   YUV → RGB, resize to 640×640
                    └──────────┬──────────┘
                               │ Float32 tensor, shared by all 4 models
                               ▼
        ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐
STAGE 2 │  Haizad  │ │ Sabrina  │ │  Hafiy   │ │  Yasmin  │
        │ YOLOv8n  │ │ YOLOv8n  │ │ YOLOv8n  │ │ YOLOv8n  │
        └─────┬────┘ └─────┬────┘ └─────┬────┘ └─────┬────┘
              │            │            │            │
              └─────┬──────┴────────────┴────────────┘
                    │  raw detections × N
                    ▼
                ┌─────────────────────────────┐
        STAGE 3 │      Label harmonisation    │   19 raw classes → 17 canonical
                └────────────┬────────────────┘   + 4 parent categories
                             │
                             ▼
                ┌─────────────────────────────┐
        STAGE 4 │   Cross-model IoU matching  │   IoU ≥ 0.3, never same-model
                └────────────┬────────────────┘   → MatchGroup per physical hazard
                             │
                             ▼
                ┌─────────────────────────────┐
        STAGE 5 │     Meta-classifier (×2)    │   24-D feature vector
                │  specific [1,17]   parent [1,4] │      ↓
                └────────────┬────────────────┘   softmax verdicts
                             │
                             ▼
                ┌─────────────────────────────┐
                │  ClassifiedDetection list   │   → bounding box overlay
                └─────────────────────────────┘   → capture + history
```

After capture, the AI flow:

```
DetectionRecord ──── 5 fields ────► Gemini 2.5 Flash ────► 3-section safety note
                                                                  │
                                                                  ▼
                                                          cached into record
                                                          (no repeat calls)
```

---

## Tech stack

| Layer | Choice | Why |
|---|---|---|
| Framework | **Flutter 3.7+** | Single codebase, fast iteration, great camera plugins |
| Detection runtime | **`tflite_flutter` 0.12** | Official Google Dart bindings, mmap-backed inference |
| Detection models | **YOLOv8n × 4** | Small enough for mobile CPU, ~50–200 ms per inference |
| Meta-classifier | **Custom dense NN** (TFLite) | 24-D in → 17-way + 4-way softmax out, sub-ms inference |
| Generative AI | **Gemini 2.5 Flash** (`google_generative_ai`) | Cheap, fast, excellent for structured short text |
| Camera | **`camera` 0.11** | `startImageStream` for real-time per-frame inference |
| Image pipeline | **`image` 4.x** | Pure-Dart YUV→RGB + resize |
| State | **`provider` 6.x** | Lightweight `ChangeNotifier` for shared services |
| Secrets | **`flutter_dotenv` 5.x** | `.env`-based key loading at runtime |
| Persistence | **Plain JSON file** | App docs dir; no DB overhead at this scale |
| Theming | **Material 3 (light)** | Soft warm-grey surfaces, deep-orange accent |

---

## Hazard catalogue

The app detects 17 specific hazards across 4 colour-coded parent categories.

<table>
<tr>
<td valign="top">

### Structural / Injury  &nbsp;`▮ red`
Things that can cut, snag, or fall on someone.

- Broken Fence
- Broken Lamp Post
- Protruding Fastener
- Rusted Equipment
- Sharp Object
- Unclear / Broken Signboard

</td>
<td valign="top">

### Surface / Ground  &nbsp;`▮ blue`
Walking-surface issues — slippery, uneven, or hidden under water.

- Damaged Flooring
- Mossy Surface
- Open / Uncovered Drain
- Pothole
- Uneven Floor
- Waterlogged Field
- Wet Floor

</td>
</tr>
<tr>
<td valign="top">

### Obstruction  &nbsp;`▮ orange`
Things in the way — overgrowth, fallen branches, blocked paths.

- Fallen Branch
- Obstacle Walkway
- Overgrown Vegetation

</td>
<td valign="top">

### Hygiene  &nbsp;`▮ amber`
Waste-related hazards that attract pests or pose a health risk.

- Overflowing Trash Bin

</td>
</tr>
</table>

---

## Getting started

### Prerequisites

- **Flutter 3.7+** with Dart 3.x — [install](https://docs.flutter.dev/get-started/install)
- **Android Studio** with Android SDK 36
- **A physical Android device** (API 21+) — emulators don't have a camera and TFLite is much slower under emulation
- **A Gemini API key** for the AI recommendation feature — [free tier at AI Studio](https://aistudio.google.com/apikey)

### Setup

1. **Clone:**
   ```bash
   git clone https://github.com/HAIZ4D/campusHazardDetector_app.git
   cd campusHazardDetector_app
   ```

2. **Drop the model files into `assets/models/`** (distributed separately, ~48 MB total):
   ```
   assets/models/
   ├── haizad_model.tflite             ← YOLOv8n
   ├── sabrina_model.tflite            ← YOLOv8n
   ├── hafiy_model.tflite              ← YOLOv8n
   ├── yasmin_model.tflite             ← YOLOv8n
   ├── meta_classifier_specific.tflite ← dense NN
   ├── meta_classifier_parent.tflite   ← dense NN
   └── meta_classifier_config.json     ← class + feature schema
   ```

3. **Configure the Gemini API key:**
   ```bash
   cp .env.example .env
   ```
   Edit `.env` and set:
   ```
   GEMINI_API_KEY=your_actual_key_from_aistudio
   ```

4. **Install Flutter dependencies:**
   ```bash
   flutter pub get
   ```

5. **Run on a connected device:**
   ```bash
   flutter devices       # lists devices, copy the id
   flutter run -d <device-id>
   ```

### Building a release APK

```bash
flutter build apk --release
```
APK lands at `build/app/outputs/flutter-apk/app-release.apk`.

---

## Configuration

### Gemini API key restrictions

If the AI tab returns `Request from referer <empty> are blocked`, your key has an **HTTP referrers** application restriction set — Android apps don't send a `Referer` header, so the request is rejected.

Two fixes (both in <https://console.cloud.google.com/apis/credentials>):

- **Quick (dev):** edit the key → Application restrictions → **None** → Save.
- **Proper (prod):** edit the key → Application restrictions → **Android apps** → add your app's package name + SHA-1.

For this app's debug build:
- Package name: `com.csc4602.machinelearning_app`
- SHA-1 fingerprint: get yours with `cd android && ./gradlew signingReport`

### Runtime tuning

In the **Settings** tab:

| Setting | Range | Default | Effect |
|---|---|---|---|
| Frame skip | 1 – 4 | 2 | Run all 4 models every Nth frame. Lower = accurate but slow UI; higher = smoother but staler detections. |
| Last zone | enum | Unspecified | Restored on next launch, becomes the default for the zone picker. |

The specific-vs-parent fallback threshold (50%) lives in `lib/widgets/display_rules.dart` as a compile-time constant.

---

## How the ensemble works

### 1. Preprocessing (shared)
YUV420 → RGB → 640×640 Float32 tensor, done **once per processed frame** in `FramePreprocessor`. This is the dominant cost on mobile (~300–600 ms pure-Dart), so duplicating it 4× would be a non-starter.

### 2. YOLO inference (parallel logical, sequential physical)
Each of the 4 `HazardDetector` instances runs `Interpreter.run()` on the shared tensor. Each model outputs `[1, 9, 8400]` — 4 bbox coords + 5 class scores × 8400 anchors. `YoloProcessor` does per-class threshold + greedy NMS and tags every surviving box with its source model key.

### 3. Label harmonisation
The 19 unique raw class names across the 4 models map to 17 canonical labels via `LabelHarmoniser`. Example: both `open_drain` (Hafiy) and `uncovered_drain` (Sabrina) → `Open/Uncovered Drain`. Unmapped raw classes are dropped with a debug log.

### 4. Cross-model IoU matching
`CrossModelMatcher` is a confidence-anchored greedy algorithm:
1. Sort detections by confidence descending.
2. Walk the list; the first unassigned detection becomes a seed.
3. Add other-model detections whose IoU with the seed is ≥ 0.3 (and whose source model isn't already in the group).
4. Repeat. Each detection ends up in exactly one `MatchGroup`.

Same-model boxes are never merged (per assignment spec). The result is one group per physical hazard, with 1 to 4 contributing models.

### 5. Meta-classifier
For each match group, `MetaClassifier.buildFeatureVector(group)` produces a 24-D Float32:

| Slot | Source | Value |
|---|---|---|
| 0 | `confidenceFor('haizad')` | 0 when haizad didn't fire |
| 1 | `confidenceFor('sabrina')` | 0 when sabrina didn't fire |
| 2 | `confidenceFor('hafiy')` | 0 when hafiy didn't fire |
| 3 | `confidenceFor('yasmin')` | 0 when yasmin didn't fire |
| 4 | `group.size` | number of models agreeing (1–4) |
| 5 | `group.maxConfidence` | max over firing members |
| 6 | `group.avgConfidence` | mean over firing members only |
| 7–23 | one-hot of representative's normalised label | exactly one 1.0 |

Two TFLite calls per group:
- `meta_classifier_specific.tflite` → `[1, 17]` softmax → top-1 label
- `meta_classifier_parent.tflite` → `[1, 4]` softmax → top-1 parent

The meta-classifier is free to override the raw YOLO label using cross-model evidence — e.g. a low-confidence `Pothole` from one model that overlaps a confident `Wet Floor` from another can be re-classified as `Wet Floor`.

### 6. UI fallback rule
If the specific classifier's confidence is below 50%, the overlay shows the parent label with a `GENERAL:` prefix and an amber background tint. The parent badge is shown either way.

---

## Project structure

```
machinelearning_app/
├── assets/models/                    # TFLite files + meta config (gitignored from public repo by you)
├── lib/
│   ├── main.dart                     # Entry, theme, provider wiring
│   ├── detection/                    # Single-model YOLO machinery
│   │   ├── detector.dart
│   │   ├── yolo_processor.dart
│   │   ├── frame_preprocessor.dart
│   │   └── detection_result.dart
│   ├── ensemble/                     # Multi-model pipeline
│   │   ├── ensemble_detector.dart
│   │   ├── ensemble_models.dart
│   │   ├── label_harmoniser.dart
│   │   ├── cross_model_matcher.dart
│   │   ├── match_group.dart
│   │   ├── meta_classifier.dart
│   │   ├── meta_classifier_config.dart
│   │   ├── meta_classifier_output.dart
│   │   ├── harmonised_detection.dart
│   │   └── classified_detection.dart
│   ├── models/                       # Data classes
│   │   ├── detection_record.dart
│   │   ├── hazard_zone.dart
│   │   └── hazard_severity.dart
│   ├── services/
│   │   ├── detection_history_service.dart
│   │   ├── app_settings_service.dart
│   │   └── gemini_service.dart
│   ├── widgets/
│   │   ├── bounding_box_overlay.dart
│   │   ├── parent_category_palette.dart
│   │   └── display_rules.dart
│   └── screens/
│       ├── main_shell.dart           # NavigationBar root with 4 tabs
│       ├── camera_screen.dart        # Live camera + capture
│       ├── history_screen.dart       # Saved records + stats header
│       ├── detection_detail_screen.dart  # Single record + Gemini
│       ├── hazards_screen.dart       # Catalogue
│       └── settings_screen.dart
├── android/                          # Android-specific config
├── .env.example                      # Template — copy to .env and add your key
└── pubspec.yaml
```

---

## Team

| Member | Trained model | Specialty |
|---|---|---|
| **Haizad** | `haizad_model.tflite` | Mossy Surface, Overgrown Vegetation, Protruding Fastener, Rusted Equipment, Waterlogged Field |
| **Sabrina** | `sabrina_model.tflite` | Damaged Flooring, Fallen Branch, Overflowing Trash, Uncovered Drain, Water Accumulation |
| **Hafiy** | `hafiy_model.tflite` | Open Drain, Overgrown Vegetation, Pothole, Sharp Object, Uneven Floor |
| **Yasmin** | `yasmin_model.tflite` | Broken Fence, Broken Lamppost, Broken Signboard, Fallen Branch, Obstacle Walkway |

Application runtime, ensemble pipeline, meta-classifier integration, AI guidance feature, and UI by **Haizad**.

---

## License

This project was built as part of an academic assignment (CSC4602). Code and structure may be reused for educational purposes.

---

<div align="center">

Built with **Flutter**, **TensorFlow Lite**, and **Google Gemini**.

</div>
