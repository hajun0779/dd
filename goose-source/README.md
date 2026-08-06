# 이번 수정 (연출 / 2층 / 알 구분 / 글씨 / 밝기)

수정하거나 새로 만든 파일만 담았습니다. 폴더 구조는 rbxl 경로 그대로라
같은 위치에 덮어쓰면 됩니다.

---

## 1. 타코 파티 노래

`rbxassetid://142376088` 로 고정했습니다.

`WorldConfig.Events.TacoSongId` 하나만 보면 됩니다. 맵의 `ServerStorage.Events.TacoSong`
에 다른 Sound 가 들어 있어도 **이 ID 가 이깁니다.** 맵마다 다른 노래가 나오면
"그 노래" 가 아니게 되니까요. 아예 Sound 를 안 넣어 뒀어도 이 ID 로 하나 만들어 재생합니다.
비워 두면(`""`) 예전처럼 맵에 있는 Sound 를 씁니다.

---

## 2. 관리자 전용 연출 10종

`ShowConfig` / `ShowService` / `ShowClient` 를 새로 만들었습니다.
관리자 패널에 **연출 실행** / **연출 중지** 명령이 생깁니다.

| ID | 이름 | 주력 | 특징 |
|---|---|---|---|
| `Aurora` | 오로라 | 하늘 | 밤하늘 + 흐르는 색 커튼, 카메라 안 흔듦 |
| `Storm` | 폭풍우 | 화면 | 비 + 불규칙한 번개(꺾인 선), 채도 -0.4 |
| `Meteor` | 유성우 | 맵 | **진짜 파트가 떨어짐**, 착탄 근처만 흔들림 |
| `Sakura` | 벚꽃 바람 | 화면 | 꽃잎이 회전하며 흩날림, 카메라 정지 |
| `Disco` | 디스코 나이트 | 보정 | 화면 색이 계속 순환 + 회전 스포트라이트 |
| `Frost` | 혹한 | 화면 | 가장자리부터 성에가 자람, 가운데는 비움 |
| `Rift` | 대균열 | 맵 | 바닥이 갈라지고 불티, 낮은 진동 지속 |
| `GoldRain` | 황금비 | 화면 | 금화가 뒤집히며 떨어짐 |
| `Nebula` | 성운 | 하늘 | 별이 화면 중심으로 아주 느리게 회전 |
| `Taco` | 타코 파티 | 보정 | 색종이 + 위 노래 |

### 왜 전에는 다 비슷해 보였나

이전 연출은 전부 같은 곳만 건드렸습니다 — 하늘 색 바꾸고 화면 번쩍.
그래서 색만 다른 같은 연출이 여러 개였습니다.

이번에는 연출 하나를 **다섯 축**으로 쪼갰고, 열 가지가 서로 다른 축을 주력으로 씁니다.

```
Sky     하늘·안개·밝기        느리고 넓게 바뀌는 것
Grade   블룸·대비·채도·틴트   화면의 "재질"
Camera  흔들림·펀치·기울기    몸으로 느끼는 것
Screen  화면에 그리는 것      눈앞을 지나가는 것
World   맵에 실제로 놓는 것   가서 볼 수 있는 것
```

`ShowClient` 의 그리는 방법도 열 가지가 전부 다릅니다(커튼 / 번개 / 줄기 / 꽃잎 /
디스코 / 성에 / 맥동 / 금화 / 별 / 색종이). 같은 방식으로 그리면 결국 색만 바뀝니다.

### 쓰는 법

관리자 패널 → **연출 실행** → `연출 ID` 에 위 표의 ID 를 칩니다(대소문자 무관).
`길이(초)` 를 0 으로 두면 연출마다 정해진 길이를 씁니다.

새로 올려야 할 이미지·파티클·모델은 **없습니다.** 노래를 넣고 싶으면
`ShowConfig.List` 의 각 항목 `Sound.Id` 에 ID 를 적으면 됩니다(비어 있으면 무음).

---

## 3. 밝기

기준값을 `ShowConfig.BaseLighting` 한 곳에 모았고, 서버가 뜰 때 `WorldService` 가
이 값으로 덮어씁니다. place 에 저장된 조명이 원인이었기 때문에, 연출이 끝나도
**저장값이 아니라 이 기준값으로** 돌아옵니다.

```lua
Brightness = 1.35            -- 기본 place 값보다 확실히 낮게
ExposureCompensation = -0.15
EnvironmentDiffuseScale = 0.55
```

