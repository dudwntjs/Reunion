# 다시 만나 — iOS PoC

여행 중 각자 시간을 보낸 뒤 다시 만나기 위한 iOS 앱입니다. Google 지도·장소 검색·경로 계산과 Apple CloudKit 친구 공유를 사용합니다. 직접 운영하거나 배포할 서버는 없습니다.

## 화면

- **재합류**: 검색으로 만날 장소 선택, 시간 설정, 개인별 이동수단·여유시간, 앱 내 길찾기, 출발·도착 확인.
- **함께 보기**: 친구 초대, 나와 친구들의 Google 지도 핀, 개인별 상태·마지막 위치, 전체 이동·도착 인원, 위치 공유 스위치.

## 개발 설정

`Reunion.xcodeproj`의 `Reunion` Scheme을 사용합니다. iOS 17 이상, Google Maps SDK 11.1.0입니다.

Google 키는 Git에서 제외한 `Config/Local.xcconfig`에 설정합니다. [Google 설정](GOOGLE_SETUP.md)과 [iCloud 설정](CLOUDKIT_SETUP.md)을 확인하세요. 앱에 키나 서버 주소를 입력하는 화면은 없습니다.

```xcconfig
GOOGLE_MAPS_API_KEY = YOUR_MAPS_SDK_KEY
GOOGLE_PLACES_API_KEY = YOUR_SEARCH_AND_ROUTES_KEY
GOOGLE_ROUTES_API_KEY = YOUR_SEARCH_AND_ROUTES_KEY
```

## 친구 초대와 위치 공유

모임을 만든 사람이 Apple 공유 화면에서 참가자의 iCloud 계정을 지정합니다. 초대받은 사람은 링크를 열고 앱에서 이름을 입력해 참여합니다. 초대받지 않은 계정은 링크만 알아도 접근할 수 없습니다. 최대 10대가 참여하며 각 기기는 별도 참가자로 표시됩니다.

위치 공유는 기본으로 꺼져 있고, 각자 켜면 자유시간에도 공유합니다. 공유를 끄면 기기에서 위치 수집을 중단하고 CloudKit의 좌표를 비웁니다. 오프라인이면 반영이 지연될 수 있습니다. 도착은 공유를 자동으로 끄지 않으며, 모임 종료는 모든 참가자의 좌표를 지우고 공유를 종료합니다. 새 모임에 참여하려면 현재 모임을 종료하고 새 약속을 시작합니다.

CloudKit의 비공개 공유 계층을 사용합니다. 초대된 참가자는 신뢰하는 공동 편집자이며 계층 전체에 읽기·쓰기 권한이 있습니다. 일반 앱 동작은 본인의 참가자 레코드만 갱신합니다. 서버가 본인 레코드에만 쓰도록 강제하는 권한 분리 모델은 아닙니다. 종료된 모임의 장소·이름·상태는 CloudKit에 남으며 자동 만료·기록 삭제 기능은 아직 없습니다. 위치 기록은 누적하지 않고 최신 좌표만 저장합니다.

## 동기화와 알림

앱이 열려 있으면 약 10초마다 CloudKit 상태를 확인하며, 위치 공유 중 위치 이벤트와 출발·도착 확인 시에도 갱신합니다. 서버가 요청 재시도를 지시하면 그 시간을 기다립니다. 30초 이상 된 좌표는 마지막 위치로 표시합니다.

CloudKit의 변경 알림은 백그라운드 갱신을 요청합니다. 앱이 변경을 받아 친구의 출발을 확인하면 로컬 알림을 표시합니다. 강제 종료·절전·네트워크 상태에 따라 지연되거나 누락될 수 있어 즉시 출발 푸시를 보장하지 않습니다. 라이브 액티비티도 앱 실행 기회를 얻었을 때 갱신하며 별도 APNs 서버나 `.p8` 키를 사용하지 않습니다.

재합류 출발 안내는 `목표시간 - Routes duration - 여유시간`으로 예약하는 기기 내 알림입니다. ETA는 출발 당시 예상이며 이동 중 자동 재계산은 포함하지 않습니다. Google의 국가별 경로 지원 제한은 그대로 적용됩니다.

## 검증

```sh
swift test
sh Tests/check-cloud-records.sh
xcodebuild -project Reunion.xcodeproj -scheme Reunion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO test
```

자동 테스트는 로컬 모델·초대 URL·CloudKit 레코드 구성·UI를 검증합니다. 실제 iCloud 계정 간 초대 수락, 위치 동기화, 백그라운드 알림은 컨테이너 등록과 실기기 테스트가 필요합니다. 과거 `Deliverables`의 화면과 서버 검증 기록은 이전 버전 자료입니다.
