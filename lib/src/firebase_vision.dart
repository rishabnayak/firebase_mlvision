// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

part of firebase_mlvision;

enum _ImageType { file, bytes }

/// Indicates the image rotation.
///
/// Rotation is counter-clockwise.
enum ImageRotation { rotation0, rotation90, rotation180, rotation270 }

/// Indicates whether a model is ran on device or in the cloud.
enum ModelType { onDevice, cloud }

/// Indicates direction of selected camera
enum CameraDirection { front, back, external }

/// Indicates selected camera resolution
enum ResolutionSetting { low, medium, high }

const MethodChannel channel = MethodChannel('plugins.flutter.io/firebase_mlvision');

/// Returns the resolution preset as a String.
String serializeResolutionPreset(ResolutionSetting resolutionSetting) {
  switch (resolutionSetting) {
    case ResolutionSetting.high:
      return 'high';
    case ResolutionSetting.medium:
      return 'medium';
    case ResolutionSetting.low:
      return 'low';
  }
  throw ArgumentError('Unknown ResolutionSetting value');
}

CameraDirection _parseCameraDirection(String string) {
  switch (string) {
    case 'front':
      return CameraDirection.front;
    case 'back':
      return CameraDirection.back;
    case 'external':
      return CameraDirection.external;
  }
  throw ArgumentError('Unknown CameraDirection value');
}

/// Completes with a list of available cameras.
///
/// May throw a [FirebaseCameraException].
Future<List<FirebaseCameraDescription>> camerasAvailable() async {
  try {
    final List<Map<dynamic, dynamic>> cameras = await channel
        .invokeListMethod<Map<dynamic, dynamic>>('camerasAvailable');
    return cameras.map((Map<dynamic, dynamic> camera) {
      return FirebaseCameraDescription(
        name: camera['name'],
        lensDirection: _parseCameraDirection(camera['lensFacing']),
        sensorOrientation: camera['sensorOrientation'],
      );
    }).toList();
  } on PlatformException catch (e) {
    throw FirebaseCameraException(e.code, e.message);
  }
}

class FirebaseCameraDescription {
  FirebaseCameraDescription({this.name, this.lensDirection, this.sensorOrientation});

  final String name;
  final CameraDirection lensDirection;

  /// Clockwise angle through which the output image needs to be rotated to be upright on the device screen in its native orientation.
  ///
  /// **Range of valid values:**
  /// 0, 90, 180, 270
  ///
  /// On Android, also defines the direction of rolling shutter readout, which
  /// is from top to bottom in the sensor's coordinate system.
  final int sensorOrientation;

  @override
  bool operator ==(Object o) {
    return o is FirebaseCameraDescription &&
        o.name == name &&
        o.lensDirection == lensDirection;
  }

  @override
  int get hashCode {
    return hashValues(name, lensDirection);
  }

  @override
  String toString() {
    return '$runtimeType($name, $lensDirection, $sensorOrientation)';
  }
}

/// This is thrown when the plugin reports an error.
class FirebaseCameraException implements Exception {
  FirebaseCameraException(this.code, this.description);

  String code;
  String description;

  @override
  String toString() => '$runtimeType($code, $description)';
}

// Build the UI texture view of the video data with textureId.
class FirebaseCameraPreview extends StatelessWidget {
  const FirebaseCameraPreview(this.controller);

  final FirebaseVision controller;

  @override
  Widget build(BuildContext context) {
    return controller.value.isInitialized
        ? Texture(textureId: controller._textureId)
        : Container();
  }
}

/// The state of a [CameraController].
class FirebaseCameraValue {
  const FirebaseCameraValue({
    this.isInitialized,
    this.errorDescription,
    this.previewSize
  });

  const FirebaseCameraValue.uninitialized()
      : this(isInitialized: false);

  /// True after [FirebaseVision.initialize] has completed successfully.
  final bool isInitialized;

  final String errorDescription;

