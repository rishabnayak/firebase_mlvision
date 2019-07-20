#import "FirebaseMlVisionPlugin.h"
#import <AVFoundation/AVFoundation.h>
#import <libkern/OSAtomic.h>

static FlutterError *getFlutterError(NSError *error) {
    return [FlutterError errorWithCode:[NSString stringWithFormat:@"Error %d", (int)error.code]
                               message:error.domain
                               details:error.localizedDescription];
}

@interface FirebaseCam : NSObject <FlutterTexture,
AVCaptureVideoDataOutputSampleBufferDelegate,
AVCaptureAudioDataOutputSampleBufferDelegate,
FlutterStreamHandler>
@property(readonly, nonatomic) int64_t textureId;
@property(nonatomic, copy) void (^onFrameAvailable)();
@property(nonatomic) FlutterEventChannel *eventChannel;
@property(nonatomic) FlutterEventSink eventSink;
@property(readonly, nonatomic) AVCaptureSession *captureSession;
@property(readonly, nonatomic) AVCaptureDevice *captureDevice;
@property(readonly, nonatomic) AVCaptureVideoDataOutput *captureVideoOutput;
@property(readonly, nonatomic) AVCaptureInput *captureVideoInput;
@property(readonly) CVPixelBufferRef volatile latestPixelBuffer;
@property(readonly, nonatomic) CGSize previewSize;

- (instancetype)initWithCameraName:(NSString *)cameraName
                  resolutionPreset:(NSString *)resolutionPreset
                     dispatchQueue:(dispatch_queue_t)dispatchQueue
                             error:(NSError **)error;

- (void)start;
- (void)stop;
@end

@implementation FirebaseCam {
    dispatch_queue_t _dispatchQueue;
}

// Format used for video and image streaming.
FourCharCode const format = kCVPixelFormatType_32BGRA;

- (instancetype)initWithCameraName:(NSString *)cameraName
                  resolutionPreset:(NSString *)resolutionPreset
                     dispatchQueue:(dispatch_queue_t)dispatchQueue
                             error:(NSError **)error {
    self = [super init];
    NSAssert(self, @"super init cannot be nil");
    _dispatchQueue = dispatchQueue;
    _captureSession = [[AVCaptureSession alloc] init];
    _captureDevice = [AVCaptureDevice deviceWithUniqueID:cameraName];
    NSError *localError = nil;
    _captureVideoInput = [AVCaptureDeviceInput deviceInputWithDevice:_captureDevice
                                                               error:&localError];
    if (localError) {
        *error = localError;
        return nil;
    }
    _captureVideoOutput = [AVCaptureVideoDataOutput new];
    _captureVideoOutput.videoSettings =
    @{(NSString *)kCVPixelBufferPixelFormatTypeKey : @(format)};
    [_captureVideoOutput setAlwaysDiscardsLateVideoFrames:YES];
    [_captureVideoOutput setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
    
    AVCaptureConnection *connection =
    [AVCaptureConnection connectionWithInputPorts:_captureVideoInput.ports
                                           output:_captureVideoOutput];
    if ([_captureDevice position] == AVCaptureDevicePositionFront) {
        connection.videoMirrored = YES;
    }
    connection.videoOrientation = AVCaptureVideoOrientationPortrait;
    [_captureSession addInputWithNoConnections:_captureVideoInput];
    [_captureSession addOutputWithNoConnections:_captureVideoOutput];
    [_captureSession addConnection:connection];
    [self setCaptureSessionPreset:resolutionPreset];
    return self;
}

- (void)start {
    [_captureSession startRunning];
}

- (void)stop {
    [_captureSession stopRunning];
}

- (void)setCaptureSessionPreset:(NSString *)resolutionPreset {
    int presetIndex;
    if ([resolutionPreset isEqualToString:@"high"]) {
        presetIndex = 0;
    } else if ([resolutionPreset isEqualToString:@"medium"]) {
        presetIndex = 2;
    } else {
        NSAssert([resolutionPreset isEqualToString:@"low"], @"Unknown resolution preset %@",
                 resolutionPreset);
        presetIndex = 3;
    }
    switch (presetIndex) {
        case 0:
            if ([_captureSession canSetSessionPreset:AVCaptureSessionPreset3840x2160]) {
                _captureSession.sessionPreset = AVCaptureSessionPreset3840x2160;
                _previewSize = CGSizeMake(3840, 2160);
                break;
            }
        case 1:
            if ([_captureSession canSetSessionPreset:AVCaptureSessionPreset1920x1080]) {
                _captureSession.sessionPreset = AVCaptureSessionPreset1920x1080;
                _previewSize = CGSizeMake(1920, 1080);
                break;
            }
        case 2:
            if ([_captureSession canSetSessionPreset:AVCaptureSessionPreset1280x720]) {
                _captureSession.sessionPreset = AVCaptureSessionPreset1280x720;
                _previewSize = CGSizeMake(1280, 720);
                break;
            }
        case 3:
            if ([_captureSession canSetSessionPreset:AVCaptureSessionPreset640x480]) {
                _captureSession.sessionPreset = AVCaptureSessionPreset640x480;
                _previewSize = CGSizeMake(640, 480);
                break;
            }
        case 4:
            if ([_captureSession canSetSessionPreset:AVCaptureSessionPreset352x288]) {
                _captureSession.sessionPreset = AVCaptureSessionPreset352x288;
                _previewSize = CGSizeMake(352, 288);
                break;
            }
        default: {
            NSException *exception = [NSException
                                      exceptionWithName:@"NoAvailableCaptureSessionException"
                                      reason:@"No capture session available for current capture session."
                                      userInfo:nil];
            @throw exception;
        }
    }
}

- (void)captureOutput:(AVCaptureOutput *)output
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    if (output == _captureVideoOutput) {
        CVPixelBufferRef newBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        CFRetain(newBuffer);
        CVPixelBufferRef old = _latestPixelBuffer;
        while (!OSAtomicCompareAndSwapPtrBarrier(old, newBuffer, (void **)&_latestPixelBuffer)) {
            old = _latestPixelBuffer;
        }
        if (old != nil) {
            CFRelease(old);
        }
        if (_onFrameAvailable) {
            _onFrameAvailable();
        }
    }
    if (!CMSampleBufferDataIsReady(sampleBuffer)) {
        _eventSink(@{
                     @"event" : @"error",
                     @"errorDescription" : @"sample buffer is not ready. Skipping sample"
                     });
        return;
    }
}

