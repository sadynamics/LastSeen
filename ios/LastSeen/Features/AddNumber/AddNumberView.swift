//
//  AddNumberView.swift
//

import SwiftUI

struct AddNumberView: View {
    @Environment(TrackingService.self) private var tracking
    @Environment(\.dismiss) private var dismiss
    @State private var country: Country = .current
    @State private var number: String = ""
    @State private var displayName: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showCountryPicker = false

    private var canSubmit: Bool {
        let digits = number.filter(\.isNumber)
        return !isSubmitting && digits.count >= 6
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Track a phone number")
                                .font(Theme.Font.title)
                                .foregroundStyle(Theme.Color.primaryText)
                            Text("Enter the WhatsApp number you want to monitor. We'll notify you when activity changes.")
                                .font(Theme.Font.callout)
                                .foregroundStyle(Theme.Color.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, Theme.Spacing.sm)

                        Card {
                            VStack(spacing: Theme.Spacing.md) {
                                Button { showCountryPicker = true } label: {
                                    HStack(spacing: Theme.Spacing.md) {
                                        Text(country.flag)
                                            .font(.title)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(country.name)
                                                .font(Theme.Font.callout.weight(.medium))
                                                .foregroundStyle(Theme.Color.primaryText)
                                            Text("+\(country.dialCode)")
                                                .font(Theme.Font.caption)
                                                .foregroundStyle(Theme.Color.secondaryText)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(Theme.Color.tertiaryText)
                                    }
                                }
                                .buttonStyle(.plain)

                                Divider().background(Theme.Color.separator)

                                HStack(spacing: 10) {
                                    Text("+\(country.dialCode)")
                                        .font(Theme.Font.body.weight(.medium))
                                        .foregroundStyle(Theme.Color.primaryText)
                                        .monospacedDigit()
                                    TextField("", text: $number, prompt: Text("Phone number")
                                        .foregroundColor(Theme.Color.tertiaryText))
                                        .keyboardType(.phonePad)
                                        .font(Theme.Font.body)
                                        .foregroundStyle(Theme.Color.primaryText)
                                        .autocorrectionDisabled()
                                        .textContentType(.telephoneNumber)
                                }

                                Divider().background(Theme.Color.separator)

                                TextField("", text: $displayName, prompt: Text("Nickname (optional)")
                                    .foregroundColor(Theme.Color.tertiaryText))
                                    .font(Theme.Font.body)
                                    .foregroundStyle(Theme.Color.primaryText)
                                    .textContentType(.name)
                            }
                        }

                        if let errorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                Text(errorMessage)
                            }
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.danger)
                        }

                        Spacer().frame(height: Theme.Spacing.sm)

                        PrimaryButton(title: "Start tracking", systemImage: "waveform.path.ecg",
                                      isLoading: isSubmitting,
                                      isDisabled: !canSubmit) {
                            Task { await submit() }
                        }
                    }
                    .padding(Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.xxl)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(Theme.Font.callout.weight(.medium))
                        .foregroundStyle(Theme.Color.secondaryText)
                }
            }
            .sheet(isPresented: $showCountryPicker) {
                CountryPicker(selected: $country)
            }
            .trackScreen("add_number", className: "AddNumberView")
        }
    }

    private func submit() async {
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        let composed = "+\(country.dialCode)\(number.filter(\.isNumber))"
        do {
            _ = try await tracking.add(phone: composed,
                                        defaultCountry: country.iso,
                                        displayName: displayName.isEmpty ? nil : displayName)
            dismiss()
        } catch APIError.subscriptionRequired {
            errorMessage = "You need a subscription to track more numbers."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct Country: Hashable, Identifiable, Sendable {
    let iso: String       // e.g. "US"
    let name: String
    let dialCode: String  // e.g. "1"

    var id: String { iso }
    var flag: String {
        iso.unicodeScalars
            .compactMap { Unicode.Scalar(127_397 + $0.value) }
            .map { String($0) }
            .joined()
    }

    static var current: Country {
        let region = Locale.current.region?.identifier ?? "US"
        return all.first { $0.iso == region } ?? all.first { $0.iso == "US" }!
    }

    static let all: [Country] = [
        .init(iso: "US", name: "United States", dialCode: "1"),
        .init(iso: "GB", name: "United Kingdom", dialCode: "44"),
        .init(iso: "TR", name: "Türkiye", dialCode: "90"),
        .init(iso: "DE", name: "Germany", dialCode: "49"),
        .init(iso: "FR", name: "France", dialCode: "33"),
        .init(iso: "ES", name: "Spain", dialCode: "34"),
        .init(iso: "IT", name: "Italy", dialCode: "39"),
        .init(iso: "NL", name: "Netherlands", dialCode: "31"),
        .init(iso: "PL", name: "Poland", dialCode: "48"),
        .init(iso: "RU", name: "Russia", dialCode: "7"),
        .init(iso: "BR", name: "Brazil", dialCode: "55"),
        .init(iso: "MX", name: "Mexico", dialCode: "52"),
        .init(iso: "AR", name: "Argentina", dialCode: "54"),
        .init(iso: "IN", name: "India", dialCode: "91"),
        .init(iso: "PK", name: "Pakistan", dialCode: "92"),
        .init(iso: "ID", name: "Indonesia", dialCode: "62"),
        .init(iso: "SA", name: "Saudi Arabia", dialCode: "966"),
        .init(iso: "AE", name: "UAE", dialCode: "971"),
        .init(iso: "EG", name: "Egypt", dialCode: "20"),
        .init(iso: "NG", name: "Nigeria", dialCode: "234"),
        .init(iso: "ZA", name: "South Africa", dialCode: "27"),
        .init(iso: "AU", name: "Australia", dialCode: "61"),
        .init(iso: "JP", name: "Japan", dialCode: "81"),
        .init(iso: "KR", name: "South Korea", dialCode: "82"),
        .init(iso: "CN", name: "China", dialCode: "86"),
        .init(iso: "PH", name: "Philippines", dialCode: "63"),
        .init(iso: "MY", name: "Malaysia", dialCode: "60"),
        .init(iso: "SG", name: "Singapore", dialCode: "65"),
        .init(iso: "TH", name: "Thailand", dialCode: "66"),
        .init(iso: "VN", name: "Vietnam", dialCode: "84"),
        .init(iso: "CA", name: "Canada", dialCode: "1")
    ].sorted { $0.name < $1.name }
}

struct CountryPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selected: Country
    @State private var search = ""

    private var filtered: [Country] {
        guard !search.isEmpty else { return Country.all }
        return Country.all.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.dialCode.contains(search)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                List {
                    ForEach(filtered) { c in
                        Button {
                            selected = c
                            dismiss()
                        } label: {
                            HStack(spacing: Theme.Spacing.md) {
                                Text(c.flag).font(.title2)
                                Text(c.name)
                                    .font(Theme.Font.callout)
                                    .foregroundStyle(Theme.Color.primaryText)
                                Spacer()
                                Text("+\(c.dialCode)")
                                    .font(Theme.Font.callout.weight(.medium))
                                    .foregroundStyle(Theme.Color.tertiaryText)
                                    .monospacedDigit()
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Color.white.opacity(0.04))
                        .listRowSeparatorTint(Theme.Color.separator)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .searchable(text: $search, prompt: "Search country")
            .navigationTitle("Country")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
