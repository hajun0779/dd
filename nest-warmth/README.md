# 둥지 온기 (Nest Warmth) — 바로 나가기 아깝게 만드는 장치

## 한 줄 요약

접속해 있는 동안 둥지가 데워져 **거위 수입 배율이 최대 x1.80까지** 오르고,
그동안 **3~6분마다 내 기지 위로 황금알이 떨어진다.**
나가면 배율은 식고, 황금알 시계는 처음으로 되돌아간다.

---

## 왜 이게 "나가기 아깝게" 만드는가

기존 게임에는 *다시 오게* 만드는 장치(일일 룰렛, 오프라인 수입)는 있었지만,
*지금 앉은 자리에서 못 일어나게* 만드는 장치가 없었습니다.
이 시스템은 나가는 순간 눈에 보이는 손실을 세 겹으로 만듭니다.

| 겹 | 나갈 때 잃는 것 | 화면에서 보이는 방식 |
|---|---|---|
| **쌓은 배율** | 50분 걸려 올린 x1.80 수입 배율 | 왼쪽 칩에 현재 단계와 배율이 항상 떠 있음 |
| **눈앞의 보상** | 몇 분 뒤 떨어질 황금알 | 칩 아래 줄이 `다음 황금알 2:41` 로 계속 카운트다운 |
| **다음 단계** | 조금만 더 있으면 오르는 승급 | 칩의 진행 막대가 다음 단계까지 얼마나 남았는지 보여 줌 |

핵심은 **"다음 것이 언제인지 항상 보인다"** 입니다.
막연히 "있으면 좋은 일이 생긴다" 가 아니라 `2:41` 이라는 숫자가 떠 있으면
그 2분 41초를 두고 나가는 게 손해로 느껴집니다.

### 방치 보상이 되지 않게 한 부분

체류 보상은 방치 보상으로 변질되기 쉬워서 두 가지 안전장치를 넣었습니다.

- **황금알은 직접 걸어가서 주워야 합니다.** 기지 위에 떠 있고 90초 안에 안 주우면 사라집니다.
- **5분 동안 6스터드도 안 움직이면 온기가 멈춥니다.** 깎지는 않습니다. 움직이면 즉시 다시 차오르고,
  방치 중에는 다음 황금알 시계도 같이 멈춰서 자리를 비운 사이에 떨어져 버리지 않습니다.

### 잠깐 튕긴 사람을 벌하지 않는 부분

나간 뒤 **5분 동안은 온기가 그대로 유지됩니다.** 서버 이동이나 순간적인 접속 끊김을
손실로 만들면 시스템이 미움만 받습니다. 5분이 지나야 분당 4씩 식기 시작하므로
가득 찬 온기는 약 30분이면 바닥이 됩니다.

돌아오면 상태에 맞는 인사가 뜹니다.
`둥지가 아직 따뜻합니다 — 후끈한 둥지 (수입 x1.50)` 는 그 자체로 재접속을 앞당기는 보상입니다.

---

## 단계표

| 단계 | 필요 온기 | 도달까지 | 수입 배율 |
|---|---|---|---|
| 차가운 둥지 | 0 | — | x1.00 |
| 불씨 | 10 | 5분 | x1.12 |
| 따뜻한 둥지 | 28 | 14분 | x1.28 |
| 후끈한 둥지 | 55 | 27분 30초 | x1.50 |
| 황금 둥지 | 100 | 50분 | x1.80 |

앞 단계를 촘촘하게 잡은 이유는, 접속하자마자 한 번은 올라야 "오르는 것" 이라는 걸 알기 때문입니다.
마지막 단계는 50분이라 한 판에 한 번 볼까 말까 한 자리에 있습니다.

## 황금알

- 첫 알은 접속 후 **3분** — 습관이 붙기 전에 한 번은 받아 봐야 합니다.
- 이후 **6분 간격**이되 단계가 오를수록 30초씩 짧아져, 황금 둥지에서는 **4분 간격**이 됩니다.
  오래 앉아 있을수록 보상이 촘촘해지는 쪽이 앉아 있게 만듭니다.
- 떨어지기 **30초 전에 예고**가 뜹니다. 이 30초가 "지금 나가면 손해" 를 만드는 구간입니다.
- 보상은 `단계별 고정액` 과 `현재 초당 수입 × 단계별 초수` 중 **큰 쪽**입니다.
  뒤쪽 덕분에 환생을 아무리 해도 보상이 초라해지지 않습니다 — 황금 둥지에서는 **9분치 수입**이 한 번에 들어옵니다.
- 단계에 따라 확률적으로 **알**(최대 28%)이나 **룰렛 기회**(최대 18%)가 덤으로 붙습니다.
  가방이 가득 차 알을 못 받으면 현금을 50% 더 얹어 줍니다.
- **황금 둥지 단계의 알은 서버 전체에 알립니다.** 남의 황금알이 부러워야 나도 남습니다.

---

## 설치 방법 (Roblox Studio)

### 새로 넣는 파일 4개

