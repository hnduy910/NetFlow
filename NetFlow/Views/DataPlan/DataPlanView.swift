import SwiftUI

enum CapacityDisplayUnit: String, CaseIterable, Identifiable {
    case mb = "MB"
    case gb = "GB"
    case tb = "TB"

    var id: String { rawValue }
    var multiplier: Double {
        switch self {
        case .mb: return 1_000_000
        case .gb: return 1_000_000_000
        case .tb: return 1_000_000_000_000
        }
    }
}

struct DataPlanView: View {
    @EnvironmentObject var store: AppStore
    @State private var capacityValue = 30.0
    @State private var capacityUnit: CapacityDisplayUnit = .gb
    @FocusState private var capacityFieldFocused: Bool

    private let selectableCycles: [PlanCycleType] = [.daily, .monthly, .yearly, .custom, .unlimited]

    var body: some View {
        ScrollView {
            VStack(spacing: AppChrome.spacing) {
                cardSection("plan") {
                    Picker("cycle", selection: $store.plan.cycleType) {
                        ForEach(selectableCycles) { cycle in
                            Text(LocalizedStringKey(cycle.rawValue)).tag(cycle)
                        }
                    }
                    .pickerStyle(.menu)

                    if !store.plan.isUnlimited {
                        HStack {
                            TextField("capacity", value: $capacityValue, format: .number)
                                .keyboardType(.decimalPad)
                                .focused($capacityFieldFocused)
                                .submitLabel(.done)

                            Picker("unit", selection: $capacityUnit) {
                                ForEach(CapacityDisplayUnit.allCases) { unit in
                                    Text(unit.rawValue).tag(unit)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }

                        Toggle("rollover", isOn: $store.plan.rolloverEnabled)

                        if store.plan.cycleType == .monthly {
                            Stepper(value: $store.plan.monthlyResetDay, in: 1...28) {
                                Text("\(AppLocalization.string("reset_day", locale: store.settings.appLanguage.locale)) \(store.plan.monthlyResetDay)")
                            }
                        }
                        if store.plan.cycleType == .yearly {
                            Stepper(value: $store.plan.yearlyResetMonth, in: 1...12) {
                                Text("\(AppLocalization.string("reset_month", locale: store.settings.appLanguage.locale)) \(store.plan.yearlyResetMonth)")
                            }
                            Stepper(value: $store.plan.yearlyResetDay, in: 1...28) {
                                Text("\(AppLocalization.string("reset_day", locale: store.settings.appLanguage.locale)) \(store.plan.yearlyResetDay)")
                            }
                        }
                        if store.plan.cycleType == .custom {
                            Stepper(value: $store.plan.customDays, in: 1...365) {
                                Text("\(AppLocalization.string("custom_days", locale: store.settings.appLanguage.locale)) \(store.plan.customDays)")
                            }
                        }
                    }
                }

                cardSection("alerts") {
                    ForEach($store.plan.alertThresholds) { $threshold in
                        Toggle(isOn: $threshold.enabled) {
                            Text(
                                threshold.kind == .percentUsed
                                ? "\(Int(threshold.value))%"
                                : ByteFormat.string(UInt64(max(threshold.value, 0)))
                            )
                        }
                    }

                    Button("add_percent_alert") {
                        capacityFieldFocused = false
                        store.plan.alertThresholds.append(AlertThreshold(kind: .percentUsed, value: 90))
                    }
                    Button("add_remaining_alert") {
                        capacityFieldFocused = false
                        store.plan.alertThresholds.append(AlertThreshold(kind: .remainingBytes, value: 1_000_000_000))
                    }
                }
            }
            .padding(AppChrome.pagePadding)
        }
        .netFlowPageBackground()
        .navigationTitle("data_plan")
        .scrollDismissesKeyboard(.interactively)
        .contentShape(Rectangle())
        .onTapGesture { capacityFieldFocused = false }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("done") { capacityFieldFocused = false }
            }
        }
        .onAppear {
            loadCapacityEditor()
        }
        .onChange(of: capacityValue) { _ in saveCapacityEditor() }
        .onChange(of: capacityUnit) { _ in saveCapacityEditor() }
        .onChange(of: store.plan) { _ in store.save() }
    }

    private func cardSection<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .netFlowSectionTitle()
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .netFlowCard(cornerRadius: 18)
    }

    private func loadCapacityEditor() {
        capacityUnit = CapacityDisplayUnit(rawValue: store.plan.capacityDisplayUnitRaw ?? "GB") ?? .gb
        capacityValue = Double(store.plan.capacityBytes) / capacityUnit.multiplier
    }

    private func saveCapacityEditor() {
        store.plan.capacityDisplayUnitRaw = capacityUnit.rawValue
        let bytes = max(capacityValue, 0) * capacityUnit.multiplier
        store.plan.capacityBytes = UInt64(min(bytes, Double(UInt64.max)))
        store.save()
    }
}
