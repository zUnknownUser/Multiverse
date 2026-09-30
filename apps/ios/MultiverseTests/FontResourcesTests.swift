import CoreText
import Foundation
import Testing
import UIKit
@testable import Multiverse

@MainActor
struct FontResourcesTests {
    @Test func appAndWidgetsBundleEveryRegisteredFontAndItsLicense() throws {
        let plugins = try #require(Bundle.main.builtInPlugInsURL)
        let widget = try #require(Bundle(url: plugins.appendingPathComponent("MultiverseWidgets.appex")))
        for bundle in [Bundle.main, widget] {
            let filenames = try #require(bundle.object(forInfoDictionaryKey: "UIAppFonts") as? [String])
            #expect(!filenames.isEmpty)
            for filename in filenames {
                let url = bundle.bundleURL.appendingPathComponent(filename)
                let descriptors = try #require(CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])
                #expect(!descriptors.isEmpty)
            }
            #expect(bundle.url(forResource: "Archivo-OFL", withExtension: "txt") != nil)
        }
    }

    @Test func archivoRegistersWithUIKitAndProvidesTheDesignSystemsVariationAxes() throws {
        let font = try #require(UIFont(name: "Archivo", size: 16) ?? UIFont(name: "Archivo-Regular", size: 16))
        #expect(font.familyName == "Archivo")
        let ctFont = CTFontCreateWithName(font.fontName as CFString, 16, nil)
        let axes = try #require(CTFontCopyVariationAxes(ctFont) as? [[String: Any]])
        let tags = Set(axes.compactMap { ($0[kCTFontVariationAxisIdentifierKey as String] as? NSNumber)?.uint32Value })
        #expect(tags.contains(0x77676874)) // wght
        #expect(tags.contains(0x77647468)) // wdth
    }
}