같이 낮춘 것:

- `BallEventConfig.Lighting.Brightness` 1.6 → **1.0** (+ 노출 -0.2)
- `BallEventConfig.Grade.Bloom` 0.7 → **0.34** — 블룸이 세면 밝은 곳이 전부 하얗게 뭉갭니다

더 어둡게/밝게 하려면 `ShowConfig.BaseLighting.Brightness` 하나만 만지면 됩니다.

---

## 4. 2층

### 흐름

1. 도감을 **30개**(거위 + 알 합산) 채운다
2. 기지 안의 **`Two` 파트가 투명해지고 통과 가능**해진다
3. 그 파트 위에 빌보드 표지가 뜨고, **내 캐릭터에서 그쪽으로 빛줄기**가 이어진다 (60초)
4. 올라가면 **환영 카드** + 슬롯 8칸 추가 안내
5. 슬롯이 **8 → 16칸**이 된다

### 맵에 준비할 것

- 기지 모델 안 어딘가에 **`Two`** 라는 파트(또는 모델). 2층 입구를 막는 판입니다.
  모델이면 그 안의 파트를 전부 치웁니다.
- `Slot` 폴더에 **9~16번** 슬롯을 2층에 만들어 둡니다. 구조는 1~8번과 같습니다
  (`Slot > 9 > Handle`). 안 만들면 그 번호는 그냥 없는 것으로 칩니다.

### 슬롯 잠금

`GameConfig.Base` 가 `SlotCount = 16`, `GroundSlotCount = 8` 로 나뉘었습니다.
잠금 판정은 **기지 모델에 붙는 속성 하나**(`FloorTwo`)로만 합니다.
`BaseService.getHandle` 이 그 속성을 보고 9번 이상을 막으므로,
수입·설치·판매·프롬프트가 전부 자동으로 따라옵니다. 서비스끼리 서로를 부르지 않습니다.

접속 순서도 맞춰 뒀습니다 — 기지를 받는 즉시(기다리지 않고) 속성을 붙입니다.
안 그러면 `EggService` 가 저장된 슬롯을 다시 세울 때 2층 거위가 사라진 것처럼 보입니다.

### 환영 판정

클라이언트가 "올라갔다" 고 알리는 방식은 쓰지 않았습니다. 안 올라가고도 보낼 수 있어서요.
서버가 `Two` 파트 윗면 + 8스터드 높이와 수평 거리 90스터드로 직접 잽니다. 한 번만 뜹니다.

### 관리자 명령

**2층 열기/닫기** — 도감 조건과 상관없이 그 사람의 2층을 여닫습니다(테스트용).

---

## 5. 도감 퀘스트 바

도감 창 위에 줄이 하나 생깁니다.

```
🏠 도감 30개 모으기 → 2층 해금   [▓▓▓▓▓▓░░░░]   18 / 30
```

30개를 채우면 줄 전체가 **초록**으로 바뀌고 숫자 자리에 **DONE!** 이 들어섭니다.

세는 값은 **서버가 보내 준 것**을 씁니다. 화면이 따로 세면
`30 / 30` 인데 2층은 안 열리는 일이 생깁니다.

---

## 6. 글씨가 안 보이던 문제

원인은 폰트입니다. `FredokaOne` 같은 장식체에는 **한글 글리프가 없습니다.**
그 폰트로 한국어를 쓰면 글자가 통째로 사라지거나 네모로 나옵니다.

전에는 창 제목만 따로 바꿔 놨는데, 숫자 폰트(`Theme.Font.Number`)로 찍는 곳,
컨트롤러가 폰트를 직접 지정한 곳은 그대로 깨져 있었습니다.

**고친 방식**

- `Theme.resolveFont(font, locale)` — 쓰고 싶은 폰트와 그 언어에서 실제로 그려지는
  폰트를 나눕니다. ko/ja/zh/th 에서는 장식체를 CJK 가 되는 폰트로 바꿔 끼웁니다.
- `UI.text` 가 **전부** 이 함수를 지나갑니다. 게임의 거의 모든 글씨가 여기를 통하므로
  한 곳만 고치면 전부 고쳐집니다.
- 언어를 바꾸면 **이미 화면에 붙어 있는 글씨까지** 같이 갈아 끼웁니다
  (약한 참조로 들고 있어서 사라진 라벨은 알아서 정리됩니다).

