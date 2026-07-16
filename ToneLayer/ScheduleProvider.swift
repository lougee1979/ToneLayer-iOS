// Copyright (c) 2026 Alden Lougee. All rights reserved.
// Proprietary and confidential. Unauthorized copying, modification,
// distribution, or derivative use is prohibited.

//
//  ScheduleProvider.swift
//  ToneLayer
//
//  Read-only calendar + location awareness for TonalInsight. Builds a short
//  agenda string (with travel-time estimates) describing the rest of the
//  user's day, and schedules local reminder notifications for upcoming
//  events so the user gets nudged ahead of time, not just when they open
//  the app.
//

import Foundation
import EventKit
import CoreLocation
import MapKit
import UserNotifications
import Combine

@MainActor
final class ScheduleProvider: NSObject, ObservableObject {

    /// Plain-text summary of the rest of today's schedule, suitable for
    /// dropping straight into TonalInsight's system prompt.
    @Published var agendaText = "No schedule information yet."

    private let eventStore = EKEventStore()
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?

    override init() {
        super.init()
        locationManager.delegate = self
    }

    /// Requests calendar + location permission (if needed), then rebuilds
    /// the agenda and (re)schedules reminder notifications for the rest of
    /// the day. Safe to call repeatedly, e.g. each time the app becomes active.
    func refresh() async {
        let hasCalendarAccess = await requestCalendarAccess()
        guard hasCalendarAccess else {
            agendaText = "Calendar access not granted."
            return
        }

        requestLocationAccess()

        let events = upcomingEventsToday()
        agendaText = await buildAgendaText(for: events)
        scheduleReminders(for: events)
    }

    // MARK: - Calendar

    private func requestCalendarAccess() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                eventStore.requestFullAccessToEvents { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    /// All events starting from now through the end of today, soonest first.
    private func upcomingEventsToday() -> [EKEvent] {
        let calendar = Calendar.current
        let now = Date()
        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now

        let predicate = eventStore.predicateForEvents(withStart: now, end: endOfDay, calendars: nil)
        return eventStore.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
    }

    // MARK: - Location

    private func requestLocationAccess() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        default:
            break
        }
    }

    // MARK: - Agenda text

    private func buildAgendaText(for events: [EKEvent]) async -> String {
        guard !events.isEmpty else {
            return "Nothing else scheduled for today."
        }

        let formatter = DateFormatter()
        formatter.timeStyle = .short

        var lines: [String] = []
        for event in events {
            let title = event.title ?? "Untitled event"
            var line = "\(formatter.string(from: event.startDate)) \u{2014} \(title)"

            if let location = event.location, !location.isEmpty {
                line += " at \(location)"
                if let minutes = await travelMinutes(to: location) {
                    line += " (about \(minutes) min away from your current location)"
                }
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    /// Driving travel time, in minutes, from the user's last known location
    /// to the given address. Returns nil if location isn't available yet or
    /// the address can't be resolved.
    private func travelMinutes(to address: String) async -> Int? {
        guard let currentLocation else { return nil }

        guard let destination = try? await CLGeocoder().geocodeAddressString(address).first?.location
        else { return nil }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: currentLocation.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate))
        request.transportType = .automobile

        guard let route = try? await MKDirections(request: request).calculate().routes.first
        else { return nil }

        return Int((route.expectedTravelTime / 60).rounded())
    }

    // MARK: - Reminder notifications

    /// Schedules a few reminder notifications ahead of each remaining event
    /// today (30 min before, 10 min before, and at start time), so the user
    /// gets nudged about obligations even if they haven't opened the app.
    private func scheduleReminders(for events: [EKEvent]) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        center.removeAllPendingNotificationRequests()

        let offsets: [(seconds: TimeInterval, label: String)] = [
            (-30 * 60, "starts in 30 minutes"),
            (-10 * 60, "starts in 10 minutes"),
            (0, "is starting now")
        ]

        for event in events {
            guard let title = event.title, let identifier = event.eventIdentifier else { continue }

            for offset in offsets {
                let fireDate = event.startDate.addingTimeInterval(offset.seconds)
                guard fireDate > Date() else { continue }

                let content = UNMutableNotificationContent()
                content.title = "ToneLayer reminder"
                content.body = "\(title) \(offset.label)."
                content.sound = .default

                let components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second], from: fireDate
                )
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "\(identifier)-\(Int(offset.seconds))",
                    content: content,
                    trigger: trigger
                )
                center.add(request)
            }
        }
    }
}

extension ScheduleProvider: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            requestLocationAccess()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            currentLocation = locations.last
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Location is best-effort — agenda text just omits travel times.
    }
}
