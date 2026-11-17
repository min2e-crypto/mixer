# mixer 구현 계획

MacBook 노치를 누르면 펼쳐지는 패널에서 앱별 볼륨을 조절하는 개인용 도구.
참고 분석(vorssaint-utils @ `89d2626`, GPL-3.0):
- 오디오 엔진: `/Users/home/coding/reverse_engineering/vorssaint-analysis.md`
- 노치 UI: `/Users/home/coding/reverse_engineering/vorssaint-notch-analysis.md`

## 1. 목표와 범위

**1차 목표 (MVP)**
- 소리를 내는 앱 목록을 패널에 표시. 패널은 노치를 클릭하면 펼쳐지고(3.5단계), 노치 없는 화면에서는 메뉴바 패널로 대신한다
- 앱별 볼륨 슬라이더(0~200%, 가운데 = 원래 소리 100%)와 음소거. 100% 초과는 리미터로 클리핑을 막는다(ADR 012)
- 앱별 볼륨을 번들 ID 기준으로 기억했다가 앱이 다시 소리를 낼 때 적용
- 볼륨 100%인 앱은 건드리지 않음(fail-open)

**2차 (MVP 안정화 뒤 선택)**
- 앱별 출력 장치 지정
- 노치 확장: 호버로 열기, 스크롤 제스처, 노치 없는 화면의 가상 노치, 전체화면 숨김

**범위 밖**: AirPlay 출력(비공개 API 필요), macOS 14.4 미만 지원, 가상 오디오 드라이버, 배포·공증, 노치용 비공개 API(전용 Space, CAFilter 블러 등)

**전제(가정)**
- 실행 환경은 마스터의 Mac 한 대(Apple Silicon, macOS 26.6, Xcode + Swift 6.4)
- 배포하지 않는 개인 도구. 다만 나중에 공개할 수 있도록 vorssaint 코드는 복사하지 않고 직접 작성한다(아래 7장)

## 2. 동작 원리

```
HAL 오디오 프로세스 목록 ──► 앱 단위로 묶기 ──► 앱별 볼륨 상태
                                              │ 볼륨 ≠ 100% 인 앱만
                                              ▼
CATapDescription(processes: [앱의 오디오 객체], isPrivate, muteBehavior = .mutedWhenTapped)
  └► AudioHardwareCreateProcessTap            (원래 소리는 시스템이 음소거)
       └► private aggregate device            (main sub-device = 현재 기본 출력, tap list = [tap])
            └► IO proc: out = in × gain       (가로챈 소리를 볼륨 적용해 다시 출력)
```

ScreenCaptureKit은 원래 소리를 끌 수 없어 볼륨 조절에 쓸 수 없고, 가상 드라이버는 설치·유지 부담이 커서 제외한다.

## 3. 구조

SwiftPM 패키지 + 빌드 스크립트로 `.app`을 조립한다(`~/Personal_Project/tidy`와 같은 방식, Xcode 프로젝트 없음).

```
mixer/
├─ Package.swift              swift-tools 6.0, platforms .macOS("14.4")
├─ Sources/
│  ├─ MixerCore/              순수 로직, Core Audio 의존 없음 → 단위 테스트 대상
│  │   ├─ GainCurve.swift         슬라이더 값 → 선형 게인 (v², 부스트 구간 선형)
│  │   ├─ AppGrouping.swift       (pid, 부모 pid, 번들 ID) 목록 → 앱 단위 묶음
│  │   ├─ EnginePolicy.swift      어떤 앱에 엔진이 필요한지 판단(100%면 없음, 제외 목록)
│  │   ├─ Render.swift            버퍼 렌더: 게인 램프, 남는 프레임 0 채우기
│  │   ├─ PeakLimiter.swift       lookahead 피크 리미터(미리 할당한 링버퍼, IO 스레드에서 할당·락 없음)
│  │   ├─ VolumeStore.swift       번들 ID → 볼륨 저장/복원
│  │   ├─ NotchGeometry.swift     화면 정보 → 카메라 rect, 접힌/펼친 프레임 (노치 없으면 nil)
│  │   └─ NotchShapePath.swift    rect → 노치 실루엣 CGPath (어깨 곡선 + 아래 둥근 모서리)
│  ├─ MixerAudio/             Core Audio 래퍼 (통합 검증 대상)
│  │   ├─ HAL.swift               속성 읽기/리스너 헬퍼
│  │   ├─ ProcessMonitor.swift    kAudioHardwarePropertyProcessObjectList 감시
│  │   ├─ TapEngine.swift         앱 1개 = tap + aggregate + IO proc
│  │   └─ MixerController.swift   상태 ↔ 엔진 조정, 기본 출력 변경 대응
│  ├─ Mixer/                  앱 (MenuBarExtra + SwiftUI)
│  │   └─ Notch/                  NotchPanel, NotchContainerView(마스크·hitTest), NotchController, MixerNotchView
│  └─ tapspike/               0단계 검증용 CLI (MVP 후 삭제)
├─ Tests/MixerCoreTests/
├─ Resources/Info.plist       LSUIElement, NSAudioCaptureUsageDescription
└─ scripts/
   ├─ setup-signing.sh        자체 서명 인증서 1회 생성
   └─ build-app.sh            swift build → .app 조립 → 고정 인증서로 codesign
```