  /// The size of the preview in pixels.
  ///
  /// Is `null` until  [isInitialized] is `true`.
  final Size previewSize;

  /// Convenience getter for `previewSize.height / previewSize.width`.
  ///
  /// Can only be called when [initialize] is done.
  double get aspectRatio => previewSize.height / previewSize.width;

  bool get hasError => errorDescription != null;

  FirebaseCameraValue copyWith({
    bool isInitialized,
    bool isRecordingVideo,
    bool isTakingPicture,
    bool isStreamingImages,
    String errorDescription,
    Size previewSize,
  }) {
    return FirebaseCameraValue(
      isInitialized: isInitialized ?? this.isInitialized,
      errorDescription: errorDescription,
      previewSize: previewSize ?? this.previewSize,
    );
  }

  @override
  String toString() {
    return '$runtimeType('
        'isInitialized: $isInitialized, '
        'errorDescription: $errorDescription, '
        'previewSize: $previewSize )';
  }
}

/// The Firebase machine learning vision API.
///
/// You can get an instance by calling [FirebaseVision.instance] and then get
/// a detector from the instance:
///
/// ```dart
/// TextRecognizer textRecognizer = FirebaseVision.instance.textRecognizer();
/// ```
class FirebaseVision extends ValueNotifier<FirebaseCameraValue> {
  FirebaseVision(
    this.description,
    this.resolutionPreset
  ) : super(const FirebaseCameraValue.uninitialized());

  final FirebaseCameraDescription description;
  final ResolutionSetting resolutionPreset;
  static int nextHandle = 0;

  int _textureId;
  bool _isDisposed = false;
  StreamSubscription<dynamic> _eventSubscription;
  Completer<void> _creatingCompleter;

  static const MethodChannel channel = MethodChannel('plugins.flutter.io/firebase_mlvision');

  /// Singleton of [FirebaseVision].
  ///
  /// Use this get an instance of a detector:
  ///
  /// ```dart
  /// TextRecognizer textRecognizer = FirebaseVision.instance.textRecognizer();
  /// ```
  // static final FirebaseVision instance = FirebaseVision._();

  /// Initializes the camera on the device.
  ///
  /// Throws a [CameraException] if the initialization fails.
  Future<void> initialize() async {
    if (_isDisposed) {
      return Future<void>.value();
    }
    try {
      _creatingCompleter = Completer<void>();
      final Map<String, dynamic> reply =
          await channel.invokeMapMethod<String, dynamic>(
        'initialize',
        <String, dynamic>{
          'cameraName': description.name,
          'resolutionPreset': serializeResolutionPreset(resolutionPreset)
        },
      );
      _textureId = reply['textureId'];
      value = value.copyWith(
        isInitialized: true,
        previewSize: Size(
          reply['previewWidth'].toDouble(),
          reply['previewHeight'].toDouble(),
        ),
      );
    } on PlatformException catch (e) {
      throw FirebaseCameraException(e.code, e.message);
    }
    _eventSubscription =
        EventChannel('plugins.flutter.io/firebase_mlvision$_textureId')
            .receiveBroadcastStream()
            .listen(_listener);
    _creatingCompleter.complete();
    return _creatingCompleter.future;
  }

  /// Listen to events from the native plugins.
  ///
  /// A "cameraClosing" event is sent when the camera is closed automatically by the system (for example when the app go to background). The plugin will try to reopen the camera automatically but any ongoing recording will end.
  void _listener(dynamic event) {
    final Map<dynamic, dynamic> map = event;
    if (_isDisposed) {
      return;
    }

    switch (map['eventType']) {
      case 'error':
        value = value.copyWith(errorDescription: event['errorDescription']);
        break;
      case 'cameraClosing':
        value = value.copyWith(isRecordingVideo: false);
        break;
    }
  }

