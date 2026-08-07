import { config } from './config.js';

const dateTimeFormatter = new Intl.DateTimeFormat('ko-KR', {
  timeZone: config.timezone,
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
  hour12: false,
});

const shortFormatter = new Intl.DateTimeFormat('ko-KR', {
  timeZone: config.timezone,
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  hour12: false,
});

const timeOnlyFormatter = new Intl.DateTimeFormat('ko-KR', {
  timeZone: config.timezone,
  hour: '2-digit',
  minute: '2-digit',
  hour12: false,
});

const businessFormatter = new Intl.DateTimeFormat('en-US', {
  timeZone: config.timezone,
  weekday: 'short',
  hour: '2-digit',
  minute: '2-digit',
  hour12: false,
});

const WEEKDAY_INDEX = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };
const WEEKDAY_LABEL = ['일', '월', '화', '수', '목', '금', '토'];

function normalize(parts) {
  const map = {};
  for (const part of parts) map[part.type] = part.value;
  return map;
}

/** 2026-08-07 14:03:22 (KST) 형식 문자열을 반환합니다. */
export function formatKst(input) {
  const date = input instanceof Date ? input : new Date(input);
  if (Number.isNaN(date.getTime())) return '알 수 없음';
  const p = normalize(dateTimeFormatter.formatToParts(date));
  return `${p.year}-${p.month}-${p.day} ${p.hour}:${p.minute}:${p.second} (KST)`;
}

/** 08-07 14:03 형식의 짧은 문자열을 반환합니다. */
export function formatKstShort(input) {
  const date = input instanceof Date ? input : new Date(input);
  if (Number.isNaN(date.getTime())) return '알 수 없음';
  const p = normalize(shortFormatter.formatToParts(date));
  return `${p.month}-${p.day} ${p.hour}:${p.minute}`;
}

/** 14:03 형식의 시각만 반환합니다. */
export function formatKstTime(input) {
  const date = input instanceof Date ? input : new Date(input);
  if (Number.isNaN(date.getTime())) return '';
  const p = normalize(timeOnlyFormatter.formatToParts(date));
  return `${p.hour}:${p.minute}`;
}

/** 밀리초 간격을 한국어 문자열로 변환합니다. */
export function formatDuration(ms) {
  if (!Number.isFinite(ms) || ms < 0) return '알 수 없음';
  const totalSeconds = Math.floor(ms / 1000);
  const days = Math.floor(totalSeconds / 86400);
  const hours = Math.floor((totalSeconds % 86400) / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;

  const parts = [];
  if (days > 0) parts.push(`${days}일`);
  if (hours > 0) parts.push(`${hours}시간`);
  if (minutes > 0) parts.push(`${minutes}분`);
  if (parts.length === 0 || seconds > 0) parts.push(`${seconds}초`);
  return parts.join(' ');
}

export function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// --- 문의 시간 ---

/** 지금이 문의 받는 시간인지 확인합니다. 한국 시간 기준입니다. */
export function isBusinessHours(input = Date.now()) {
  const date = input instanceof Date ? input : new Date(input);
  if (Number.isNaN(date.getTime())) return false;

  const p = normalize(businessFormatter.formatToParts(date));
  const day = WEEKDAY_INDEX[p.weekday];
  if (day === undefined) return false;
  if (!config.business.days.includes(day)) return false;

  const hour = Number(p.hour) % 24;
  const minutes = hour * 60 + Number(p.minute);
  return minutes >= config.business.startHour * 60 && minutes < config.business.endHour * 60;
}

/** 24시간제 시각을 AM 11:00 형태로 바꿉니다. */
export function formatHour12(hour) {
  const value = ((Number(hour) % 24) + 24) % 24;
  const period = value < 12 ? 'AM' : 'PM';
  const display = value % 12 === 0 ? 12 : value % 12;
  return `${period} ${String(display).padStart(2, '0')}:00`;
}

/** 평일 AM 11:00 ~ PM 06:00 형태의 안내 문구를 만듭니다. */
export function formatBusinessHours() {
  const { days, startHour, endHour } = config.business;
  const sorted = [...days].sort((a, b) => a - b);
  const isWeekdays = sorted.length === 5 && sorted.every((day, index) => day === index + 1);
  const dayLabel = isWeekdays ? '평일' : sorted.map((day) => WEEKDAY_LABEL[day]).join(', ');
  return `${dayLabel} ${formatHour12(startHour)} ~ ${formatHour12(endHour)}`;
}