| 파일 | 넣을 위치 | 클래스 |
|---|---|---|
| `ReplicatedStorage/Shared/Config/WarmthConfig.lua` | `ReplicatedStorage > Shared > Config` | **ModuleScript** |
| `ServerScriptService/Server/Services/WarmthService.lua` | `ServerScriptService > Server > Services` | **ModuleScript** |
| `ServerScriptService/WarmthBootstrap.lua` | `ServerScriptService` 바로 아래 | **Script** |
| `StarterPlayer/StarterPlayerScripts/WarmthClient.lua` | `StarterPlayer > StarterPlayerScripts` | **LocalScript** |

이름은 `.lua` 를 뗀 이름 그대로 씁니다 (`WarmthConfig`, `WarmthService`, `WarmthBootstrap`, `WarmthClient`).

`WarmthBootstrap` 은 룰렛과 같은 방식입니다 — 기존 `Server` 메인 스크립트를 건드리지 않고
서비스를 시작합니다. `Server.lua` 는 수정할 필요가 없습니다.

### 덮어쓰는 기존 파일 4개

| 파일 | 바뀐 내용 |
|---|---|
| `ReplicatedStorage/Shared/Net/Remotes.lua` | `WarmthSync` / `WarmthDrop` / `WarmthGetState` 세 줄 추가 |
| `ReplicatedStorage/Shared/Locale/Strings/ko.lua` | `warmth_*` 문자열 추가 |
| `ReplicatedStorage/Shared/Locale/Strings/en.lua` | 같은 키의 영어 문장 추가 |
| `ServerScriptService/Server/Services/IncomeService.lua` | 수입 배율에 온기 배율 한 항 추가 |

`IncomeService` 수정은 **모듈이 없으면 배율 1로 넘어가도록** 만들어 두었습니다.
`WarmthService` 를 빼도 수입 계산은 그대로 돕니다.

### 필요 없는 것

- 맵에 새로 놓아야 하는 파트: **없음**. 황금알은 서버가 기지 `SpawnPart` 위에 만들어 놓고,
  주우면 지웁니다. `SpawnPart` 가 없는 기지는 모델 중심을 씁니다.
- 새 아틀라스/파티클 업로드: **없음**. 화면에 쓰는 스프라이트는 전부 기존 `RadAtlas` 것이고,
  파티클도 기존 `ParticleAssets` 의 `Spark` 를 씁니다.
- 새 개발자 상품: **없음**.

---

## 튜닝

숫자는 전부 `WarmthConfig.lua` 한 곳에 있습니다. 자주 만질 만한 것들:

```lua
WarmthConfig.FillPerMinute = 2.0      -- 온기가 차는 속도 (0→100 까지 50분)
WarmthConfig.GraceSeconds  = 5 * 60   -- 나간 뒤 온기가 그대로 유지되는 시간
WarmthConfig.DecayPerMinute = 4       -- 그 뒤 분당 식는 양

WarmthConfig.Tiers[n].Multiplier      -- 단계별 수입 배율
WarmthConfig.Drop.FirstSeconds  = 180 -- 첫 황금알까지
WarmthConfig.Drop.IntervalSeconds = 360
WarmthConfig.Drop.LifetimeSeconds = 90  -- 안 주우면 사라지는 시간
WarmthConfig.Drop.SecondsOfIncome     -- 단계별 "몇 초치 수입" 을 줄지
WarmthConfig.IdleSeconds = 300        -- 방치로 보는 시간
```

### 먼저 확인해 볼 것 (밸런스)

최고 단계 **x1.80 은 작은 수가 아닙니다.** 환생 10회(x4.5), VIP(x1.5), 월드 이벤트와
전부 곱해지므로 최종 배율이 예상보다 커집니다. 처음에는 **x1.5 정도로 낮춰서 시작**하고,
황금알 쪽(`SecondsOfIncome`)을 올려 체감을 채우는 편이 경제에 덜 부담이 됩니다.

황금알 보상이 초당 수입에 비례하므로, 인플레이션은 배율보다 이쪽이 먼저 눈에 띕니다.
`SecondsOfIncome` 의 마지막 값(540초 = 9분치)부터 만져 보세요.

---

## 저장 데이터

프로필에 `data.warmth` 하나가 생깁니다. 기존 데이터에 없으면 서비스가 만들어 넣으므로
마이그레이션은 필요 없습니다.

```lua
data.warmth = {
    value = 0,          -- 온기 0~100
    seenAt = 0,         -- 마지막으로 확인된 시각 (식힘 계산용, 매 초 갱신)
    eggsClaimed = 0,    -- 지금까지 주운 황금알 수
    totalSeconds = 0,   -- 온기가 차오른 총 시간
    bestValue = 0,      -- 최고 기록
}
```

황금알 시계(`nextDropAt`)는 **저장하지 않습니다.** 나가면 처음부터 다시 3분입니다.
이게 이 시스템에서 가장 중요한 한 줄입니다 — 시계를 저장하면
"나갔다 들어와서 받으면 되지" 가 되어 버려 앉아 있을 이유가 사라집니다.