- (void)close {
    [_captureSession stopRunning];
    for (AVCaptureInput *input in [_captureSession inputs]) {
        [_captureSession removeInput:input];
    }
    for (AVCaptureOutput *output in [_captureSession outputs]) {
        [_captureSession removeOutput:output];
    }
}

- (void)dealloc {
    if (_latestPixelBuffer) {
        CFRelease(_latestPixelBuffer);
    }
}

- (CVPixelBufferRef)copyPixelBuffer {
    CVPixelBufferRef pixelBuffer = _latestPixelBuffer;
    while (!OSAtomicCompareAndSwapPtrBarrier(pixelBuffer, nil, (void **)&_latestPixelBuffer)) {
        pixelBuffer = _latestPixelBuffer;
    }
    
    return pixelBuffer;
}

- (FlutterError *_Nullable)onCancelWithArguments:(id _Nullable)arguments {
    _eventSink = nil;
    return nil;
}

- (FlutterError *_Nullable)onListenWithArguments:(id _Nullable)arguments
                                       eventSink:(nonnull FlutterEventSink)events {
    _eventSink = events;
    return nil;
}
@end

@interface FLTFirebaseMlVisionPlugin ()
@property(readonly, nonatomic) NSObject<FlutterTextureRegistry> *registry;
@property(readonly, nonatomic) NSObject<FlutterBinaryMessenger> *messenger;
@property(readonly, nonatomic) FirebaseCam *camera;
@end

@implementation FLTFirebaseMlVisionPlugin {
    dispatch_queue_t _dispatchQueue;
}
+ (void)handleError:(NSError *)error result:(FlutterResult)result {
    result(getFlutterError(error));
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    FlutterMethodChannel *channel =
    [FlutterMethodChannel methodChannelWithName:@"plugins.flutter.io/firebase_mlvision"
                                binaryMessenger:[registrar messenger]];
    FLTFirebaseMlVisionPlugin *instance = [[FLTFirebaseMlVisionPlugin alloc] initWithRegistry:[registrar textures]
                                                                                    messenger:[registrar messenger]];
    [registrar addMethodCallDelegate:instance channel:channel];
}

- (instancetype)initWithRegistry:(NSObject<FlutterTextureRegistry> *)registry
                       messenger:(NSObject<FlutterBinaryMessenger> *)messenger{
    self = [super init];
    if (self) {
        if (![FIRApp appNamed:@"__FIRAPP_DEFAULT"]) {
            NSLog(@"Configuring the default Firebase app...");
            [FIRApp configure];
            NSLog(@"Configured the default Firebase app %@.", [FIRApp defaultApp].name);
            _registry = registry;
            _messenger = messenger;
        }
    }
    return self;
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    if (_dispatchQueue == nil) {
        _dispatchQueue = dispatch_queue_create("io.flutter.camera.dispatchqueue", NULL);
    }
    
    // Invoke the plugin on another dispatch queue to avoid blocking the UI.
    dispatch_async(_dispatchQueue, ^{
        [self handleMethodCallAsync:call result:result];
    });
}