  /// Releases the resources of this camera.
  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    super.dispose();
    if (_creatingCompleter != null) {
      await _creatingCompleter.future;
      await channel.invokeMethod<void>(
        'dispose',
        <String, dynamic>{'textureId': _textureId},
      );
      await _eventSubscription?.cancel();
    }
  }

  /// Creates an instance of [BarcodeDetector].
  Stream<List<Barcode>> addBarcodeDetector([BarcodeDetectorOptions options]) {
    BarcodeDetector detector = BarcodeDetector._(options ?? const BarcodeDetectorOptions(),
    nextHandle++,
    );
    return detector.startDetection();
  }

  /// Creates an instance of [VisionEdgeImageLabeler].
  VisionEdgeImageLabeler visionEdgeImageLabeler(
      String dataset, String modelLocation,
      [VisionEdgeImageLabelerOptions options]) {
    return VisionEdgeImageLabeler._(
        options: options ?? const VisionEdgeImageLabelerOptions(),
        dataset: dataset,
        handle: nextHandle++,
        modelLocation: modelLocation);
  }

  /// Creates an instance of [FaceDetector].
  FaceDetector faceDetector([FaceDetectorOptions options]) {
    return FaceDetector._(options ?? const FaceDetectorOptions(),
    nextHandle++,);
  }

  /// Creates an instance of [ModelManager].
  ModelManager modelManager() {
    return ModelManager._();
  }

  /// Creates an on device instance of [ImageLabeler].
  ImageLabeler imageLabeler([ImageLabelerOptions options]) {
    return ImageLabeler._(
      options: options ?? const ImageLabelerOptions(),
      modelType: ModelType.onDevice,
      handle: nextHandle++,
    );
  }

  /// Creates an instance of [TextRecognizer].
  TextRecognizer textRecognizer() => TextRecognizer._(
    modelType: ModelType.onDevice,
    handle: nextHandle++,
  );

  /// Creates a cloud instance of [ImageLabeler].
  ImageLabeler cloudImageLabeler([CloudImageLabelerOptions options]) {
    return ImageLabeler._(
      options: options ?? const CloudImageLabelerOptions(),
      modelType: ModelType.cloud,
      handle: nextHandle++,
    );
  }
}

/// Represents an image object used for both on-device and cloud API detectors.
///
/// Create an instance by calling one of the factory constructors.
class FirebaseVisionImage {
  FirebaseVisionImage._({
    @required _ImageType type,
    FirebaseVisionImageMetadata metadata,
    File imageFile,
    Uint8List bytes,
  })  : _imageFile = imageFile,
        _metadata = metadata,
        _bytes = bytes,
        _type = type;

  /// Construct a [FirebaseVisionImage] from a file.
  factory FirebaseVisionImage.fromFile(File imageFile) {
    assert(imageFile != null);
    return FirebaseVisionImage._(
      type: _ImageType.file,
      imageFile: imageFile,
    );
  }

  /// Construct a [FirebaseVisionImage] from a file path.
  factory FirebaseVisionImage.fromFilePath(String imagePath) {
    assert(imagePath != null);
    return FirebaseVisionImage._(
      type: _ImageType.file,
      imageFile: File(imagePath),
    );
  }

  /// Construct a [FirebaseVisionImage] from a list of bytes.
  ///
  /// On Android, expects `android.graphics.ImageFormat.NV21` format. Note:
  /// Concatenating the planes of `android.graphics.ImageFormat.YUV_420_888`
  /// into a single plane, converts it to `android.graphics.ImageFormat.NV21`.
  ///
  /// On iOS, expects `kCVPixelFormatType_32BGRA` format. However, this should
  /// work with most formats from `kCVPixelFormatType_*`.
  factory FirebaseVisionImage.fromBytes(
    Uint8List bytes,
    FirebaseVisionImageMetadata metadata,
  ) {
    assert(bytes != null);
    assert(metadata != null);
    return FirebaseVisionImage._(
      type: _ImageType.bytes,
      bytes: bytes,
      metadata: metadata,
    );
  }

