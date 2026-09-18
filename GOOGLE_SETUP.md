# 개발용 Google 연결 설정

앱 사용자에게 키를 입력하게 하지 않습니다. 모든 Google 키는 개발 단계에서 `Config/Local.xcconfig`에 한 번 설정하고 빌드합니다. 기존 Keychain 입력값은 더 이상 사용하지 않습니다.

## Google Cloud 준비

1. [Google Cloud 콘솔](https://console.cloud.google.com/)에서 프로젝트를 만들고 결제 계정을 연결합니다.
2. API 라이브러리에서 Maps SDK for iOS, Places API (New), Routes API를 활성화합니다.
3. 사용자 인증 정보에서 지도용 키와 검색·경로용 키를 만듭니다.
4. 지도용 키는 iOS 앱 제한과 본인 번들 ID(기본 `com.reunion.poc`), Maps SDK for iOS API 제한을 적용합니다.
5. 검색·경로용 키는 Places API (New)와 Routes API만 허용합니다. 현재 비공개 PoC는 기기에서 직접 REST 요청을 보냅니다. 공개 배포 단계에서는 웹서비스 키를 인증된 서버로 이전합니다.

발급된 키가 로컬 파일에 있으면 Codex가 설정 파일에 연결할 수 있습니다. 계정 비밀번호를 공유할 필요는 없습니다. 현재 프로젝트 파일에는 예시 값만 있고 실제 발급 키는 없습니다.

```xcconfig
GOOGLE_MAPS_API_KEY = YOUR_MAPS_SDK_KEY
GOOGLE_PLACES_API_KEY = YOUR_SEARCH_AND_ROUTES_KEY
GOOGLE_ROUTES_API_KEY = YOUR_SEARCH_AND_ROUTES_KEY
```

이 파일은 Git에서 제외합니다. 키 변경 후 앱을 다시 빌드합니다. Google 사용량에 따라 비용이 발생할 수 있으므로 테스트용 할당량·결제 알림을 설정합니다. 알림 자체가 비용 상한은 아닙니다.

## 실제 연결 확인

- 재합류 → 다시 만날 약속 정하기 → 위치 사용 허용 → 카페·역·주소 검색.
- 결과를 선택하고 시간·이동수단·여유시간을 설정해 저장.
- 함께 보기에서 실제 지도 타일과 내 위치 확인.
- 현재 위치부터 약속 장소까지 Google 경로 응답과 출발시간 확인.

시뮬레이터는 실제 GPS 대신 설정한 위치를 씁니다. Simulator의 Features → Location에서 테스트 위치를 설정하세요. 임의 도시로 대체하지 않습니다.

Google Maps API는 친구의 기기끼리 위치를 전달해 주지 않습니다. 친구 연결은 별도의 동기화 서비스가 담당하며, 주소도 같은 개발 설정 파일에서 읽습니다. 서버 주소를 앱 사용자에게 입력시키지 않습니다.

공식 문서: [Maps SDK 키](https://developers.google.com/maps/documentation/ios-sdk/get-api-key), [Places API 키](https://developers.google.com/maps/documentation/places/web-service/get-api-key), [Text Search](https://developers.google.com/maps/documentation/places/web-service/text-search).
