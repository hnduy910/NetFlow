import SwiftUI

struct SystemCapabilitiesView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(spacing: AppChrome.spacing) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(LocalizedStringKey(store.capabilities.snapshot.environmentTitleKey), systemImage: "iphone.gen3.radiowaves.left.and.right")
                        .font(.title3.bold())
                    Text(LocalizedStringKey(store.capabilities.snapshot.environmentDetailKey))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if store.capabilities.snapshot.lastChecked != .distantPast {
                        Text(store.capabilities.snapshot.lastChecked, style: .time)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .netFlowCard(cornerRadius: 18)

                VStack(alignment: .leading, spacing: 14) {
                    Text("system_capabilities")
                        .netFlowSectionTitle()

                    ForEach(store.capabilities.snapshot.items) { item in
                        HStack(spacing: 14) {
                            Image(systemName: item.systemImage)
                                .frame(width: 28)
                                .foregroundStyle(color(for: item.state))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(LocalizedStringKey(item.titleKey))
                                Text(LocalizedStringKey(item.detailKey))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Label(stateTitle(item.state), systemImage: stateImage(item.state))
                                .labelStyle(.iconOnly)
                                .foregroundStyle(color(for: item.state))
                        }
                        .accessibilityElement(children: .combine)
                        .padding(.vertical, 4)

                        if item.id != store.capabilities.snapshot.items.last?.id {
                            Divider()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .netFlowCard(cornerRadius: 18)

                Text("capability_signing_note")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .netFlowCard(cornerRadius: 18)
            }
            .padding(AppChrome.pagePadding)
        }
        .netFlowPageBackground()
        .navigationTitle("system_information")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task {
                        await store.refreshContext()
                        await store.capabilities.refresh(context: store.networkContext)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("refresh")
            }
        }
        .task { await store.capabilities.refresh(context: store.networkContext) }
    }

    private func stateTitle(_ state: CapabilityState) -> LocalizedStringKey {
        switch state {
        case .available: return "cap_available"
        case .limited: return "cap_limited"
        case .unavailable: return "cap_unavailable"
        case .unknown: return "cap_unknown"
        }
    }

    private func stateImage(_ state: CapabilityState) -> String {
        switch state {
        case .available: return "checkmark.circle.fill"
        case .limited: return "exclamationmark.circle.fill"
        case .unavailable: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    private func color(for state: CapabilityState) -> Color {
        switch state {
        case .available: return .green
        case .limited: return .orange
        case .unavailable: return .red
        case .unknown: return .secondary
        }
    }
}
