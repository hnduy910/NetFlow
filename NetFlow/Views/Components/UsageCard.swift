import SwiftUI

struct UsageCard: View {
    let title: LocalizedStringKey
    let icon: String
    let total: UInt64
    let received: UInt64
    let sent: UInt64

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .netFlowSectionTitle()
            Text(ByteFormat.string(total)).font(.title2.bold())
            HStack {
                Label(ByteFormat.string(received), systemImage: "arrow.down")
                Spacer()
                Label(ByteFormat.string(sent), systemImage: "arrow.up")
            }.font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .netFlowCard(cornerRadius: 18)
    }
}
