import SwiftUI

struct ConnectionView: View {

    // MARK: - Properties

    @Environment(ReunionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var code = ""
    @State private var joining = false
    @State private var ending = false
    @State private var inviting = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            connectionForm
                .onAppear {
                    name = store.name
                    if let link = store.pendingInvitation {
                        code = link
                        joining = true
                    }
                }
                .sheet(isPresented: $inviting) {
                    if let credentials = store.credentials { CloudInviteView(credentials: credentials) }
                }
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
                    Text("모든 참가자의 위치 공유가 중지됩니다.")
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
                    if credentials.isOwner {
                        Button {
                            inviting = true
                        } label: {
                            Label("iCloud로 친구 초대", systemImage: "person.badge.plus")
                        }
                    } else {
                        Text("다른 친구를 초대하려면 모임을 만든 친구에게 요청해 주세요.")
                    }
                    LabeledContent("참여 인원", value: "\(store.peers.count + 1)명 / 최대 10명")
                    Text("초대한 iCloud 계정만 참여할 수 있어요.")
                    ForEach(store.peers) { peer in
                        LabeledContent(peer.name, value: peer.status)
                    }
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
                        Text("초대로 참여")
                            .tag(true)
                    }
                    .pickerStyle(.segmented)
                    if joining {
                        TextField("iCloud 초대 링크", text: $code)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
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
                                name: name,
                                code: joining ? code : nil
                            ) {
                                if joining { dismiss() } else { inviting = true }
                            }
                        }
                    } label: {
                        HStack(alignment: .center, spacing: 8) {
                            Text(joining ? "참여하기" : "모임 만들고 초대하기")
                            if store.isLoading {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(
                        store.isLoading || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || (joining ? CloudInvitation.url(code) == nil : !store.hasDestination)
                    )
                } footer: {
                    Text("iCloud에 로그인한 친구를 초대해 주세요. 위치는 함께 보기에서 공유를 켰을 때만 전달돼요.")
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
