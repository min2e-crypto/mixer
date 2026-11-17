# ADR

## 001. 앱별 오디오 제어에 Core Audio Process Tap을 쓴다 (2026-11-18)

- 결정: `AudioHardwareCreateProcessTap`(muteBehavior `.mutedWhenTapped`, private tap) + private aggregate device + IO proc 게인 방식을 쓴다. 최소 macOS 14.4.
- 이유: 드라이버 설치 없이 원래 소리를 끄고 다시 출력할 수 있다. ScreenCaptureKit은 원래 소리를 끌 수 없고, HAL 가상 드라이버는 설치·서명·유지 부담이 크다. vorssaint-utils가 실제로 이 방식으로 동작한다.
- 근거: `/Users/home/coding/reverse_engineering/vorssaint-analysis.md`

## 002. 볼륨 100%인 앱은 탭하지 않는다 (2026-11-18)

- 결정: 볼륨이 100%이고 출력 지정이 없는 앱에는 엔진을 만들지 않는다. 엔진이 실패하면 탭을 해제해 원래 소리로 돌아간다(fail-open).
- 이유: 기본 상태에서는 시스템 오디오에 개입하지 않아야 지연·버그 위험이 가장 작다.

## 003. vorssaint-utils 코드는 복사하지 않는다 (2026-11-18)

- 결정: GPL-3.0 코드를 복사·번역하지 않고, 분석으로 얻은 사실과 아이디어만 참고해 직접 작성한다.
- 이유: 나중에 GPL이 아닌 라이선스로 공개할 수 있는 선택지를 남긴다.

## 004. SwiftPM + 스크립트로 .app을 조립하고 고정 자체 서명 인증서로 서명한다 (2026-11-18)

- 결정: Xcode 프로젝트 없이 SwiftPM으로 빌드하고 스크립트로 `.app`을 만든다. 서명은 키체인의 고정 자체 서명 인증서로 한다.
- 이유: `~/Personal_Project/tidy`와 같은 구조를 유지한다. 시스템 오디오 녹음 권한(TCC)은 서명 ID에 묶이므로, ad-hoc 서명으로 다시 빌드할 때마다 권한이 풀리는 것을 막는다.

## 005. 주 UI는 노치에서 펼치는 패널로 하고, 메뉴바 패널은 대체 UI로 남긴다 (2026-11-18)

- 결정: 노치 화면에서는 노치를 클릭하면 믹서 패널이 펼쳐진다. 노치 없는 화면에서는 메뉴바 패널을 쓴다. 창은 펼친 크기로 한 번만 잡고 `CAShapeLayer` 마스크 path만 애니메이션하며, `hitTest`를 path로 제한해 클릭을 통과시킨다. 맨 윗줄 클릭은 전역 마우스 모니터로 받는다. 노치 창에는 공개 API만 쓴다.
- 이유: 마스터가 노치에서 펼치는 방식을 원한다. 창 크기를 프레임마다 바꾸면 깜빡이므로 마스크 방식을 택한다. 전역 마우스 모니터는 TCC 권한이 필요 없다. 비공개 API는 OS 업데이트에 취약하다.
- 근거: `/Users/home/coding/reverse_engineering/vorssaint-notch-analysis.md`

## 006. 탭 생성은 Swift `CATapDescription` 이니셜라이저를 그대로 쓴다 (2026-11-18)

- 결정: ObjC 우회 모듈 없이 `CATapDescription(stereoMixdownOfProcesses: [AudioObjectID])`를 쓴다. PID는 `kAudioHardwarePropertyTranslatePIDToProcessObject`로 오디오 프로세스 객체로 바꿔 넘긴다.
- 근거: macOS 26.6 + Xcode 27.2 SDK의 Swift 오버레이에 이니셜라이저가 있고, 0단계 tapspike에서 탭·aggregate 생성과 IO proc 구동이 성공했다(탭 포맷 48kHz 2ch Float32 interleaved, `afplay -v 0.02` 재생 시 입력 피크 0.00183 = 예상값과 일치). vorssaint의 ObjC 우회는 14.4 초기 SDK 문제 대응이라 이 프로젝트에는 필요 없다.
- 함께 확인한 것: main.swift 최상위 클로저는 MainActor로 추론되어 IO 스레드에서 런타임 격리 검사에 걸린다. IO 블록은 격리되지 않은 함수나 타입 안에서 만든다. 자체 서명 인증서의 지정 요구사항은 `certificate leaf = H"…"`라 재빌드해도 바뀌지 않는다.

