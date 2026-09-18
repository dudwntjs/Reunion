# CloudKit 연결 설정

직접 서버 운영·배포, 서버 URL, APNs `.p8` 키는 필요하지 않습니다. 유료 Apple Developer 계정과 각 iPhone의 iCloud 로그인이 필요합니다.

## Xcode에서 한 번 설정

1. `Reunion.xcodeproj`를 열고 **Reunion 타깃 → Signing & Capabilities**에서 본인의 유료 Team과 자동 서명을 선택합니다.
2. **iCloud → CloudKit**을 켜고 컨테이너 **`iCloud.com.reunion.poc`**를 생성하거나 선택합니다. 코드와 entitlements는 이 식별자로 준비돼 있습니다. 등록 권한 또는 식별자 충돌로 다른 이름을 쓰면 `SessionClient.containerID`와 `Config/Reunion.entitlements`를 함께 변경해야 합니다.
3. **Push Notifications**, **Background Modes → Remote notifications / Location updates**를 사용합니다. entitlements와 Info.plist에 해당 설정을 준비했습니다.
4. 실제 iPhone을 연결해 개발 빌드를 실행합니다. 앱에서 모임을 한 번 만들면 Development 환경에 아래 레코드 형식이 생성됩니다. 모든 기기는 같은 컨테이너·환경의 빌드를 사용해야 합니다.

컨테이너는 [Apple Developer의 iCloud Containers](https://developer.apple.com/account/resources/identifiers/list/cloudContainer) 또는 Xcode에서 관리하고, 데이터는 [CloudKit Console](https://icloud.developer.apple.com/)에서 확인할 수 있습니다. 계정에 실제 컨테이너를 만드는 작업은 파일에 식별자를 쓰는 것과 별개입니다.

## 레코드와 권한

- `ReunionMeeting`: `meeting` Bytes(JSON), `ended` Int64.
- `ReunionParticipant`: `deviceID` String, `peer` Bytes(JSON), 시스템 parent 참조.
- 모임별 private custom zone, 루트 CKShare와 미리 만든 참가자 슬롯 10개를 원자적으로 저장합니다.
- CKShare 공개 권한은 `.none`. Apple 공유 화면은 초대한 사람만 / 읽기·쓰기로 제한합니다. Public Database는 사용하지 않습니다.
- 참가자는 공유 수락 후 Shared Database에 접근합니다. 동시에 같은 빈 슬롯을 선택하면 레코드 버전 충돌 후 다시 시도합니다. 모임 종료와 상태 갱신도 버전 충돌을 검사합니다.
- 일반 참가자는 Apple 공유 화면에서 다른 친구를 추가하지 않으며, 초대는 모임 생성자가 관리합니다. 초대된 계정 전체에 읽기·쓰기 권한이 있으므로 서로 신뢰하는 PoC 참가자만 초대하세요.

## 여러 iPhone 테스트

1. 각 기기에서 **설정 → Apple 계정 → iCloud**에 로그인하고 iCloud Drive를 켭니다. 서로 다른 계정 간 공유를 반드시 검증합니다.
2. A가 만날 장소와 시간을 정하고 **함께 보기 → 친구와 연결하기 → 모임 만들고 초대하기**를 누릅니다.
3. Apple 공유 화면에서 B·C의 iCloud 계정을 지정하고 메시지 등으로 초대를 직접 보냅니다.
4. B·C가 초대를 열어 앱으로 들어오면 이름을 확인하고 참여합니다. 앱이 자동으로 열리지 않으면 **초대로 참여**에서 초대 URL을 붙여 넣습니다. URL을 다른 사람에게 전달해도 초대받지 않은 계정은 접근할 수 없습니다.
5. 각자 위치 공유를 켜고, 이동·도착 상태와 다른 친구들의 핀을 확인합니다. 공유를 끈 사람의 핀만 사라지는지 확인합니다.
6. 초대되지 않은 계정의 거절, 11번째 기기 참여 거절, 동일 기기 재참여, 동시 참여, 오프라인 공유 중지·종료 재시도도 확인합니다.
7. 화면 잠금·강제 종료·저전력 모드에서 출발 알림과 위치 갱신 지연을 별도로 측정합니다. CloudKit 변경 알림과 라이브 액티비티의 즉시 갱신은 보장되지 않습니다.

## TestFlight

Development 테스트가 끝나면 CloudKit Console에서 스키마를 **Production에 배포**하고 TestFlight로 테스트합니다. Production은 새 레코드 형식을 자동 생성하지 않습니다. Development와 Production의 데이터는 공유되지 않습니다. 서명 프로파일의 iCloud 환경 및 APNs 환경은 배포 방식과 일치해야 합니다.

## 공식 문서

- [Apple CloudKit 공유 샘플](https://github.com/apple/sample-cloudkit-sharing)
- [CKShare](https://developer.apple.com/documentation/cloudkit/ckshare)
- [CKDatabaseSubscription](https://developer.apple.com/documentation/cloudkit/ckdatabasesubscription)
- [SwiftUI 초대 수락](https://developer.apple.com/documentation/coredata/accepting-share-invitations-in-a-swiftui-app)

## 이 작업에서 확인한 설정

2026-09-18 Xcode의 현재 Team으로 iCloud 컨테이너를 포함한 실기기 서명 빌드가 성공했습니다. 생성된 프로비저닝 프로파일에 `iCloud.com.reunion.poc` 접근 권한이 포함된 것을 확인했습니다. Debug는 Development, Release는 Production 환경을 지정합니다. 이는 실제 계정 간 공유와 데이터 동기화가 성공했다는 뜻은 아니며 위 현장 절차는 별도로 실행해야 합니다.