앞으로 새 폰트를 쓰고 싶으면 `Theme.FontFallback` 에 대응 폰트만 한 줄 적으면 됩니다.

---

## 7. 알 구분

알이 스물여섯 종인데 화면에서는 전부 같은 아이콘 하나였습니다.
색도 **등급**(Glow)으로만 칠해서, 실제로 눈에 보이는 건 두어 가지뿐이었습니다.

**두 겹으로 그립니다.**

| 겹 | 무엇 | 왜 |
|---|---|---|
| 껍데기 | `icon_egg` 를 그 알의 `Color` 로 | 멀리서도 색으로 갈림 |
| 무늬 | 그 알의 `Glyph` 를 `Accent` 로 | 가까이서 기호로 확정 |

색만으로는 스물여섯을 못 나눕니다(비슷한 파랑이 넷입니다). 기호만으로도 안 됩니다
(작은 슬롯에서 안 읽힙니다). 둘을 같이 써야 한 눈에 갈립니다.

기호는 전부 **기존 RadAtlas** 스프라이트입니다. 새로 올릴 이미지는 없습니다.

```
서리 ❄  업화 🔥  시간 ⏱  왕실 🏆  혼돈 ⚠  창세 ↻  용 💪  꿈 ♪ ...
```

적용된 곳: 상점 카드 / 가방 슬롯 / 드래그 고스트 / 도감 / 룰렛 보상.
가방에서는 **등급 색 대신 알 색**을 씁니다 — 등급은 테두리(rarityFrame)가 이미 말하고 있습니다.

**3D 모델**도 같이 바꿨습니다. 예전에는 어느 알이든 점 다섯 개였는데,
이제 종류마다 새기는 방식이 다릅니다: 점 / 띠 / 고리 / 파편 / 소용돌이 / 왕관.
`EggConfig` 의 `Pattern` 값으로 정합니다.

---

## 설치

### 새로 넣는 파일

| 파일 | 위치 | 클래스 |
|---|---|---|
| `Config/ShowConfig` | `ReplicatedStorage > Shared > Config` | ModuleScript |
| `Config/FloorConfig` | `ReplicatedStorage > Shared > Config` | ModuleScript |
| `UI/EggVisual` | `ReplicatedStorage > Shared > UI` | ModuleScript |
| `Services/ShowService` | `ServerScriptService > Server > Services` | ModuleScript |
| `Services/FloorService` | `ServerScriptService > Server > Services` | ModuleScript |
| `ShowBootstrap` | `ServerScriptService` 바로 아래 | **Script** |
| `FloorBootstrap` | `ServerScriptService` 바로 아래 | **Script** |
| `ShowClient` | `StarterPlayer > StarterPlayerScripts` | **LocalScript** |
| `FloorClient` | `StarterPlayer > StarterPlayerScripts` | **LocalScript** |

Bootstrap 은 룰렛과 같은 방식입니다. `Server.lua` 는 건드리지 않습니다.

### 덮어쓰는 파일

`Remotes` · `Theme` · `UIBuilder` · `GameConfig` · `WorldConfig` · `BallEventConfig` ·
`AdminConfig` · `EggConfig` · `ModelFactory` · `ko.lua` · `en.lua` ·
`BaseService` · `IndexService` · `WorldService` · `IncomeService` · `AdminService` ·
`IndexController` · `InventoryController` · `ShopController` · `MusicController` · `EggWheelClient`

`AdminService` 의 연출/2층 명령은 **모듈이 없으면 "미구현" 으로 답하도록** 해 뒀습니다.
`ShowService` 나 `FloorService` 를 빼도 관리자 패널 자체는 그대로 열립니다.

---

## 확인한 것 / 못 한 것

- 전체 105개 스크립트를 Luau 컴파일러로 파싱 검증했습니다 (35 KLOC, 오류 0).
- 정적 분석기 경고도 새로 추가된 것은 없습니다.
- **Studio 실행 테스트는 못 했습니다.** 로블록스 런타임이 없어서 검증한 건 문법·정적 분석까지입니다.
  특히 맵에 실제로 놓아야 하는 것(`Two` 파트, 9~16번 슬롯)은 직접 확인이 필요합니다.
- 거위 VFX(`GooseVfxConfig`)는 이번에 손대지 않았습니다. 32종이라 범위가 따로입니다 —
  필요하면 이어서 하겠습니다.