## 007. helper 프로세스는 책임 프로세스(비공개 심볼)로 먼저 앱에 묶는다 (2026-11-18)

- 결정: `ProcessMonitor`는 `responsibility_get_pid_responsible_for_pid`를 `dlsym`으로 찾아 상위 pid로 먼저 쓰고, 심볼이 없거나 자기 자신을 돌려주면 `proc_pidinfo`의 부모 pid로 대신한다. 순수 로직(`AppGrouping`)은 상위 pid를 클로저로만 받는다.
- 이유: WebKit 계열 XPC helper(`com.apple.WebKit.GPU`)는 부모가 launchd라서 부모 체인으로는 Safari·카카오톡 같은 소유 앱에 닿지 않는다. 2단계에서 실측한 결과 이 심볼은 WebKit.GPU를 소유 앱 pid로 돌려줬다. 이를 대신할 공개 API는 없다.
- 위험: 비공개 심볼이라 OS 업데이트로 사라질 수 있다. 사라져도 부모 체인으로 동작은 하되, Safari 소리는 앱 행이 아니라 helper 행으로 보일 수 있다.

## 008. 일반 앱에 묶이지 않은 프로세스는 재생 중일 때만 목록에 보인다 (2026-11-18)

- 결정: `AppGroup.isApp`이 false(번들 ID로만 묶인 시스템 프로세스)이면 `isPlaying`일 때만 `MixerController.apps`에 넣는다.
- 이유: HAL 프로세스 목록에는 loginwindow, corespeechd 같은 데몬이 오디오 연결만 가진 채 늘 들어 있어서, 그대로 보여 주면 목록이 노이즈로 찬다.

## 009. 게인은 C11 원자 변수로 IO 스레드에 넘긴다 (2026-11-18)

- 결정: `MixerAtomics` C 타깃(`_Atomic float`, relaxed load/store)을 둔다.
- 이유: 최소 OS가 14.4라 macOS 15+ 전용인 `Synchronization.Atomic`을 쓸 수 없고, 외부 패키지 의존은 피한다. IO 블록 한 번에 load 한 번이라 함수 호출 비용은 무시할 만하다.

## 010. 노치 클릭은 패널 mouseDown과 전역 마우스 모니터를 둘 다 받는다 (2026-11-18, 3.5-a)

- 측정(자동): 내장 화면 1512×982, 노치 rect (665, 950, 185×32), `safeAreaInsets.top` 32, 메뉴바 높이 33(`frame.maxY - visibleFrame.maxY`). 노치 높이 전체가 메뉴바 높이 안에 들어간다. `notchspike` 패널은 CGWindowList에서 노치 rect와 같은 bounds, 레이어 26(statusBar+1)으로 확인했다.
- 측정하지 못한 것: 실제 클릭이 높이별로 패널 `mouseDown`과 전역 모니터 중 어디로 가는지. 작업 셸에 손쉬운 사용 권한이 없어 합성 클릭을 보낼 수 없었다. `swift run notchspike 60`으로 마스터가 직접 확인한다.
- 결정: 결과와 관계없이 동작하도록 두 경로를 모두 쓴다. 패널 안 클릭은 `NotchContainerView.mouseDown`이, 메뉴바가 가져가는 클릭은 상시 설치한 전역 `leftMouseDown/Up` 모니터(down·up 모두 노치 rect 안일 때)가 토글한다. 전역 모니터는 다른 앱으로 간 이벤트만 받으므로 한 클릭이 두 번 토글되지 않는다. 바깥 클릭으로 닫는 모니터는 노치 rect 안의 클릭을 무시해, 열린 상태에서 노치를 누르면 닫혔다가 다시 열리는 일을 막는다.

## 011. Discord는 제외 목록에서 뺀다 (2026-11-18)

- 결정: `com.hnc.Discord`를 `EnginePolicy.excludedBundleIDs`에서 빼서 일반 앱처럼 볼륨을 조절한다. Zoom·Teams·DAW는 계속 제외한다.
- 이유: 마스터가 Discord 볼륨 조절을 원한다.
- 감수하는 위험: 볼륨을 100% 밖으로 바꾼 상태에서 Discord 화면 공유(소리 포함)를 하면, Discord가 자기 앱 소리로 인식해 빼던 통화 소리를 Mixer가 대신 재생하므로 상대에게 다시 들어갈 수 있다. 100%면 탭하지 않으므로(ADR 002) 영향이 없다.
