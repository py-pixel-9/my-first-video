# SMC Easy Signal Indicator - 사용 설명서

## 📌 개요
**SMC (Smart Money Concepts) Easy Signal** 인디케이터는 BOS(Break of Structure)와 CHoCH(Change of Character)를 자동으로 감지하여 차트에 표시하는 도구입니다.

---

## 🎯 주요 기능

### 1. **BOS (Break of Structure)** - 구조 돌파
- 현재 추세가 계속될 때 이전 고점/저점을 돌파하는 시점 감지
- **매수 BOS**: 상승 추세 중 이전 고점 돌파
- **매도 BOS**: 하락 추세 중 이전 저점 돌파

### 2. **CHoCH (Change of Character)** - 추세 전환
- 추세가 반전될 때의 신호 감지
- **매수 CHoCH**: 하락 추세에서 상승 추세로 전환
- **매도 CHoCH**: 상승 추세에서 하락 추세로 전환

### 3. **리페인팅 방지 (Non-Repainting)**
- **임시 표시**: 가격이 구간을 돌파하면 실시간으로 표시
- **자동 삭제**: 가격이 다시 되돌아오면 표시 제거
- **확정 표시**: 캔들이 종가로 확정되면 영구 표시

---

## 🔧 설정 파라미터

### 📊 Market Structure Time-Horizon (25)
- 스윙 고점/저점을 찾기 위한 캔들 개수
- **높은 값**: 더 큰 구조 변화만 감지 (장기)
- **낮은 값**: 작은 구조 변화도 감지 (단기)

### ✅ BOS Confirmation Type
- **CandleClose**: 캔들 종가 기준으로 확정 (기본값, 권장)
- 추후 다른 확정 방식 추가 가능

### 🔔 알림 설정
- **PC Pop-up/Sound alert**: PC 알림창 표시
- **Push Notification**: 모바일 푸시 알림
- **Email Alert**: 이메일 알림

### 🎨 외관 설정
- **Bullish Color (Aqua)**: 매수 신호 색상
- **Bearish Color (Magenta)**: 매도 신호 색상
- **Arrow Size (3)**: 화살표 크기
- **Font Size (12)**: 텍스트 크기

---

## 💻 코드 구조 설명

### 주요 배열 구조

```mql4
// 스윙 포인트 저장
double swingHighPrices[];  // 스윙 고점 가격
int swingHighBars[];       // 스윙 고점 위치 (바 인덱스)
double swingLowPrices[];   // 스윙 저점 가격
int swingLowBars[];        // 스윙 저점 위치

// BOS/CHoCH 구조 저장
double tempPrices[];       // 구조 돌파 가격
int tempBars[];            // 구조 발생 위치
string tempTypes[];        // "BOS" 또는 "CHoCH"
bool tempIsBuy[];          // true = 매수, false = 매도
bool tempConfirmed[];      // true = 확정, false = 임시
```

### 핵심 함수 설명

#### 1. **FindSwingPoints(int lookback)**
```mql4
// 스윙 고점/저점 찾기
// lookback = 양쪽으로 확인할 캔들 개수
// 예: lookback=25면 좌우 25개 캔들을 비교
```
**로직**:
- 중심 캔들이 좌우 25개 캔들보다 높으면 → 스윙 고점
- 중심 캔들이 좌우 25개 캔들보다 낮으면 → 스윙 저점

#### 2. **DetectStructureBreaks()**
```mql4
// BOS/CHoCH 감지 로직
```

**3단계 프로세스**:

**[Step 1] 임시 구조 검증**
- 확정되지 않은 구조를 계속 검증
- 매수 신호: 가격이 레벨 아래로 떨어지면 → 삭제
- 매도 신호: 가격이 레벨 위로 올라가면 → 삭제
- 캔들 종가가 레벨을 넘으면 → 확정

**[Step 2] 과거 데이터 스캔 (500개 캔들)**
- 차트에 표시되지 않은 과거 BOS/CHoCH 찾기
- 각 스윙 고점/저점을 돌파한 시점 확인
- 추세 분석하여 BOS인지 CHoCH인지 판단

**[Step 3] 실시간 감지 (현재 캔들)**
- 현재 가격이 이전 구조를 돌파하는지 실시간 체크
- 알림 발송 (중복 방지)

