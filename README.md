# 다시 만나 — iOS PoC

Apple 기본 TabView, NavigationStack, List, Form, 검색창과 날짜 선택기로 만든 재합류 앱입니다. iOS 17 이상, Xcode 26.3에서 빌드했습니다.

## 화면

- **재합류**: 다시 만날 약속 정하기, 현재 위치 기반 장소 검색, 약속 시간, 개인별 이동수단·여유시간, 출발 안내, 출발·도착 확인.
- **함께 보기**: Google 지도, 나·친구의 자유시간/이동 중/도착 상태, 위치 공유 스위치, 마지막 위치 갱신 상태.
- **친구와 연결**: 이름과 초대 코드만 입력. Google 키, 서버 주소, 테스트 기록 화면은 없습니다.

위치 공유는 기본으로 꺼져 있습니다. 함께 보기에서 켜면 자유시간에도 공유하고, 꺼도 자유시간·이동 중 같은 상태는 유지됩니다. 도착 뒤에도 켜 둔 공유는 유지되며 모임 종료 시 두 사람 모두 공유가 종료됩니다. 공유를 끄면 이 기기의 백그라운드 위치 수집을 즉시 중지하고 서버에서 좌표를 제거합니다. 오프라인이면 상대에게 변경 전달이 지연될 수 있어 화면에 전달 대기를 표시합니다.

## 개발 설정

`Reunion.xcodeproj`를 열고 `Reunion` Scheme을 실행합니다. Google Maps SDK 11.1.0은 Swift Package Manager가 받습니다.

`Config/Local.xcconfig`에 지도·검색·경로 키와 연결 서비스 주소를 한 번 설정합니다. 이 파일은 Git에서 제외돼 있습니다. 앱은 이 설정만 읽으며 기존 Keychain 입력값을 사용하지 않습니다.

```xcconfig
GOOGLE_MAPS_API_KEY = YOUR_MAPS_SDK_KEY
GOOGLE_PLACES_API_KEY = YOUR_SEARCH_AND_ROUTES_KEY
GOOGLE_ROUTES_API_KEY = YOUR_SEARCH_AND_ROUTES_KEY
REUNION_SERVICE_URL = https:/$()/your-service.example.com
```

URL 중간의 `$()`는 xcconfig가 `//`를 주석으로 해석하는 것을 피하기 위한 표기입니다. 실제 앱에는 정상적인 HTTPS 주소가 들어갑니다.

[Google 설정 가이드](GOOGLE_SETUP.md)에서 프로젝트·결제·API 활성화 방법을 확인합니다. 저장소에는 예시 설정만 포함하며 실제 키가 들어 있는 Local.xcconfig는 제외합니다. 연결 서비스 주소는 별도로 설정해야 합니다. 키나 서버가 없을 때 지도·친구·검색 결과를 가짜로 표시하지 않습니다. 이 단계에서는 개발자가 실제 키와 서비스 주소를 등록해야 합니다.

## Google와 친구 연결 서비스의 역할

- Maps SDK for iOS: 지도 표시.
- Places API (New): 현재 위치 주변 5km를 우선하는 장소 검색.
- Routes API: 이동시간 계산. `출발시간 = 재합류 목표시간 - duration - 여유시간`.
- 별도 연결 서비스: 친구의 상태·위치 동기화와 출발 알림.

현재 앱은 동봉한 Node 중계 서버 방식입니다. 자체 서버 운영을 없애려면 Firebase/CloudKit 같은 관리형 서비스로 전환할 수 있지만, 이 프로젝트는 아직 그 방식으로 전환하지 않았습니다. 근거리 무선 연결만으로 멀리 떨어진 두 기기의 인터넷 동기화를 대신하지 않습니다.

## 중계 서버와 두 iPhone

Node 20 이상에서 아래를 실행합니다.

```sh
cd Server
node server.mjs
```

기본 포트는 8787입니다. 실제 현장에서는 HTTPS 주소로 배포한 뒤 `REUNION_SERVICE_URL`에 설정하고 같은 구성으로 두 기기에 설치합니다. 로컬 실행만으로 인터넷에 공개되지는 않습니다. 서버 미설정 시 앱은 초대 코드 만들기·참여를 비활성화합니다.

A가 장소와 시간을 정한 뒤 친구와 연결에서 초대 코드를 만들고, B가 그 코드로 참여합니다. 둘 다 함께 보기에서 위치 공유를 직접 켭니다. 연결 후 약속 장소·시간은 고정되며 각자의 이동수단·여유시간은 재합류 화면에서 변경할 수 있습니다.

서버는 메모리 저장소로 재시작 시 모임이 사라집니다. 12시간 뒤 다음 요청 시 정리합니다. 2명 제한, 참여자별 인증 토큰, 요청 크기·빈도 제한이 있습니다. 검색과 경로 계산 시에는 현재 위치가 Google에 전달됩니다.

## 푸시와 백그라운드

실제 iPhone 설치 시 Xcode에서 본인 Apple Team·Bundle ID를 지정합니다. 푸시는 앱의 Push Notifications 권한과 서버의 APNs 설정이 필요합니다.

```sh
export APNS_KEY_ID=YOUR_KEY_ID
export APNS_TEAM_ID=YOUR_TEAM_ID
export APNS_KEY_PATH=/secure/path/AuthKey.p8
export APNS_BUNDLE_ID=com.reunion.poc
export APNS_ENV=development
node server.mjs
```

배포 빌드는 APNs 환경을 production으로 일치시킵니다. `.p8` 키는 서버에만 저장합니다. `/health`의 pushConfigured는 환경변수 존재 확인이며 실제 전달 보장은 아닙니다.

포그라운드는 4초 간격으로 상태를 동기화합니다. 공유 동의 후 백그라운드 GPS 이벤트에서도 갱신합니다. 강제 종료·권한 회수·통신 장애로 중단될 수 있습니다. 30초 이상 된 위치는 마지막 위치로 표시하고, 친구가 미연결일 때 자유시간이라고 가정하지 않습니다. ETA는 출발 당시 예상이며 이동 중 자동 재계산은 포함하지 않았습니다.

이동 감지는 출발 예정 시각 전후 10분 이내에서 80m 이상 이동 시 확인을 요청하는 방식입니다. 자유시간 이동을 자동으로 출발 상태로 바꾸지 않습니다.

## 검증

```sh
swift test
node --test Server/server.test.mjs
xcodebuild -project Reunion.xcodeproj -scheme Reunion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO test
```

현재 변경에서 iOS 빌드와 UI 테스트 3개, 서버 테스트 9개가 통과했습니다. 실제 Google 지도·검색·경로 응답, 두 실제 iPhone의 GPS·APNs·잠금화면 동작은 키·서비스·기기가 준비된 후 별도 검증해야 합니다.
