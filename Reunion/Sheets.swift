import SwiftUI

struct ConnectionView: View {

    // MARK: - Properties

    @Environment(ReunionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var code = ""
    @State private var joining = false
    @State private var ending = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            connectionForm
                .navigationTitle("친구와 연결")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Text("완료")
                        }
                    }
                }
                .alert("약속을 종료할까요?", isPresented: $ending) {
                    Button(role: .cancel) {
                    } label: {
                        Text("취소")
                    }
                    Button(role: .destructive) {
                        Task {
                            await store.finish()
                            dismiss()
                        }
                    } label: {
                        Text("종료")
                    }
                } message: {
                    Text("두 사람의 위치 공유가 중지됩니다.")
                }
                .alert(
                    "연결을 확인해 주세요",
                    isPresented: Binding(
                        get: {
                            store.error != nil
                        },
                        set: {
                            if !$0 {
                                store.error = nil
                            }
                        }
                    )
                ) {
                    Button {
                        store.error = nil
                    } label: {
                        Text("확인")
                    }
                } message: {
                    Text(store.error ?? "")
                }
        }
    }
}
struct ReminderSheet: View {

    // MARK: - Properties

    @Environment(ReunionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var kind: PromptKind
    var onDepart: () -> Void

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(kind.title)
                        .font(.headline)
                    Text(kind.body)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button {
                        store.acknowledge(kind)
                        if kind == .movement {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                onDepart()
                            }
                        }
                    } label: {
                        Text(kind == .movement ? "네, 출발했어요" : "확인했어요")
                    }
                    if kind == .movement {
                        Button {
                            store.acknowledge(kind)
                        } label: {
                            Text("아직 자유시간을 보내고 있어요")
                        }
                    }
                }
            }
            .navigationTitle("출발 안내")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Subviews

extension ConnectionView {

    private var connectionForm: some View {
        Form {
            if let credentials = store.credentials {
                Section("친구 초대") {
                    LabeledContent("초대 코드", value: credentials.code)
                        .monospacedDigit()
                        .textSelection(.enabled)
                    ShareLink(item: "다시 만나 · 초대 코드 \(credentials.code)\n앱에서 친구와 연결하기를 눌러 참여해 주세요.") {
                        Label("초대 코드 공유", systemImage: "square.and.arrow.up")
                    }
                    LabeledContent("친구", value: store.friendJoined ? store.meeting.friendName : "참여 기다리는 중")
                }
                Section {
                    Button(role: .destructive) {
                        ending = true
                    } label: {
                        Text("약속 종료")
                    }
                    .disabled(store.phase == .complete)
                    if store.pendingEnd {
                        Button {
                            Task {
                                await store.flushPendingEnd()
                            }
                        } label: {
                            Text("종료 요청 다시 보내기")
                        }
                    }
                }
            } else {
                Section {
                    TextField("내 이름", text: $name)
                        .textContentType(.name)
                    Picker("연결 방법", selection: $joining) {
                        Text("친구 초대")
                            .tag(false)
                        Text("코드로 참여")
                            .tag(true)
                    }
                    .pickerStyle(.segmented)
                    if joining {
                        TextField("6자리 초대 코드", text: $code)
                            .keyboardType(.numberPad)
                    }
                }
                if !joining {
                    Section("함께할 약속") {
                        Text(store.hasDestination ? store.meeting.place : "먼저 재합류 탭에서 약속을 정해 주세요.")
                        if store.hasDestination {
                            Text(store.meeting.target, format: .dateTime.month().day().hour().minute())
                        }
                    }
                }
                Section {
                    Button {
                        Task {
                            if await store.connect(
                                server: GoogleConfiguration.relayURL,
                                name: name,
                                code: joining ? code : nil
                            ) {
                                dismiss()
                            }
                        }
                    } label: {
                        HStack(alignment: .center, spacing: 8) {
                            Text(joining ? "참여하기" : "초대 코드 만들기")
                            if store.isLoading {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(
                        store.isLoading || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || (joining ? code.count != 6 || !code.allSatisfy(\.isNumber) : !store.hasDestination)
                            || GoogleConfiguration.relayURL.isEmpty
                    )
                } footer: {
                    if GoogleConfiguration.relayURL.isEmpty {
                        Text("친구 연결 서비스를 준비 중이에요. 연결이 준비되면 초대 코드를 사용할 수 있어요.")
                    } else {
                        Text("위치는 함께 보기에서 공유를 켰을 때만 전달됩니다.")
                    }
                }
            }
            if let issue = store.connectionError {
                Section {
                    Text(issue)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
