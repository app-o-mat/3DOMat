//
//  CombineChannelsFilter.swift
//  Stereoscope
//
//  Created by Louis Franco on 6/29/17.
//  Copyright © 2017 Lou Franco. All rights reserved.
//

import Foundation
import CoreImage

public class CombineChannelsFilterFactory: NSObject, CIFilterConstructor {

    public func filter(withName name: String) -> CIFilter? {
        switch name {
        case "CombineChannelsFilter":
            return CombineChannelsFilter()
        default:
            return nil
        }
    }

    public static func register() {
        CIFilter.registerName("CombineChannelsFilter", constructor: CombineChannelsFilterFactory(), classAttributes: [kCIAttributeFilterCategories: ["Channel Filters"]])
    }

}

public class CombineChannelsFilter: CIFilter {

    @objc dynamic var inputChannelRed: CIImage?
    @objc dynamic var inputChannelBlue: CIImage?
    @objc dynamic var inputChannelGreen: CIImage?

    let combineChannelsKernel = CIColorKernel(string:
        "kernel vec4 combineChannelKernel(__sample red, __sample green, __sample blue) {\n" +
        "   return vec4(red.r, green.g, blue.b, 1.0);\n" +
        "}"
    )

    public override var attributes: [String : Any] {
        return [
            kCIAttributeFilterName: "Combine Channels",

            "inputChannelRed": [
                kCIAttributeIdentity: 0,
                kCIAttributeClass: "CIImage",
                kCIAttributeDisplayName: "Red Channel",
                kCIAttributeType: kCIAttributeTypeImage,
            ],

            "inputChannelGreen": [
                kCIAttributeIdentity: 0,
                kCIAttributeClass: "CIImage",
                kCIAttributeDisplayName: "Green Channel",
                kCIAttributeType: kCIAttributeTypeImage,
            ],

            "inputChannelBlue": [
                kCIAttributeIdentity: 0,
                kCIAttributeClass: "CIImage",
                kCIAttributeDisplayName: "Blue Channel",
                kCIAttributeType: kCIAttributeTypeImage,
            ],
        ]
    }

    public override var outputImage: CIImage? {
        guard let inputChannelRed = inputChannelRed,
            let inputChannelGreen = inputChannelGreen,
            let inputChannelBlue = inputChannelBlue,
            let combineChannelsKernel = combineChannelsKernel
        else {
            return nil
        }

        // The final image is just where they overlap, so you can use infinite sized, generated images
        let extent = inputChannelRed.extent.intersection(inputChannelGreen.extent.intersection(inputChannelBlue.extent))
        let arguments = [
            inputChannelRed, inputChannelGreen, inputChannelBlue
        ]

        return combineChannelsKernel.apply(withExtent: extent, arguments: arguments)
    }
}