## 4. 단계별 계획

각 단계는 성공 기준을 통과해야 다음 단계로 넘어간다.

### 0단계 — 스파이크: 소리 한 앱 줄이기
가장 불확실한 부분(권한, 서명, 탭 동작)을 먼저 확인한다.
- `scripts/setup-signing.sh`: 로그인 키체인에 자체 서명 코드서명 인증서 생성. 현재 코드서명 ID가 0개라 필수
- `tapspike <pid> <gain>`: 해당 PID를 탭해 게인을 적용하고 Enter를 누르면 정리 후 종료
- `.app`으로 감싸 서명해서 실행(TCC 프롬프트에 사용 목적 문구가 필요)
- 확인할 것: macOS 26에서 Swift `CATapDescription` 이니셜라이저를 그대로 쓸 수 있는지. vorssaint는 14.4 초기 버그 때문에 ObjC로 우회했음

**성공 기준**
- 처음 실행할 때 "시스템 오디오 녹음" 권한 프롬프트가 뜬다
- 재생 중인 Music/Safari 소리가 gain 0.3에서 확실히 작아지고, 다시 빌드한 뒤에도 권한이 유지된다
- 종료하면 원래 소리로 돌아온다

### 1단계 — MixerCore (TDD)
테스트 먼저 작성하고 구현한다.
- `GainCurve`: 0→0, 0.5→0.25, 1→1, 2→2(부스트 구간 선형), 범위 밖 값 클램프
- `AppGrouping`: helper PID가 부모 체인으로 앱에 묶임, 자기 자신 PID 제외, 번들 ID 없는 프로세스 처리
- `EnginePolicy`: 볼륨 100% + 출력 지정 없음 → 엔진 없음, 제외 목록(DAW·Zoom·Teams) → 엔진 없음
- `Render`: 출력 프레임이 입력보다 많으면 나머지 0, 블록 안에서 이전 게인 → 새 게인 선형 램프, 탭 버퍼 인덱스 선택(채널 수 기준)
- `VolumeStore`: 저장 후 복원, 손상된 값 무시

**성공 기준**: `swift test` 통과

### 2단계 — 오디오 엔진
- `ProcessMonitor`: 프로세스 목록 변경을 리스너로 받아 `AppGrouping`에 전달. 재생 여부는 `kAudioProcessPropertyIsRunningOutput`
- `TapEngine`: 생성 순서 tap → aggregate → IO proc → start. 해제는 `AudioDeviceStop`만 바로 하고 destroy는 메인 스레드 밖에서
- 게인은 원자적 Float로 IO 스레드에 전달. IO proc 안에서는 락·할당·Swift 컬렉션 생성 금지
- `MixerController`: 기본 출력 장치가 바뀌면 모든 엔진 재생성, 탭 생성 실패 시 0.5초 뒤 1회 재시도하고 그래도 실패하면 권한 필요 상태로 표시
- 0단계 CLI를 `MixerAudio` 기반으로 바꿔 수동 검증

**성공 기준**
- 두 앱(Music, Safari)을 서로 다른 볼륨으로 동시에 조절할 수 있다
- 이어폰 ↔ 스피커를 전환해도 소리가 따라간다
- 100%로 되돌리면 엔진이 해제된다(`AudioDeviceStop` 확인 로그)

### 3단계 — 메뉴바 앱
메뉴바 패널은 3.5단계 이후 노치 없는 화면용 대체 UI와 종료·설정 메뉴로 남긴다.
- `MenuBarExtra(.window)` 패널: 앱 아이콘·이름·슬라이더·음소거 버튼, 재생 중 표시
- 권한이 없으면 안내 행 + 설정 열기(`x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture`)
- 로그인 시 실행: `SMAppService.mainApp`
- `scripts/build-app.sh`로 `~/Applications/Mixer.app` 설치

**성공 기준**: 재부팅 후 자동 실행되고, 저장된 앱 볼륨이 그 앱이 소리를 낼 때 적용된다

### 3.5단계 — 노치 UI (MVP 완성)
오디오 엔진과 독립된 단계다. 3단계의 `MixerController`(ObservableObject)를 메뉴바 패널과 노치 패널이 같이 관찰한다. 노치 창 자체에는 공개 API만 쓰고 TCC 권한도 추가로 필요 없다.

