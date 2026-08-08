import { config } from './config.js';

/**
 * 시간은 Intl 에 기대지 않고 직접 계산합니다.
 *
 * 호스팅에 따라 Node 가 전체 ICU 없이 설치되어 있으면
 * Intl 에 Asia/Seoul 을 넣어도 무시되고 UTC 로 처리됩니다.
 * 그러면 낮 12시가 새벽 3시로 읽혀서 문의 시간 판정이 어긋납니다.
 * 한국은 서머타임이 없어 UTC 에 9시간만 더하면 정확하므로 그렇게 계산합니다.
 */

const OFFSET_MS = config.timezoneOffsetHours * 3600_000;

const WEEKDAY_LABEL = ['일', '월', '화', '수', '목', '금', '토'];

function pad(value, length = 2) {
  return String(value).padStart(length, '0');
}

/** 한국 시간 기준의 연월일시분초와 요일을 뽑아냅니다. */
export function kstParts(input = Date.now()) {
  const date = input instanceof Date ? input : new Date(input);
  if (Number.isNaN(date.getTime())) return null;

  const shifted = new Date(date.getTime() + OFFSET_MS);
  return {
    year: shifted.getUTCFullYear(),
    month: shifted.getUTCMonth() + 1,
    day: shifted.getUTCDate(),
    hour: shifted.getUTCHours(),
    minute: shifted.getUTCMinutes(),
    second: shifted.getUTCSeconds(),
    weekday: shifted.getUTCDay(),
  };
}

/** 2026-08-07 14:03:22 (KST) 형식 문자열을 반환합니다. */
export function formatKst(input) {
  const p = kstParts(input);
  if (!p) return '알 수 없음';
  return `${p.year}-${pad(p.month)}-${pad(p.day)} ${pad(p.hour)}:${pad(p.minute)}:${pad(p.second)} (KST)`;
}

/** 08-07 14:03 형식의 짧은 문자열을 반환합니다. */
export function formatKstShort(input) {
  const p = kstParts(input);
  if (!p) return '알 수 없음';
  return `${pad(p.month)}-${pad(p.day)} ${pad(p.hour)}:${pad(p.minute)}`;
}

/** 14:03 형식의 시각만 반환합니다. */
export function formatKstTime(input) {
  const p = kstParts(input);
  if (!p) return '';
  return `${pad(p.hour)}:${pad(p.minute)}`;
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
  const p = kstParts(input);
  if (!p) return false;
  if (!config.business.days.includes(p.weekday)) return false;

  const minutes = p.hour * 60 + p.minute;
  return minutes >= config.business.startHour * 60 && minutes < config.business.endHour * 60;
}

/** 24시간제 시각을 AM 11:00 형태로 바꿉니다. */
export function formatHour12(hour) {
  const value = ((Number(hour) % 24) + 24) % 24;
  const period = value < 12 ? 'AM' : 'PM';
  const display = value % 12 === 0 ? 12 : value % 12;
  return `${period} ${pad(display)}:00`;
}

/** 평일 AM 11:00 ~ PM 06:00 형태의 안내 문구를 만듭니다. */
export function formatBusinessHours() {
  const { days, startHour, endHour } = config.business;
  const sorted = [...days].sort((a, b) => a - b);
  const isWeekdays = sorted.length === 5 && sorted.every((day, index) => day === index + 1);
  const dayLabel = isWeekdays ? '평일' : sorted.map((day) => WEEKDAY_LABEL[day]).join(', ');
  return `${dayLabel} ${formatHour12(startHour)} ~ ${formatHour12(endHour)}`;
}
