import CloudKit
import SwiftUI
import UIKit

struct CloudInviteView: View {
    let credentials: SessionCredentials
    @State private var share: CKShare?
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let share {
                    PrivateCloudSharingController(share: share, error: $error)
                } else if let error {
                    ContentUnavailableView(
                        "초대를 준비하지 못했어요",
                        systemImage: "icloud.slash",
                        description: Text(error)
                    )
                } else {
                    ProgressView("iCloud 초대 준비 중")
                }
            }
            .navigationTitle("친구 초대")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("완료")
                    }
                }
            }
            .task {
                do { share = try await SessionClient.shared.share(credentials) } catch {
                    self.error = error.localizedDescription
                }
            }
            .alert(
                "초대를 저장하지 못했어요",
                isPresented: Binding(
                    get: { share != nil && error != nil },
                    set: { if !$0 { error = nil } }
                )
            ) {
                Button {
                    error = nil
                } label: {
                    Text("확인")
                }
            } message: {
                Text(error ?? "")
            }
        }
    }
}

private struct PrivateCloudSharingController: UIViewControllerRepresentable {
    let share: CKShare
    @Binding var error: String?

    func makeCoordinator() -> Coordinator { Coordinator(error: $error) }
    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(
            share: share,
            container: CKContainer(identifier: SessionClient.containerID)
        )
        // Do not offer "anyone with the link" access to participants' location data.
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        @Binding var error: String?
        init(error: Binding<String?>) { _error = error }
        func itemTitle(for csc: UICloudSharingController) -> String? { "다시 만나" }
        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            self.error = error.localizedDescription
        }
    }
}
