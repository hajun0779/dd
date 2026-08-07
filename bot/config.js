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

  // 컨테이너 맨 아래 작은 글씨에 들어갈 이름
  brandName: str('BRAND_NAME', 'RoStation'),

  // 모든 컨테이너 맨 아래에 붙는 저작권 문구
  copyrightText: str(
    'COPYRIGHT_TEXT',
    `Copyright ${str('COPYRIGHT_YEAR', '2026')}. ${str('BRAND_NAME', 'RoStation')}. All rights reserved.`,
  ),

  // 티켓
  ticketPanelChannelId: str('TICKET_PANEL_CHANNEL_ID', '1535140042652254219'),
  ticketStaffRoleId: str('TICKET_STAFF_ROLE_ID', '1535140290581635162'),
  ticketTranscriptChannelId: str('TICKET_TRANSCRIPT_CHANNEL_ID', '1535140618626670623'),
  ticketDeleteDelaySeconds: int('TICKET_DELETE_DELAY_SECONDS', 5),
  // 티켓 패널 안에 넣을 배너 이미지 주소. 비워 두면 이미지 없이 나갑니다.
  ticketPanelImageUrl: str('TICKET_PANEL_IMAGE_URL', null),

  // 총관리자 역할. 모든 명령을 쓸 수 있고, 모든 보고를 DM 으로 받습니다.
  adminRoleId: str('ADMIN_ROLE_ID', null),

  // 업무 배당
  assignListChannelId: str('ASSIGN_LIST_CHANNEL_ID', null),
  assignStatusChannelId: str('ASSIGN_STATUS_CHANNEL_ID', null),
  warningChannelId: str('WARNING_CHANNEL_ID', null),
  payrollChannelId: str('PAYROLL_CHANNEL_ID', null),

  // 기간이 지난 뒤 몇 시간마다 알릴지, 연장하면 몇 시간을 더 줄지
  overdueNoticeHours: int('OVERDUE_NOTICE_HOURS', 1),
  extendHours: int('EXTEND_HOURS', 2),

  // 후기가 올라갈 채널
  reviewChannelId: str('REVIEW_CHANNEL_ID', null),

  // 봇이 설정과 제품 파일을 보관할 채널. 스태프만 보이게 만들어 주세요.
  storageChannelId: str('STORAGE_CHANNEL_ID', null),

  // 제품을 등록하고 보낼 수 있는 역할
  productRoleId: str('PRODUCT_APPROVAL_ROLE_ID', null),

  // 문의 받는 시간 (한국 시간 기준). 0=일요일, 1=월요일 ... 6=토요일
  business: {
    startHour: int('BUSINESS_START_HOUR', 11),
    endHour: int('BUSINESS_END_HOUR', 18),
    days: str('BUSINESS_DAYS', '1,2,3,4,5')
      .split(',')
      .map((day) => Number.parseInt(day.trim(), 10))
      .filter((day) => Number.isInteger(day) && day >= 0 && day <= 6),
  },

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

// 문의 종류마다 카테고리가 따로 있습니다.
// 제품 문의와 파트너 문의 카테고리 ID 를 아직 넣지 않았다면 통합 문의 카테고리를 대신 씁니다.
const GENERAL_CATEGORY_ID = str('TICKET_CATEGORY_GENERAL', '1535141065160658944');

export const TICKET_TYPES = [
  {
    value: 'general',
    label: '통합 문의',
    prefix: '통합문의',
    description: '서버 이용에 대한 문의',
    categoryId: GENERAL_CATEGORY_ID,
  },
  {
    value: 'product',
    label: '제품 문의',
    prefix: '제품문의',
    description: '제품에 대한 문의',
    categoryId: str('TICKET_CATEGORY_PRODUCT', GENERAL_CATEGORY_ID),
  },
  {
    value: 'partner',
    label: '파트너 문의',
    prefix: '파트너문의',
    description: '제휴 문의',
    categoryId: str('TICKET_CATEGORY_PARTNER', GENERAL_CATEGORY_ID),
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
    TICKET_PANEL_CHANNEL_ID: config.ticketPanelChannelId,
    TICKET_STAFF_ROLE_ID: config.ticketStaffRoleId,
    TICKET_TRANSCRIPT_CHANNEL_ID: config.ticketTranscriptChannelId,
  };

  for (const type of TICKET_TYPES) {
    requiredIds[`${type.label} 카테고리`] = type.categoryId;
  }

  for (const [name, value] of Object.entries(requiredIds)) {
    if (!/^\d{17,20}$/.test(String(value ?? ''))) {
      problems.push(`${name} 값이 올바른 디스코드 ID 형식이 아닙니다: ${value}`);
    }
  }

  if (config.business.days.length === 0) {
    problems.push('BUSINESS_DAYS 에 요일이 하나도 없습니다. 0(일)부터 6(토) 사이 숫자를 쉼표로 적어 주세요.');
  }

  if (config.business.startHour >= config.business.endHour) {
    problems.push('BUSINESS_START_HOUR 는 BUSINESS_END_HOUR 보다 앞이어야 합니다.');
  }

  return problems;
}

/** 아직 채우지 않은 선택 설정을 알려 줍니다. */
export function getMissingOptionalIds() {
  const wanted = [
    ['ADMIN_ROLE_ID', '총관리자 역할', config.adminRoleId],
    ['STORAGE_CHANNEL_ID', '설정과 제품 보관 채널', config.storageChannelId],
    ['REVIEW_CHANNEL_ID', '후기 채널', config.reviewChannelId],
    ['PRODUCT_APPROVAL_ROLE_ID', '제품 담당 역할', config.productRoleId],
    ['ASSIGN_LIST_CHANNEL_ID', '배당 목록 채널', config.assignListChannelId],
    ['ASSIGN_STATUS_CHANNEL_ID', '배당 상황 채널', config.assignStatusChannelId],
    ['WARNING_CHANNEL_ID', '경고 상태 채널', config.warningChannelId],
    ['PAYROLL_CHANNEL_ID', '급여 신청 채널', config.payrollChannelId],
  ];
  return wanted.filter(([, , value]) => !value).map(([name, label]) => [name, label]);
}

/** 아직 채우지 않아 통합 문의 카테고리를 같이 쓰고 있는 종류를 알려 줍니다. */
export function getSharedCategoryTypes() {
  return TICKET_TYPES.filter(
    (type) => type.value !== 'general' && type.categoryId === GENERAL_CATEGORY_ID,
  );
}
