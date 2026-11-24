# notifly_sdk (iOS)

![Generic badge](https://img.shields.io/badge/pod-2.0.0-green.svg)
![Generic badge](https://img.shields.io/badge/platform-ios-blue.svg)
![Generic badge](https://img.shields.io/badge/ios-15.0+-blue.svg)

## 요구사항

- iOS 15.0+
- Xcode 15.0+
- Swift 5.0+

## 앱에서 Notifly SDK 사용하기
[Notifly 개발자 문서](https://docs.notifly.tech/ko/developer-guide/client-sdk/ios-sdk)를 참고해주세요.

## 테스트 앱 실행

`NotiflyExample/NotiflyTestApp.xcodeproj`를 열고 `NotiflyTestApp` scheme을 실행합니다.
앱과 알림 확장은 저장소 루트의 로컬 Swift Package에서 `notifly_sdk` product를 사용하므로,
SDK 소스 수정사항이 앱 빌드에 바로 반영됩니다. Swift에서는 `import notifly_sdk`로 가져옵니다.

`NotiflyCore`는 `Package.swift`가 관리합니다. `build/NotiflyCore.xcframework`가 있으면 로컬
바이너리를 사용하고, 없으면 지정된 릴리스 바이너리를 다운로드합니다. Core 소스를 수정했다면
`./scripts/build_kmp_core_xcframework.sh`로 로컬 바이너리를 다시 빌드합니다.

## SDK 단위 테스트

테스트는 `Tests/NotiflySDKTests`에 있으며, `Package.swift`의 `NotiflySDKTests` 타겟으로
등록되어 있습니다. Xcode에서 루트의 `Package.swift`를 열고 `notifly_sdk-Package` scheme과
iOS 시뮬레이터를 선택해 테스트합니다.

터미널에서는 저장소 루트에서 실행합니다. `SIMULATOR_ID`에는 `xcrun simctl list devices available`에
표시되는 iPhone 시뮬레이터의 UUID를 지정합니다.

```sh
xcodebuild test \
  -scheme notifly_sdk-Package \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -onlyUsePackageVersionsFromResolvedFile \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO
```

SDK가 UIKit과 WebKit을 사용하므로 iOS 시뮬레이터에서 테스트합니다.
