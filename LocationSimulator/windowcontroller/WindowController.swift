//
//  WindowController.swift
//  LocationSimulator
//
//  Created by David Klopp on 18.08.19.
//  Copyright © 2019 David Klopp. All rights reserved.
//

import Foundation
import AppKit
import MapKit

/// The main window controller instance which hosts the map view and the toolbar.
class WindowController: NSWindowController {
    /// Enable, disable autofocus current location.
    @IBOutlet weak var currentLocationButton: NSButton!

    /// Change the current move speed.
    @IBOutlet weak var typeSegmented: NSSegmentedControl!

    /// Change the current move speed using the touchbar.
    @IBOutlet var typeSegmentedTouchbar: NSSegmentedControl!

    /// Search for a location inside the map.
    @IBOutlet weak var searchField: LocationSearchField!

    /// Change the current device.
    @IBOutlet weak var devicesPopup: NSPopUpButton!

    /// Search completer to find a location based on a string.
    public var searchCompleter: MKLocalSearchCompleter!

    /// UDIDs of all currently connected devices.
    public var deviceUDIDs: [String]!

    /// Cache to store the last known location for each device as long as it is connected
    var lastKnownLocationCache: [String: CLLocationCoordinate2D] = [:]

    /// Internal reference to a NotificationCenterObserver.
    private var autofocusObserver: Any?

    // MARK: - Window lifecycle

    override func windowDidLoad() {
        super.windowDidLoad()

        // save the UDIDs of all connected devices
        self.deviceUDIDs = []

        if Device.startGeneratingDeviceNotifications() {
            NotificationCenter.default.addObserver(self, selector: #selector(self.deviceConnected),
                                                   name: .DeviceConnected, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(self.devicePaired),
                                                   name: .DevicePaired, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(self.deviceDisconnected),
                                                   name: .DeviceDisconnected, object: nil)
        }

        // setup the location searchfield
        searchField.tableViewDelegate = self

        // only search for locations
        searchCompleter = MKLocalSearchCompleter()
        searchCompleter.filterType = .locationsOnly

        // listen to current location changes
        self.autofocusObserver = NotificationCenter.default.addObserver(forName: .AutoFoucusCurrentLocationChanged,
                                                                        object: nil, queue: .main) { (notification) in
            if let isOn = notification.object as? Bool, isOn == true {
                self.currentLocationButton.state = .on
            } else {
                self.currentLocationButton.state = .off
            }
        }
    }

    deinit {
        // stop generating update notifications (0 != 1 can never occur)
        Device.stopGeneratingDeviceNotifications()

        // remove all notifications
        /*NotificationCenter.default.removeObserver(self, name: .DeviceConnected, object: nil)
        NotificationCenter.default.removeObserver(self, name: .DevicePaired, object: nil)
        NotificationCenter.default.removeObserver(self, name: .DeviceDisconnected, object: nil)*/
        if let observer = self.autofocusObserver {
            NotificationCenter.default.removeObserver(observer)
            self.autofocusObserver = nil
        }
    }

    // MARK: - Interface Builder callbacks

    /// Toggle the autofocus feature on or off.
    /// - Parameter sender: the button which triggered the action
    @IBAction func currentLocationClicked(_ sender: NSButton) {
        guard let viewController = self.contentViewController as? MapViewController else { return }

        if viewController.currentLocationMarker == nil {
            sender.state = .off
        } else {
            viewController.autoFocusCurrentLocation = (sender.state == .on)
        }
    }

    /// Change the move speed to walk / cycle / drive based on the selected segment. Futhermore update the tool- and
    /// touchbar to represent the current status.
    /// - Parameter sender: the segmented control instance inside the tool- or touchbar.
    @IBAction func typeSegmentChanged(_ sender: NSSegmentedControl) {
        guard let viewController = self.contentViewController as? MapViewController else { return }

        // Update the toolbar state if the touchbar was clicked.
        if self.typeSegmented.selectedSegment != sender.selectedSegment {
            self.typeSegmented.selectedSegment = sender.selectedSegment
        }

        // Update the touchbar state if the toolbar was clicked.
        if self.typeSegmentedTouchbar.selectedSegment != sender.selectedSegment {
            self.typeSegmentedTouchbar.selectedSegment = sender.selectedSegment
        }

        viewController.spoofer?.moveType = MoveType(rawValue: sender.selectedSegment)!
    }

    /// Stop spoofing the current location.
    /// - Parameter sender: the button which triggered the action
    @IBAction func resetClicked(_ sender: Any) {
        guard let viewController = contentViewController as? MapViewController else { return }
        viewController.spoofer?.resetLocation()
    }

    /// Change the currently select device to the new devive choosen from the list.
    /// - Parameter sender: the button which triggered the action
    @IBAction func deviceSelected(_ sender: NSPopUpButton) {
        // Disable all menubar items which only work if a device is connected.
        let items: [NavigationMenubarItem] = [.setLocation, .toggleAutomove, .moveUp, .moveDown, .moveCounterclockwise,
                                              .moveClockwise, .recentLocation]
        items.forEach { item in item.disable() }

        guard let viewController = contentViewController as? MapViewController else { return }

        let index: Int = sender.indexOfSelectedItem
        let udid: String = self.deviceUDIDs[index]

        // cleanup the UI if a previous device was selected
        if let spoofer = viewController.spoofer {
            // if the selection did not change do nothing
            if spoofer.device.UDID == udid {
                NavigationMenubarItem.setLocation.enable()
                NavigationMenubarItem.recentLocation.enable()
                return
            }
            // reset the timer and cancel all delegate updates
            spoofer.moveState = .manual
            spoofer.delegate = nil

            // store the last known location for the last device
            self.lastKnownLocationCache[spoofer.device.UDID] = spoofer.currentLocation

            // explicitly force the UI to reset
            viewController.willChangeLocation(spoofer: spoofer, toCoordinate: nil)
            viewController.didChangeLocation(spoofer: spoofer, toCoordinate: nil)
        }

        // load the new device
        if viewController.loadDevice(udid) {
            // set the correct walking speed based on the current selection
            viewController.spoofer?.moveType = MoveType(rawValue: self.typeSegmented.selectedSegment) ?? .walk

            // Check if we already have a known location for this device, if so load it.
            // TODO: This is not an optimal solution, because we do not keep information about the current route or
            // automove state. We could fix this by serializing the spoofer instance... but this is low priority.
            if let spoofer = viewController.spoofer, let coordinate = self.lastKnownLocationCache[udid] {
                spoofer.currentLocation = coordinate
                viewController.willChangeLocation(spoofer: spoofer, toCoordinate: coordinate)
                viewController.didChangeLocation(spoofer: spoofer, toCoordinate: coordinate)
                // enable the move menubar items
                spoofer.moveState = .manual
            }

            // Make sure to enable the 'Set Location' menubar item if a device is connected.
            NavigationMenubarItem.setLocation.enable()
            NavigationMenubarItem.recentLocation.enable()
        }
    }
}
