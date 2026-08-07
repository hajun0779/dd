// .env 파일이 있으면 읽어옵니다. dotenv 가 설치되어 있지 않아도 시스템 환경 변수로 동작합니다.
try {
  await import('dotenv/config');
} catch {
  // 무시하고 process.env 만 사용합니다.
}

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
  token: str('DISCORD_TOKEN', null),

  // 로블록스 인증
  verifyPanelChannelId: str('VERIFY_PANEL_CHANNEL_ID', '1418823709027733517'),
  verifiedRoleId: str('VERIFIED_ROLE_ID', '1418823708247720077'),
  nicknamePrefix: str('NICKNAME_PREFIX', '예천군 시민ㅣ'),
  verifyCodeTtlMinutes: int('VERIFY_CODE_TTL_MINUTES', 30),

  // 티켓
  ticketPanelChannelId: str('TICKET_PANEL_CHANNEL_ID', '1535140042652254219'),
  ticketStaffRoleId: str('TICKET_STAFF_ROLE_ID', '1535140290581635162'),
  ticketTranscriptChannelId: str('TICKET_TRANSCRIPT_CHANNEL_ID', '1535140618626670623'),
  ticketCategoryId: str('TICKET_CATEGORY_ID', '1535141065160658944'),
  ticketDeleteDelaySeconds: int('TICKET_DELETE_DELAY_SECONDS', 5),

  // 저장소
  dataFile: str('DATA_FILE', './data/store.json'),

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
  if (!config.token) problems.push('DISCORD_TOKEN 이 설정되지 않았습니다.');

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
