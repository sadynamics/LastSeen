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
                Theme.Color.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        Text("Track a phone number")
                            .font(.title2.bold())
                            .foregroundStyle(Theme.Color.primaryText)
                        Text("Enter the WhatsApp number you want to monitor. We'll notify you when it comes online.")
                            .font(.callout)
                            .foregroundStyle(Theme.Color.secondaryText)

                        Card {
                            VStack(spacing: Theme.Spacing.md) {
                                Button { showCountryPicker = true } label: {
                                    HStack {
                                        Text(country.flag)
                                            .font(.title2)
                                        VStack(alignment: .leading) {
                                            Text(country.name)
                                                .font(.callout)
                                                .foregroundStyle(Theme.Color.primaryText)
                                            Text("+\(country.dialCode)")
                                                .font(.caption)
                                                .foregroundStyle(Theme.Color.secondaryText)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.down")
                                            .foregroundStyle(Theme.Color.tertiaryText)
                                    }
                                }
                                .buttonStyle(.plain)

                                Divider().background(Theme.Color.surfaceElevated)

                                HStack {
                                    Text("+\(country.dialCode)")
                                        .foregroundStyle(Theme.Color.primaryText)
                                        .monospacedDigit()
                                    TextField("Phone number", text: $number)
                                        .keyboardType(.phonePad)
                                        .foregroundStyle(Theme.Color.primaryText)
                                        .autocorrectionDisabled()
                                        .textContentType(.telephoneNumber)
                                }

                                Divider().background(Theme.Color.surfaceElevated)

                                TextField("Nickname (optional)", text: $displayName)
                                    .foregroundStyle(Theme.Color.primaryText)
                                    .textContentType(.name)
                            }
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(Theme.Color.danger)
                        }

                        Spacer().frame(height: Theme.Spacing.md)

                        PrimaryButton(title: "Start tracking", systemImage: "eye.fill",
                                      isLoading: isSubmitting,
                                      isDisabled: !canSubmit) {
                            Task { await submit() }
                        }
                    }
                    .padding(Theme.Spacing.lg)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.Color.secondaryText)
                }
            }
            .sheet(isPresented: $showCountryPicker) {
                CountryPicker(selected: $country)
            }
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
            List {
                ForEach(filtered) { c in
                    Button {
                        selected = c
                        dismiss()
                    } label: {
                        HStack {
                            Text(c.flag).font(.title3)
                            Text(c.name).foregroundStyle(Theme.Color.primaryText)
                            Spacer()
                            Text("+\(c.dialCode)")
                                .foregroundStyle(Theme.Color.tertiaryText)
                                .monospacedDigit()
                        }
                    }
                    .listRowBackground(Theme.Color.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.background)
            .searchable(text: $search, prompt: "Search country")
            .navigationTitle("Country")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