**3.5-a 스파이크: 클릭이 어디로 오는가**
- 노치 화면(`safeAreaInsets.top > 0` + `CGDisplayIsBuiltin`)에 빈 검정 패널을 띄운다
- 노치 영역 클릭이 패널의 `mouseDown`으로 오는지, 메뉴바가 가져가서 전역 마우스 모니터로만 보이는지를 높이별로 로그로 확인
  - 화면 맨 윗줄은 창 레벨과 관계없이 메뉴바가 클릭을 가져간다(분석에서 확인). 노치 높이 대부분이 메뉴바 높이와 겹치므로, 상당 부분을 전역 모니터로 받아야 할 가능성이 있다(추론)

**3.5-b NotchGeometry·NotchShapePath (TDD, MixerCore)**
- `NotchGeometry`: 카메라 폭 = `auxiliaryTopRightArea.minX - auxiliaryTopLeftArea.maxX`, 높이 = `safeAreaInsets.top`. 좌우 영역이 없거나 높이가 0이면 nil. 접힌 프레임은 카메라 rect보다 양옆 수 pt 넓게, 펼친 프레임은 화면 위 가장자리 중앙(예: 480×220)
- 프레임 좌표를 디스플레이 배율(backingScaleFactor)로 스냅
- `NotchShapePath`: 위 직선 + 양쪽 어깨 곡선 + 아래 둥근 모서리. 직접 설계하며, 크기에 비례해 곡률을 제한
- 테스트: 노치 있는/없는 화면 입력, 좌우 대칭, 스냅 결과, path 경계가 rect 안인지

**3.5-c 패널과 펼침 애니메이션**
- `NotchPanel: NSPanel`
  - `[.borderless, .nonactivatingPanel]`, 배경 투명, 그림자 없음, level `statusBar + 1`
  - `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`
  - `canBecomeKey`는 열린 동안만 true
- `NotchContainerView`: 레이어 마스크 = `CAShapeLayer`(노치 path). `hitTest`는 path 안에서만 응답하고, 안에 `NSHostingView(MixerNotchView)`를 둔다. `acceptsFirstMouse = true`
- 열기: 창 프레임을 펼친 크기로 **한 번만** 설정한 뒤, 마스크 path만 접힌 모양 → 펼친 모양으로 애니메이션(1차는 easeOut 약 0.3초나 `CASpringAnimation`). 콘텐츠는 opacity 페이드
- 닫기: 클릭 통과가 바로 되도록 `ignoresMouseEvents`를 먼저 켜고, path를 접는다. 애니메이션이 끝나면 창 프레임을 다시 줄인다
- 트리거: 노치 클릭(패널 안 + 맨 윗줄 전역 `leftMouseDown/Up` 모니터)으로 토글. 바깥 클릭(전역+로컬 모니터)이나 Esc(로컬 `keyDown`)로 닫는다. 모니터는 열린 동안에만 설치
- 화면 구성 변경(`didChangeScreenParametersNotification`): 기하를 다시 계산한다. 노치 화면이 사라지면(덮개를 닫거나 외장 모니터만 쓸 때) 노치 패널을 숨기고 메뉴바 패널만 쓴다. 화면을 옮길 때는 `orderOut` → 프레임 이동 → `orderFront`
- `MixerNotchView`: 앱 행(아이콘·슬라이더·음소거). 메뉴바 패널 뷰와 공유할 수 있으면 공유한다. 빈 상태는 권한 필요 / 앱 없음으로 구분

**1차에서 하지 않을 것**: 호버 열기, 스크롤 제스처, 가상 노치, 전체화면 숨김, Mission Control 대응, Liquid Glass 배경, 비공개 Space API, 여러 화면(모듈) 구조

**성공 기준**
- 노치를 클릭하면 0.3초 안팎으로 펼쳐지고, 슬라이더 조작이 바로 소리에 반영된다
- 바깥 클릭과 Esc로 닫힌다
- 접힌 상태에서 노치 양옆 메뉴바 항목 클릭이 방해받지 않는다
- 노치 없는 외장 모니터만 연결해도 메뉴바 패널로 동작한다
- 다른 앱 창을 쓰는 중에 노치를 열어도 그 앱이 비활성화되지 않는다

### 4단계 — 안정성
- 슬립 복귀나 장치 재구성 뒤 IO proc이 멈추는 문제: 렌더 카운터로 감시해서 멈추면 1회 재생성, 실패하면 탭 해제(원래 소리로 복귀)
- 다채널 출력(HDMI 등)에서 mixdown 탭 레벨이 1/(채널 쌍 수)로 줄어드는 문제 보정
- 탭 포맷·샘플레이트 변경 리스너 → 재생성
- 비동기 빌드 경합으로 한 앱에 탭이 두 개 생기는 것 방지(세대 번호로 늦게 도착한 빌드 폐기)

