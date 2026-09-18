import SwiftUI

/// Displays a participant's confirmed activity separately from location sharing.
struct ParticipantStatus: View {

    // MARK: - Properties

    let name: String
    let status: String
    let detail: String
    let isStale: Bool

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            LabeledContent(name, value: status)

            Text(detail)
                .font(.caption)
                .foregroundStyle(isStale ? .orange : .secondary)
        }
        .padding(.vertical, 4)
    }
}
