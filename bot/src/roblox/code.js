import { randomInt } from 'node:crypto';

// 사람이 눈으로 옮겨 적기 때문에 헷갈리는 글자(I, O)는 제외합니다.
const LETTERS = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
const DIGITS = '0123456789';

/** YCC-123 형태로 알파벳 3자 + 숫자 3자 코드를 생성합니다. */
export function generateVerificationCode() {
  let letters = '';
  for (let i = 0; i < 3; i += 1) letters += LETTERS[randomInt(LETTERS.length)];

  let digits = '';
  for (let i = 0; i < 3; i += 1) digits += DIGITS[randomInt(DIGITS.length)];

  return `${letters}-${digits}`;
}

/**
 * 소개란에 코드가 들어 있는지 확인합니다.
 * 대소문자, 하이픈, 공백 차이는 무시합니다.
 */
export function descriptionContainsCode(description, code) {
  if (typeof description !== 'string' || description.length === 0) return false;

  const normalizedDescription = normalize(description);
  const normalizedCode = normalize(code);
  if (normalizedCode.length === 0) return false;

  return normalizedDescription.includes(normalizedCode);
}

function normalize(value) {
  return String(value)
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, '');
}