**성공 기준**: 슬립/복귀 5회, 출력 장치 전환 10회 뒤에도 소리가 끊기거나 두 번 들리지 않는다

### 5단계 — 선택 기능
- 앱별 출력 장치: aggregate의 main sub-device를 지정한 장치로
- 노치 확장: 호버로 열기(지연 열기, 나가면 닫기, 트래킹 영역 exit 누락 대비 mouseMoved 감시), 위/아래 스크롤로 열고 닫기, 노치 없는 화면의 가상 노치

## 5. 검증 방법

| 대상 | 방법 |
|---|---|
| MixerCore | `swift test` (단위 테스트, NotchGeometry·NotchShapePath 포함) |
| 노치 UI | 3.5단계 성공 기준 수동 체크리스트 + `screencapture`로 접힘/펼침 상태 확인 |
| MixerAudio | 수동 체크리스트 + 로그. HAL은 실제 장치가 필요해서 CI 자동화는 하지 않음 |
| 렌더 성능 | Instruments로 IO 스레드에서 할당이 0인지 확인(4단계) |

## 6. 미리 알고 있는 함정 (분석에서 확인)

1. 출력 버퍼에 이전 데이터가 남아 있음 → 못 채운 프레임은 반드시 0
2. aggregate 입력 버퍼 0번이 탭이 아닐 수 있음(장치 마이크가 먼저 옴)
3. 다채널 출력에서 mixdown 탭 레벨 감소
4. 블록 단위 게인 변경 → 지퍼 노이즈, 블록 안에서 램프 필요
5. 슬립 복귀 뒤 IO proc이 조용히 멈춤
6. `AudioHardwareDestroyProcessTap`이 HAL에서 멈출 수 있음 → 메인 스레드에서 호출 금지
7. DAW·화상회의 앱은 탭하면 무음이나 에코 문제 → 제외 목록(Discord는 ADR 011로 제외하지 않음)
8. ad-hoc 서명으로 다시 빌드하면 TCC 권한이 풀림 → 고정 인증서
9. 자기 자신 PID를 탭하면 피드백 → 제외
10. HAL 리스너 블록은 제거 뒤에도 늦게 불릴 수 있음 → 수명 관리

**노치 UI**
11. 화면 맨 윗줄 클릭은 창 레벨을 올려도 메뉴바가 가져감 → 전역 마우스 모니터로 보완
12. 실루엣보다 큰 창의 투명 영역이 메뉴바 클릭을 막음 → `hitTest`를 path로 제한, 닫히는 동안 `ignoresMouseEvents` 먼저
13. SwiftUI의 완전 투명 영역이나 `allowsHitTesting(false)` 영역은 클릭이 아래 창으로 새어 나감 → 0.01 불투명도로 채움
14. 애니메이션 프레임마다 창 크기를 바꾸면 깜빡임 → 창은 최대 크기로 한 번 잡고 마스크만 애니메이션
15. 보이는 상태로 다른 화면에 `setFrame`하면 창 서버가 늘어나는 애니메이션을 그림 → `orderOut` 후 이동
16. `.nonactivatingPanel`이어도 `canBecomeKey`가 늘 true면 키 포커스를 가져감 → 열린 동안만 true
17. `orderOut` 때 시트 완료 핸들러가 불리지 않음 → 노치 안에서 시트·알림창을 띄우지 않음
18. Space를 전환할 때 노치가 바탕화면과 함께 미끄러지는 현상은 공개 API로 완전히 막을 수 없음 → 1차에서는 수용

## 7. 라이선스 원칙

vorssaint-utils는 GPL-3.0이다. 이 프로젝트는 vorssaint 코드를 복사·번역하지 않고, 분석 문서의 사실(API 호출 순서, 게인 곡선, 보정 규칙, 창 속성 조합, 마스크 애니메이션 방식, 함정)만 참고해 직접 작성한다. 노치 path도 직접 설계한다. 구현할 때 vorssaint 소스를 옆에 펴 놓고 옮겨 적지 않는다.

## 8. 열린 결정

- 이 저장소의 라이선스와 GitHub 공개 여부(공개한다면 MIT 등)
- 앱 이름(가칭 `mixer` / `Mixer.app`)
- ~~부스트 기능을 MVP에 넣을지~~ → MVP에 포함(ADR 012)
- 노치 패널 레이아웃: 앱별 가로 슬라이더 목록(메뉴바 패널과 공유하기 쉬움)인지, vorssaint처럼 세로 페이더 레일인지(현재 계획: 가로 슬라이더 목록)
