import Foundation
import CoreHID

/// Checks only whether this signing context can construct a virtual HID device.
/// A standard mouse descriptor avoids conflating permission with a novel trackpad report.
/// No activation or input reports: the probe never moves or clicks the pointer.
@main struct VirtualHIDProbe {
    static func main() async {
        let descriptor = Data([
            0x05, 0x01, 0x09, 0x02, 0xa1, 0x01, 0x09, 0x01, 0xa1, 0x00,
            0x05, 0x09, 0x19, 0x01, 0x29, 0x03, 0x15, 0x00, 0x25, 0x01,
            0x95, 0x03, 0x75, 0x01, 0x81, 0x02, 0x95, 0x01, 0x75, 0x05,
            0x81, 0x03, 0x05, 0x01, 0x09, 0x30, 0x09, 0x31, 0x15, 0x81,
            0x25, 0x7f, 0x75, 0x08, 0x95, 0x02, 0x81, 0x06, 0xc0, 0xc0
        ])
        // Reserved test identity; never impersonate Apple hardware.
        let properties = HIDVirtualDevice.Properties(descriptor: descriptor, vendorID: 0xffff,
            productID: 1, product: "PhoneTouchpad permission probe", manufacturer: "PhoneTouchpad")
        guard let device = HIDVirtualDevice(properties: properties) else {
            print("Virtual HID construction unavailable for this signing context.")
            print("This probe does not establish trackpad or native multi-touch compatibility.")
            exit(2)
        }
        withExtendedLifetime(device) {
            print("Virtual HID object constructed; no reports dispatched.")
            print("Native trackpad recognition remains unverified.")
        }
    }
}