  final Uint8List _bytes;
  final File _imageFile;
  final FirebaseVisionImageMetadata _metadata;
  final _ImageType _type;

  Map<String, dynamic> _serialize() => <String, dynamic>{
        'type': _enumToString(_type),
        'bytes': _bytes,
        'path': _imageFile?.path,
        'metadata': _type == _ImageType.bytes ? _metadata._serialize() : null,
      };
}

/// Plane attributes to create the image buffer on iOS.
///
/// When using iOS, [bytesPerRow], [height], and [width] throw [AssertionError]
/// if `null`.
class FirebaseVisionImagePlaneMetadata {
  FirebaseVisionImagePlaneMetadata({
    @required this.bytesPerRow,
    @required this.height,
    @required this.width,
  })  : assert(defaultTargetPlatform == TargetPlatform.iOS
            ? bytesPerRow != null
            : true),
        assert(defaultTargetPlatform == TargetPlatform.iOS
            ? height != null
            : true),
        assert(
            defaultTargetPlatform == TargetPlatform.iOS ? width != null : true);

  /// The row stride for this color plane, in bytes.
  final int bytesPerRow;

  /// Height of the pixel buffer on iOS.
  final int height;

  /// Width of the pixel buffer on iOS.
  final int width;

  Map<String, dynamic> _serialize() => <String, dynamic>{
        'bytesPerRow': bytesPerRow,
        'height': height,
        'width': width,
      };
}

/// Image metadata used by [FirebaseVision] detectors.
///
/// [rotation] defaults to [ImageRotation.rotation0]. Currently only rotates on
/// Android.
///
/// When using iOS, [rawFormat] and [planeData] throw [AssertionError] if
/// `null`.
class FirebaseVisionImageMetadata {
  FirebaseVisionImageMetadata({
    @required this.size,
    @required this.rawFormat,
    @required this.planeData,
    this.rotation = ImageRotation.rotation0,
  })  : assert(size != null),
        assert(defaultTargetPlatform == TargetPlatform.iOS
            ? rawFormat != null
            : true),
        assert(defaultTargetPlatform == TargetPlatform.iOS
            ? planeData != null
            : true),
        assert(defaultTargetPlatform == TargetPlatform.iOS
            ? planeData.isNotEmpty
            : true);

  /// Size of the image in pixels.
  final Size size;

  /// Rotation of the image for Android.
  ///
  /// Not currently used on iOS.
  final ImageRotation rotation;

  /// Raw version of the format from the iOS platform.
  ///
  /// Since iOS can use any planar format, this format will be used to create
  /// the image buffer on iOS.
  ///
  /// On iOS, this is a `FourCharCode` constant from Pixel Format Identifiers.
  /// See https://developer.apple.com/documentation/corevideo/1563591-pixel_format_identifiers?language=objc
  ///
  /// Not used on Android.
  final dynamic rawFormat;

  /// The plane attributes to create the image buffer on iOS.
  ///
  /// Not used on Android.
  final List<FirebaseVisionImagePlaneMetadata> planeData;

  int _imageRotationToInt(ImageRotation rotation) {
    switch (rotation) {
      case ImageRotation.rotation90:
        return 90;
      case ImageRotation.rotation180:
        return 180;
      case ImageRotation.rotation270:
        return 270;
      default:
        assert(rotation == ImageRotation.rotation0);
        return 0;
    }
  }

  Map<String, dynamic> _serialize() => <String, dynamic>{
        'width': size.width,
        'height': size.height,
        'rotation': _imageRotationToInt(rotation),
        'rawFormat': rawFormat,
        'planeData': planeData
            .map((FirebaseVisionImagePlaneMetadata plane) => plane._serialize())
            .toList(),
      };
}

String _enumToString(dynamic enumValue) {
  final String enumString = enumValue.toString();
  return enumString.substring(enumString.indexOf('.') + 1);
}
