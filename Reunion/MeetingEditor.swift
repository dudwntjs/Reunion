import SwiftUI

struct MeetingEditor: View {
    @Environment(ReunionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var proposedPlace: PlaceResult?
    @State private var draft = Meeting()

    var body: some View {
        NavigationStack {
            Form {
                Section("함께 보기에서 선택한 장소") {
                    Label(draft.place.isEmpty ? "먼저 지도에서 장소를 선택해 주세요" : draft.place, systemImage: "mappin")
                }
                Section("다시 만날 약속") {
                    DatePicker("약속 시간", selection: $draft.target, in: Date()...Date().addingTimeInterval(86400))
                    TextField("상세 만남 위치 (선택)", text: $draft.note)
                }
            }
            .navigationTitle("약속 정하기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("취소")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        draft.mode = .walk
                        draft.bufferMinutes = 0
                        store.updateMeeting(draft)
                        store.mapFocusRequest += 1
                        if store.freshLocation != nil && !MapConfiguration.restKey.isEmpty {
                            Task { await store.fetchRoute() }
                        }
                        dismiss()
                    } label: {
                        Text("저장")
                    }
                    .disabled(
                        draft.place.isEmpty || !draft.coordinate.isValid || draft.target <= .now
                            || store.credentials != nil
                    )
                    .accessibilityIdentifier("saveMeeting")
                }
            }
            .onAppear {
                draft = store.meeting
                if let proposedPlace {
                    draft.place = proposedPlace.displayName.text
                    draft.coordinate = proposedPlace.location
                }
            }
        }
    }
}
