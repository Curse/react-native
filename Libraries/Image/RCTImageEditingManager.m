/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "RCTImageEditingManager.h"

#import <UIKit/UIKit.h>

#import "RCTConvert.h"
#import "RCTLog.h"
#import "RCTUtils.h"
#import "RCTImageUtils.h"

#import "RCTImageStoreManager.h"
#import "RCTImageLoader.h"

@implementation RCTImageEditingManager

RCT_EXPORT_MODULE()

@synthesize bridge = _bridge;

/**
 * Crops an image and adds the result to the image store.
 *
 * @param imageRequest An image URL
 * @param cropData Dictionary with `offset`, `size` and `displaySize`.
 *        `offset` and `size` are relative to the full-resolution image size.
 *        `displaySize` is an optimization - if specified, the image will
 *        be scaled down to `displaySize` rather than `size`.
 *        All units are in px (not points).
 */
RCT_EXPORT_METHOD(cropImage:(NSURLRequest *)imageRequest
                  cropData:(NSDictionary *)cropData
                  successCallback:(RCTResponseSenderBlock)successCallback
                  errorCallback:(RCTResponseErrorBlock)errorCallback)
{
  CGRect rect = {
    [RCTConvert CGPoint:cropData[@"offset"]],
    [RCTConvert CGSize:cropData[@"size"]]
  };

  __weak RCTImageEditingManager *weakSelf = self;
  [_bridge.imageLoader loadImageWithURLRequest:imageRequest callback:^(NSError *error, UIImage *image) {
    __strong RCTImageEditingManager *strongSelf = weakSelf;
    if (error || !strongSelf) {
      if (errorCallback) {
        errorCallback(error);
      }
      return;
    }

    // Crop image
    CGSize targetSize = rect.size;
    CGRect targetRect = {{-rect.origin.x, -rect.origin.y}, image.size};
    CGAffineTransform transform = RCTTransformFromTargetRect(image.size, targetRect);
    UIImage *croppedImage = RCTTransformImage(image, targetSize, image.scale, transform);

    // Scale image
    if (cropData[@"displaySize"]) {
      targetSize = [RCTConvert CGSize:cropData[@"displaySize"]]; // in pixels
      RCTResizeMode resizeMode = [RCTConvert RCTResizeMode:cropData[@"resizeMode"] ?: @"contain"];
      targetRect = RCTTargetRect(croppedImage.size, targetSize, 1, resizeMode);
      transform = RCTTransformFromTargetRect(croppedImage.size, targetRect);
      croppedImage = RCTTransformImage(croppedImage, targetSize, image.scale, transform);
    }

    // Store image
    if (!strongSelf->_bridge || !strongSelf->_bridge.imageStoreManager) {
      return;
    }
    [strongSelf->_bridge.imageStoreManager storeImage:croppedImage withBlock:^(NSString *croppedImageTag) {
      if (!croppedImageTag) {
        NSString *errorMessage = @"Error storing cropped image in RCTImageStoreManager";
        RCTLogWarn(@"%@", errorMessage);
        if (errorCallback) {
          errorCallback(RCTErrorWithMessage(errorMessage));
        }
        return;
      }
      if (successCallback) {
        successCallback(@[croppedImageTag]);
      }
    }];
  }];
}

@end
