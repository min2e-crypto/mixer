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