- (void)handleMethodCallAsync:(FlutterMethodCall *)call result:(FlutterResult)result {
    NSString *modelName = call.arguments[@"model"];
    NSDictionary *options = call.arguments[@"options"];
    __block CVPixelBufferRef img = nil;
    if ([@"BarcodeDetector#detectInImage" isEqualToString:call.method]) {
        if (img != nil){
            FIRVisionImage *image = [self pixelBufferToVisionImage:img];
            [BarcodeDetector handleDetection:image options:options result:result];
        }
    } else if ([@"FaceDetector#processImage" isEqualToString:call.method]) {
        if (img != nil){
            FIRVisionImage *image = [self pixelBufferToVisionImage:img];
            [FaceDetector handleDetection:image options:options result:result];
        }
    } else if ([@"ImageLabeler#processImage" isEqualToString:call.method]) {
        if (img != nil){
            FIRVisionImage *image = [self pixelBufferToVisionImage:img];
            [ImageLabeler handleDetection:image options:options result:result];
        }
    } else if ([@"TextRecognizer#processImage" isEqualToString:call.method]) {
        if (img != nil){
            FIRVisionImage *image = [self pixelBufferToVisionImage:img];
            [TextRecognizer handleDetection:image options:options result:result];
        }
    } else if ([@"VisionEdgeImageLabeler#processLocalImage" isEqualToString:call.method]) {
        if (img != nil){
            FIRVisionImage *image = [self pixelBufferToVisionImage:img];
            [LocalVisionEdgeDetector handleDetection:image options:options result:result];
        }
    } else if ([@"VisionEdgeImageLabeler#processRemoteImage" isEqualToString:call.method]) {
        if (img != nil){
            FIRVisionImage *image = [self pixelBufferToVisionImage:img];
            [RemoteVisionEdgeDetector handleDetection:image options:options result:result];
        }
    } else if ([@"ModelManager#setupLocalModel" isEqualToString:call.method]) {
        [SetupLocalModel modelName:modelName result:result];
    } else if ([@"ModelManager#setupRemoteModel" isEqualToString:call.method]) {
        [SetupRemoteModel modelName:modelName result:result];
    } else if ([@"camerasAvailable" isEqualToString:call.method]){
        AVCaptureDeviceDiscoverySession *discoverySession = [AVCaptureDeviceDiscoverySession
                                                             discoverySessionWithDeviceTypes:@[ AVCaptureDeviceTypeBuiltInWideAngleCamera ]
                                                             mediaType:AVMediaTypeVideo
                                                             position:AVCaptureDevicePositionUnspecified];
        NSArray<AVCaptureDevice *> *devices = discoverySession.devices;
        NSMutableArray<NSDictionary<NSString *, NSObject *> *> *reply =
        [[NSMutableArray alloc] initWithCapacity:devices.count];
        for (AVCaptureDevice *device in devices) {
            NSString *lensFacing;
            switch ([device position]) {
                case AVCaptureDevicePositionBack:
                    lensFacing = @"back";
                    break;
                case AVCaptureDevicePositionFront:
                    lensFacing = @"front";
                    break;
                case AVCaptureDevicePositionUnspecified:
                    lensFacing = @"external";
                    break;
            }
            [reply addObject:@{
                               @"name" : [device uniqueID],
                               @"lensFacing" : lensFacing,
                               @"sensorOrientation" : @90,
                               }];
        }
        result(reply);
    } else if ([@"initialize" isEqualToString:call.method]) {
        NSString *cameraName = call.arguments[@"cameraName"];
        NSString *resolutionPreset = call.arguments[@"resolutionPreset"];
        NSError *error;
        FirebaseCam *cam = [[FirebaseCam alloc] initWithCameraName:cameraName
                                        resolutionPreset:resolutionPreset
                                           dispatchQueue:_dispatchQueue
                                                   error:&error];
        if (error) {
            result(getFlutterError(error));
        } else {
            if (_camera) {
                [_camera close];
            }
            int64_t textureId = [_registry registerTexture:cam];
            _camera = cam;
            cam.onFrameAvailable = ^{
                [_registry textureFrameAvailable:textureId];
                img = cam.latestPixelBuffer;
            };
            FlutterEventChannel *eventChannel = [FlutterEventChannel
                                                 eventChannelWithName:[NSString
                                                                       stringWithFormat:@"plugins.flutter.io/firebase_mlvision%lld",
                                                                       textureId]
                                                 binaryMessenger:_messenger];
            [eventChannel setStreamHandler:cam];
            cam.eventChannel = eventChannel;
            result(@{
                     @"textureId" : @(textureId),
                     @"previewWidth" : @(cam.previewSize.width),
                     @"previewHeight" : @(cam.previewSize.height),
                     });
            [cam start];
        }
    } else {
        result(FlutterMethodNotImplemented);
    }
}

- (FIRVisionImage *)pixelBufferToVisionImage:(CVPixelBufferRef)pixelBufferRef {
    CVPixelBufferLockBaseAddress(pixelBufferRef, kCVPixelBufferLock_ReadOnly);
    CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixelBufferRef];
    
    CIContext *temporaryContext = [CIContext contextWithOptions:nil];
    CGImageRef videoImage =
    [temporaryContext createCGImage:ciImage
                           fromRect:CGRectMake(0, 0, CVPixelBufferGetWidth(pixelBufferRef),
                                               CVPixelBufferGetHeight(pixelBufferRef))];
    
    UIImage *uiImage = [UIImage imageWithCGImage:videoImage];
    CGImageRelease(videoImage);
    CVPixelBufferUnlockBaseAddress(pixelBufferRef, kCVPixelBufferLock_ReadOnly);
    return [[FIRVisionImage alloc] initWithImage:uiImage];
}

@end
