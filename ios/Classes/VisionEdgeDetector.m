#import "FirebaseMlVisionPlugin.h"

@import FirebaseMLCommon;

@implementation VisionEdgeDetector
static FIRVisionImageLabeler *labeler;

+ (void)handleDetection:(FIRVisionImage *)image options:(NSDictionary *)options result:(FlutterResult)result {
    NSString *manifestPath = [NSBundle.mainBundle pathForResource:@"manifest"
        ofType:@"json"
        inDirectory:options[@"dataset"]];
    FIRLocalModel *localModel = [[FIRLocalModel alloc] initWithName:options[@"dataset"]
        path:manifestPath];
    [[FIRModelManager modelManager] registerLocalModel:localModel];
    FIRVisionOnDeviceAutoMLImageLabelerOptions *labelerOptions =
    [[FIRVisionOnDeviceAutoMLImageLabelerOptions alloc]
     initWithRemoteModelName: nil
     localModelName:options[@"dataset"]];
    labelerOptions.confidenceThreshold = 0.5;
    FIRVisionImageLabeler *labeler =
    [[FIRVision vision] onDeviceAutoMLImageLabelerWithOptions:labelerOptions];
    [labeler
     processImage:image
     completion:^(NSArray<FIRVisionImageLabel *> *_Nullable labels, NSError *_Nullable error) {
         if (error) {
             [FLTFirebaseMlVisionPlugin handleError:error result:result];
             return;
         } else if (!labels) {
             result(@[]);
         }
         
         NSMutableArray *labelData = [NSMutableArray array];
         for (FIRVisionImageLabel *label in labels) {
             NSDictionary *data = @{
                                    @"confidence" : label.confidence,
                                    @"entityID" : label.entityID,
                                    @"text" : label.text,
                                    };
             [labelData addObject:data];
         }
         
         result(labelData);
     }];
}

+ (FIRVisionOnDeviceAutoMLImageLabelerOptions *)parseOptions:(NSDictionary *)optionsData {
    NSNumber *conf = optionsData[@"confidenceThreshold"];
    
    FIRVisionOnDeviceAutoMLImageLabelerOptions *options = [FIRVisionOnDeviceAutoMLImageLabelerOptions new];
    options.confidenceThreshold = [conf floatValue];
    
    return options;
}

@end
