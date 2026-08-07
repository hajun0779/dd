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