#### 3. **AddStructure() / RemoveStructure()**
```mql4
// 배열에 구조 추가/제거
// MQL4는 구조체를 지원하지 않아 여러 배열을 동시에 관리
```

#### 4. **DrawStructures()**
```mql4
// 차트에 그리기
// - 화살표 (▲ 매수, ▼ 매도)
// - 텍스트 라벨 ("BOS" 또는 "CHoCH")
// - 수평선 (구조 가격 레벨)
```

---

## 🎮 작동 원리

### 예시: 매수 BOS 발생 과정

```
1. 스윙 고점 감지
   고점A (4950) ← 25개 캔들 중 최고점

2. 가격 상승
   현재 가격: 4960 (고점A 돌파!)
   → 임시 BOS 표시 생성 (확정 안됨)

3-a. 시나리오 1: 가격이 다시 하락
   현재 가격: 4945 (고점A 아래로 떨어짐)
   → BOS 표시 삭제 (잘못된 신호)

3-b. 시나리오 2: 캔들 종가 확정
   종가: 4955 (고점A 위에서 마감)
   → BOS 확정! 영구 표시
   → 알림 발송
```

### CHoCH vs BOS 구분

```
상승 추세 중:
- 이전 고점 돌파 → BOS (추세 지속)
- 이전 저점 하향 돌파 → CHoCH (추세 전환)

하락 추세 중:
- 이전 저점 돌파 → BOS (추세 지속)
- 이전 고점 상향 돌파 → CHoCH (추세 전환)
```

---

## 🚀 설치 방법

1. **파일 복사**
   ```
   SMC_Easy_Signal_Official.ex4
   → MT4/MQL4/Indicators/ 폴더에 복사
   ```

2. **MT4 재시작** 또는 **Navigator 새로고침**

3. **차트에 적용**
   - Navigator → Indicators → Custom
   → SMC_Easy_Signal_Official 더블클릭

---

## ⚙️ 권장 설정

### 📈 스캘핑 / 단기 트레이딩
```
Market Structure Time-Horizon: 15-20
How many latest zones: 3-5
```

### 📊 스윙 트레이딩 / 중기
```
Market Structure Time-Horizon: 25-30 (기본값)
How many latest zones: 2-3
```

### 📉 포지션 트레이딩 / 장기
```
Market Structure Time-Horizon: 40-50
How many latest zones: 1-2
```

---

## ⚠️ 주의사항

1. **과거 데이터 스캔**
   - 최대 500개 캔들까지만 과거 데이터 스캔
   - 너무 오래된 데이터는 표시되지 않음

2. **중복 신호 방지**
   - 같은 가격 레벨에서 5초 이내 중복 알림 차단

3. **MQL4 제약사항**
   - 구조체(struct) 미지원 → 배열로 대체
   - 실시간 업데이트로 인한 CPU 사용량 증가 가능

4. **최적화**
   - Time-Horizon 값이 너무 작으면 → 잘못된 신호 증가
   - Time-Horizon 값이 너무 크면 → 신호 지연 발생

---

## 🐛 문제 해결

### 신호가 안 보여요
→ `How many latest zones` 값을 늘려보세요 (5-10)

### 신호가 너무 많아요
→ `Market Structure Time-Horizon` 값을 늘려보세요 (35-50)

### 알림이 안 와요
→ MT4 설정 → 옵션 → 알림 탭 확인

---

## 📝 버전 정보

**Version 1.00**
- BOS/CHoCH 자동 감지
- 리페인팅 방지 로직
- 과거 데이터 스캔 (500 캔들)
- 실시간 알림 시스템
- 사용자 정의 색상/크기

---

## 👨‍💻 개발 노트

이 인디케이터는 MQL4 문법 제약으로 인해:
- 구조체 대신 **병렬 배열** 사용
- 각 속성(가격, 바, 타입, 방향, 확정 여부)을 별도 배열로 관리
- 배열 인덱스로 관계 유지

성능 최적화:
- 확정된 신호만 매 틱마다 다시 그리기
- 오래된 객체 자동 삭제
- 중복 검사로 불필요한 계산 방지

---

**개발: Claude (Anthropic)**
**날짜: 2026-02-08**
