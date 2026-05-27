# Sideby

[English](README.md) | 한국어

Sideby는 여러 디스플레이를 사용하는 macOS 사용자가 여러 화면을 하나의 작업 컨텍스트처럼 함께 전환할 수 있게 돕는 네이티브 메뉴바 유틸리티입니다. 제품 슬로건은 "Side by Side"입니다.

Sideby는 Mission Control 대체제나 전체 윈도우 매니저가 아닙니다. 함께 이동할 디스플레이를 고르고, Sideby를 켠 뒤, 제스처나 선택적 단축키로 이전/다음 macOS Space로 이동하는 좁은 워크플로에 집중합니다.

## 만들게 된 배경

Sideby는 한 작업 컨텍스트를 여러 디스플레이에 나눠 정리해두고 싶은 생각에서 출발했습니다. 각 화면에는 같은 일의 서로 다른 조각이 놓여 있고, 컨텍스트를 바꿀 때는 그 화면 묶음이 디스플레이별로 따로 움직이는 대신 함께 이동하면 좋겠다고 봤습니다.

Sideby의 목표는 멀티 디스플레이 환경을 하나의 작업공간처럼 묶고, 그 작업공간을 한 번의 의도적인 행동으로 옮기는 것입니다. 범위는 작게 유지하고, 공개 macOS API만 사용하며, 권한이나 Space 한계가 있을 때는 가능한 척하지 않고 명확한 진단으로 설명합니다.

## 현재 상태

Sideby는 pre-1.0 소프트웨어입니다. V1 앱 셸, 온보딩 플로우, 메뉴바 설정, 메인 설정, 디스플레이 선택, 입력 파이프라인, 진단, 로컬 번들 스크립트를 개발 중입니다.

현재 릴리즈 전략은 App Sandbox off 직접 배포입니다. Sideby는 공개 macOS API만 사용해야 하며 private Mission Control 또는 Spaces API에 의존하지 않습니다.

## 기능

- 여러 디스플레이를 빠르게 제어하는 메뉴바 앱
- 함께 전환할 디스플레이를 고르는 Move Targets
- 공개 macOS 키보드 명령 경로를 통한 Previous/Next Screen Switching
- 기본 입력 습관: `Option + Shift + horizontal swipe`
- 메인 설정에서 켤 수 있는 선택적 Previous/Next 키보드 단축키
- Accessibility와 Screen Switching access를 안내하는 첫 실행 온보딩
- 권한, 디스플레이, 전환 한계를 설명하는 진단
- Display Spaces 라벨과 best-effort visible app/window suggestion
- 영어/한국어 UI 문구

## 요구사항

- macOS 14 이상
- Swift 6 toolchain이 포함된 Xcode
- 전역 입력 감지를 위한 Accessibility 권한
- 요청한 Space 전환 명령을 보내기 위한 Screen Switching access
- 현재 V1 명령 경로에서 필요할 경우 System Events Automation 권한

Sideby는 V1 Screen Switching을 위해 Screen Recording 권한을 요청하지 않습니다.

## 빠른 시작

저장소를 클론한 뒤 테스트를 실행하고 로컬 제품 번들을 빌드합니다.

```bash
swift test
scripts/build_app_bundle.sh
open "dist/Sideby.app"
```

앱을 연 뒤 macOS 시스템 설정에서 요청된 Accessibility와 Screen Switching 권한을 허용합니다. 번들을 다시 빌드한 뒤에도 macOS가 권한을 거부 상태로 표시하면 macOS 시스템 설정에서 기존 Sideby 항목을 삭제하고 다시 빌드한 앱을 추가하세요.

개발과 macOS API 실험에는 dev app을 사용합니다.

```bash
scripts/build_dev_app_bundle.sh
open "dist/SidebyDevApp.app"
```

`SidebyDevApp`은 로컬 테스트 하네스이며 릴리즈 번들이 아닙니다.

## 개발

Xcode에서 Swift package를 직접 엽니다.

```bash
xed Package.swift
```

제품 앱은 `SidebyApp` scheme을, 로컬 dev harness는 `SidebyDevApp` scheme을 사용합니다.

자주 쓰는 명령은 다음과 같습니다.

```bash
swift test
swift build --product SidebyApp
swift build --product SidebyDevApp
scripts/build_app_bundle.sh
scripts/build_dev_app_bundle.sh
```

제품 번들은 `Resources/AppIcon.icns`를 사용합니다. 원본 이미지를 바꾸는 경우 번들 빌드 전에 아이콘을 다시 생성합니다.

```bash
swift scripts/generate_app_icon.swift <source-png> Resources/AppIcon.icns
scripts/build_app_bundle.sh
```

## 아키텍처

저장소는 작은 SwiftPM 모듈로 나뉩니다.

```text
Sources/
  SidebyApp/       product app, menu bar, panels, onboarding
  SidebyDevApp/    local probes and diagnostics
  SidebyCore/      domain models, gesture logic, settings, diagnostics
  SidebySystem/    macOS API adapters
  SidebyUI/        reusable SwiftUI views and view models
Tests/
  SidebyCoreTests/
  SidebySystemTests/
  SidebyUITests/
```

중요한 경계는 다음과 같습니다.

- Space 전환은 `ContextSwitchEngine`과 `SpaceCommandExecutor`를 통해서만 호출합니다.
- 전역 입력 어댑터는 `SidebySystem`에 둡니다.
- 제스처 해석은 `SidebyCore`의 순수 Swift 도메인 로직에 둡니다.
- SwiftUI는 재사용 UI를 맡고, 메뉴바/윈도우/시스템 연동은 AppKit 어댑터가 처리합니다.

개발 환경 메모는 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)를, 사용자를 보호하기 위한 최소 기술 경계는 [docs/DECISIONS.md](docs/DECISIONS.md)를 참고하세요.

## 개인정보와 권한

Sideby는 Sideby가 켜져 있을 때 설정된 제스처를 감지하기 위해 Accessibility 권한을 사용합니다. 사용자가 행동한 뒤 요청된 Previous/Next Space 명령을 보내기 위해 Screen Switching access를 사용합니다.

Sideby는 입력 내용, raw input event, 스크린샷, private Space ID, app bundle ID, window ID, 숨겨진 Mission Control 상태를 저장하지 않습니다. Display Spaces 라벨은 사용자가 직접 작성하며 로컬에 저장됩니다.

## 문서

- [Development](docs/DEVELOPMENT.md)
- [Decisions](docs/DECISIONS.md)

## 기여

기여를 환영합니다. 이슈나 pull request를 열기 전에 [CONTRIBUTING.md](CONTRIBUTING.md)를 읽어 주세요.

코드 변경 전에는 `swift test`를 실행해 주세요. 권한, 입력, 전환, 패키징, 릴리즈에 영향을 주는 변경은 먼저 이슈에서 트레이드오프를 논의해 주세요.

## 보안

보안 취약점은 공개 이슈로 제보하지 말아 주세요. 제보 절차는 [SECURITY.md](SECURITY.md)를 참고하세요.

## 라이선스

Sideby는 [MIT License](LICENSE)로 배포됩니다.
