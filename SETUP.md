# 프로젝트 환경 설정 가이드

## 다른 PC에서 이 레포를 사용하기 위한 가이드

### 1단계: Git Clone
```bash
git clone https://github.com/py-pixel-9/my-first-video.git
cd my-first-video
```

### 2단계: Node.js 설치 확인
```bash
node --version   # v20 이상 필요
npm --version    # v10 이상 필요
```
설치 안 되어 있으면: https://nodejs.org 에서 LTS 버전 다운로드

### 3단계: npm 패키지 설치
```bash
npm install
```

### 4단계: Remotion 테스트
```bash
npx remotion studio
# 브라우저에서 http://localhost:3000 열림
```

### 5단계: Claude Code Skills
`.claude/skills/` 폴더는 git에 포함되어 있으므로 pull하면 자동으로 받아집니다.
- `remotion/` - Remotion 영상 제작 베스트 프랙티스 (30+ 규칙)
- `trading-video/` - 트레이딩 영상 제작 가이드

### 6단계: Remotion 영상 렌더링
```bash
# 특정 컴포지션 렌더링
npx remotion render src/index.ts DescendingChannelBreakout out/video.mp4

# 스틸 이미지 (썸네일)
npx remotion still src/index.ts DescendingChannelBreakout out/thumbnail.png
```

## 프로젝트 구조
```
my-first-video/
├── .claude/skills/          ← Claude Code Skills (자동 인식)
│   ├── remotion/            ← Remotion 베스트 프랙티스
│   └── trading-video/       ← 트레이딩 영상 제작 가이드
├── src/                     ← Remotion 영상 소스코드
│   ├── CandleChart/         ← 캔들차트 애니메이션
│   └── HelloWorld/          ← 기본 템플릿
├── mt4-ea/                  ← MT4 Expert Advisors
│   ├── EA_Gold_Algo_RE.mq4      ← Gold Breakout v1
│   ├── EA_Gold_Algo_RE_v2.mq4   ← Gold Breakout v2 (풀기능)
│   ├── SMC_Breakout_EA.mq4      ← SMC 돌파 EA
│   ├── GridTrader.mq4            ← 그리드 트레이더
│   └── EquityManager.mq4        ← 자금관리 EA
├── mt4-indicators/          ← MT4 인디케이터
├── package.json             ← Remotion 의존성
└── remotion.config.ts       ← Remotion 설정
```
