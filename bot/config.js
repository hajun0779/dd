import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// ===========================================================================
//  봇 토큰
//
//  아래 따옴표 사이에 디스코드 봇 토큰을 붙여넣으면 바로 실행됩니다.
//  (.env 파일을 만들어서 넣어도 되고, 그쪽이 우선합니다.)
//
//  주의: 여기에 토큰을 넣은 뒤에는 이 파일을 깃허브에 올리거나 남에게
//  보내지 마세요. 토큰이 새면 봇을 남이 조종할 수 있습니다.
//  토큰이 샜다면 디스코드 개발자 포털에서 Reset Token 을 눌러 주세요.
// ===========================================================================
const BOT_TOKEN = '';

// 이 파일이 있는 폴더. 어느 위치에서 실행해도 경로가 어긋나지 않도록 씁니다.
const BASE_DIR = path.dirname(fileURLToPath(import.meta.url));

/** 같은 폴더의 .env 파일을 읽습니다. 이미 설정된 환경 변수는 덮어쓰지 않습니다. */
function loadEnvFile() {
  const envPath = path.join(BASE_DIR, '.env');

  let raw;
  try {
    raw = fs.readFileSync(envPath, 'utf8');
  } catch {
    return; // .env 가 없으면 그냥 넘어갑니다.
  }

  for (const line of raw.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (trimmed.length === 0 || trimmed.startsWith('#')) continue;

    const match = trimmed.match(/^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/);
    if (!match) continue;

    const [, key, rawValue] = match;
    // 이미 값이 들어 있는 환경 변수만 그대로 둡니다.
    // 빈 문자열로 설정된 변수는 없는 것으로 보고 .env 값을 씁니다.
    if (typeof process.env[key] === 'string' && process.env[key].trim().length > 0) continue;

    let value = rawValue.trim();
    if (
      (value.startsWith('"') && value.endsWith('"') && value.length >= 2) ||
      (value.startsWith("'") && value.endsWith("'") && value.length >= 2)
    ) {
      value = value.slice(1, -1);
    } else {
      // 따옴표가 없으면 줄 뒤쪽 주석을 잘라냅니다.
      const comment = value.indexOf(' #');
      if (comment !== -1) value = value.slice(0, comment).trim();
    }

    process.env[key] = value;
  }
}

loadEnvFile();

function str(name, fallback) {
  const value = process.env[name];
  if (value === undefined || value === null || value.trim() === '') return fallback;
  return value.trim();
}

function int(name, fallback) {
  const value = str(name, null);
  if (value === null) return fallback;
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export const config = {
  // .env 의 DISCORD_TOKEN 이 있으면 그걸 쓰고, 없으면 위의 BOT_TOKEN 을 씁니다.
  token: str('DISCORD_TOKEN', BOT_TOKEN.trim().length > 0 ? BOT_TOKEN.trim() : null),

  // 로블록스 인증
  verifyPanelChannelId: str('VERIFY_PANEL_CHANNEL_ID', '1418823709027733517'),
  verifiedRoleId: str('VERIFIED_ROLE_ID', '1418823708247720077'),
  nicknamePrefix: str('NICKNAME_PREFIX', '예천군 시민ㅣ'),
  verifyCodeTtlMinutes: int('VERIFY_CODE_TTL_MINUTES', 30),
  // 인증 패널 안에 넣을 배너 이미지 주소. 비워 두면 이미지 없이 나갑니다.
  verifyPanelImageUrl: str('VERIFY_PANEL_IMAGE_URL', null),

  // 티켓
  ticketPanelChannelId: str('TICKET_PANEL_CHANNEL_ID', '1535140042652254219'),
  ticketStaffRoleId: str('TICKET_STAFF_ROLE_ID', '1535140290581635162'),
  ticketTranscriptChannelId: str('TICKET_TRANSCRIPT_CHANNEL_ID', '1535140618626670623'),
  ticketCategoryId: str('TICKET_CATEGORY_ID', '1535141065160658944'),
  ticketDeleteDelaySeconds: int('TICKET_DELETE_DELAY_SECONDS', 5),
  // 티켓 패널 안에 넣을 배너 이미지 주소. 비워 두면 이미지 없이 나갑니다.
  ticketPanelImageUrl: str('TICKET_PANEL_IMAGE_URL', null),

  // 저장소. 실행 위치와 상관없이 이 폴더의 data/store.json 을 씁니다.
  dataFile: str('DATA_FILE', path.join(BASE_DIR, 'data', 'store.json')),

  // 기록(HTML) 생성 제한
  transcript: {
    maxMessages: int('TRANSCRIPT_MAX_MESSAGES', 5000),
    // 개별 첨부파일을 HTML 안에 직접 포함시킬 최대 크기 (바이트)
    inlineMaxBytes: int('TRANSCRIPT_INLINE_MAX_BYTES', 2 * 1024 * 1024),
    // HTML 안에 포함시킬 미디어 총량 상한 (바이트)
    inlineTotalBytes: int('TRANSCRIPT_INLINE_TOTAL_BYTES', 6 * 1024 * 1024),
  },

  colors: {
    primary: 0x2f6fed,
    success: 0x22a06b,
    danger: 0xd23f3f,
    warning: 0xd9822b,
    neutral: 0x4f5660,
  },

  timezone: 'Asia/Seoul',
};

export const TICKET_TYPES = [
  {
    value: 'general',
    label: '통합문의',
    prefix: '통합문의',
    description: '서버 이용 전반에 대한 문의를 남깁니다.',
  },
  {
    value: 'bug',
    label: '버그문의',
    prefix: '버그문의',
    description: '게임 또는 서버에서 발견한 오류를 제보합니다.',
  },
  {
    value: 'partner',
    label: '파트너문의',
    prefix: '파트너문의',
    description: '제휴 및 파트너십 관련 문의를 남깁니다.',
  },
];

export function getTicketType(value) {
  return TICKET_TYPES.find((type) => type.value === value) ?? null;
}

export function validateConfig() {
  const problems = [];
  if (!config.token) {
    problems.push(
      '봇 토큰이 없습니다. config.js 맨 위의 BOT_TOKEN 따옴표 사이에 토큰을 붙여넣거나, ' +
        '같은 폴더에 .env 파일을 만들고 DISCORD_TOKEN=토큰 을 적어 주세요.',
    );
  }

  const requiredIds = {
    VERIFY_PANEL_CHANNEL_ID: config.verifyPanelChannelId,
    VERIFIED_ROLE_ID: config.verifiedRoleId,
    TICKET_PANEL_CHANNEL_ID: config.ticketPanelChannelId,
    TICKET_STAFF_ROLE_ID: config.ticketStaffRoleId,
    TICKET_TRANSCRIPT_CHANNEL_ID: config.ticketTranscriptChannelId,
    TICKET_CATEGORY_ID: config.ticketCategoryId,
  };

  for (const [name, value] of Object.entries(requiredIds)) {
    if (!/^\d{17,20}$/.test(String(value ?? ''))) {
      problems.push(`${name} 값이 올바른 디스코드 ID 형식이 아닙니다: ${value}`);
    }
  }

  return problems;
}
