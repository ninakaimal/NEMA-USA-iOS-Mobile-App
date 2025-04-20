// CalendarView.swift
// NEMA USA
// Created by Nina on 4/16/25.

import SwiftUI

struct CalendarView: View {
    @StateObject private var loader        = EventLoader()
    @State private var selectedDate: Date? = Date()
    @State private var displayedMonth      = Calendar.current.component(.month, from: Date())
    @State private var displayedYear       = Calendar.current.component(.year,  from: Date())

    private let columns    = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let calendar   = Calendar.current
    private let monthNames: [String] = DateFormatter().monthSymbols

    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                Color.orange
                    .ignoresSafeArea(edges: .top)
                    .frame(height: 56)

                ScrollView {
                    VStack(spacing: 16) {
                        BannerView()
                        Spacer().frame(height: 16)

                        calendarHeader

                        calendarGrid
                            .padding(.horizontal)

                        Divider()

                        eventsSection
                    }
                    .padding(.bottom)
                    .background(Color(.systemBackground))
                }
            }
            .navigationBarHidden(true)
        }
    }

    // MARK: – Header

    private var calendarHeader: some View {
        VStack(spacing: 8) {
            Text("Events Calendar")
                .font(.title2)
                .foregroundColor(.primary)
                .padding(.top, 8)

            Text("Click on a specific day to see the NEMA event details")
                .font(.subheadline)
                .foregroundColor(.gray)

            HStack(spacing: 12) {
                // ← Previous month
                Button(action: goToPreviousMonth) {
                    Image(systemName: "chevron.left")
                        .font(.body)
                        .foregroundColor(.primary)
                }

                // Month picker
                Picker("Month", selection: $displayedMonth) {
                    ForEach(1...12, id: \.self) { m in
                        Text(monthNames[m - 1]).tag(m)
                    }
                }
                .pickerStyle(MenuPickerStyle())

                // Year picker
                Picker("Year", selection: $displayedYear) {
                    ForEach(2023...2026, id: \.self) { y in
                        Text("\(y)").tag(y)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .environment(\.locale, Locale(identifier: "en_US_POSIX"))

                // → Next month
                Button(action: goToNextMonth) {
                    Image(systemName: "chevron.right")
                        .font(.body)
                        .foregroundColor(.primary)
                }

                Spacer()

                Button("Today") {
                    let now = Date()
                    displayedMonth = calendar.component(.month, from: now)
                    displayedYear  = calendar.component(.year,  from: now)
                    selectedDate   = now
                }
                .foregroundColor(.white)
                .font(.footnote)
                .padding(8)
                .background(Color.orange.opacity(0.8))
                .cornerRadius(8)
            }
            .padding(.horizontal)
        }
    }

    // MARK: – Grid

    private var calendarGrid: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(["Sun","Mon","Tue","Wed","Thu","Fri","Sat"], id: \.self) { d in
                Text(d)
                    .font(.caption).bold()
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
            }

            ForEach(generateCalendarDates(), id: \.self) { date in
                DayCell(
                    date: date,
                    isInMonth: calendar.component(.month, from: date) == displayedMonth,
                    hasEvent:  !events(on: date).isEmpty,
                    isSelected: selectedDate.map { calendar.isDate(date, inSameDayAs: $0) } ?? false
                )
                .onTapGesture { selectedDate = date }
            }
        }
    }

    // MARK: – Events Section

    private var eventsSection: some View {
        Group {
            if let sel = selectedDate {
                let list = events(on: sel)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Events on \(sel.formatted(date: .long, time: .omitted))")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .padding(.top, 10)

                    if list.isEmpty {
                        Text("No events on this day.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 2)
                    } else {
                        LazyVStack(spacing: 16) {
                            ForEach(list) { ev in
                                NavigationLink(destination: EventDetailView(event: ev)) {
                                    EventCard(event: ev)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: – Month navigation

    private func goToPreviousMonth() {
        if displayedMonth > 1 {
            displayedMonth -= 1
        } else {
            displayedMonth = 12
            displayedYear  -= 1
        }
        selectedDate = nil
    }

    private func goToNextMonth() {
        if displayedMonth < 12 {
            displayedMonth += 1
        } else {
            displayedMonth = 1
            displayedYear  += 1
        }
        selectedDate = nil
    }

    // MARK: – Helpers

    private func events(on date: Date) -> [Event] {
        loader.events.filter {
            $0.date.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        }
    }

    private func generateCalendarDates() -> [Date] {
        guard let firstDayOfMonth = calendar.date(
            from: DateComponents(year: displayedYear, month: displayedMonth, day: 1)
        ) else { return [] }

        var dates: [Date] = []
        // leading days
        let weekday = calendar.component(.weekday, from: firstDayOfMonth)
        let leadingCount = (weekday - calendar.firstWeekday + 7) % 7
        // 1..<leadingCount+1 is empty when leadingCount == 0
        for i in 1..<leadingCount + 1 {
            if let d = calendar.date(byAdding: .day,
                                     value: -leadingCount + (i-1),
                                     to: firstDayOfMonth) {
                dates.append(d)
            }
        }
        // month days
        let range = calendar.range(of: .day, in: .month, for: firstDayOfMonth)!
        for day in range {
            if let d = calendar.date(from: DateComponents(year: displayedYear, month: displayedMonth, day: day)) {
                dates.append(d)
            }
        }
        // trailing days
        while dates.count % 7 != 0 {
            if let last = dates.last,
               let next = calendar.date(byAdding: .day, value: 1, to: last) {
                dates.append(next)
            }
        }

        return dates
    }
}

// MARK: – DayCell

struct DayCell: View {
    let date: Date
    let isInMonth: Bool
    let hasEvent: Bool
    let isSelected: Bool

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    var body: some View {
        VStack(spacing: 4) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isInMonth ? .primary : .gray)
                .frame(maxWidth: .infinity)

            if hasEvent {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(8)
        .background(
            Group {
                if isSelected {
                    Color.orange.opacity(0.3)
                } else if isToday {
                    Color.orange.opacity(0.15)
                } else {
                    Color.clear
                }
            }
        )
        .cornerRadius(10)
    }
}
