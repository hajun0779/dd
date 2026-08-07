import { log } from '../util/log.js';

const USERS_API = 'https://users.roblox.com/v1';
const THUMBNAILS_API = 'https://thumbnails.roblox.com/v1';
const REQUEST_TIMEOUT_MS = 10_000;

export class RobloxApiError extends Error {
  constructor(message, { status = null, cause = null } = {}) {
    super(message);
    this.name = 'RobloxApiError';
    this.status = status;
    this.cause = cause;
  }
}

async function request(url, options = {}) {
  let response;
  try {
    response = await fetch(url, {
      ...options,
      headers: {
        Accept: 'application/json',
        'User-Agent': 'YecheonVerifyBot/1.0',
        ...(options.headers ?? {}),
      },
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    });
  } catch (error) {
    throw new RobloxApiError('로블록스 서버에 연결하지 못했습니다.', { cause: error });
  }

  if (response.status === 429) {
    throw new RobloxApiError('로블록스 요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.', {
      status: 429,
    });
  }

  if (!response.ok && response.status !== 404) {
    throw new RobloxApiError(`로블록스 응답 오류 (HTTP ${response.status})`, {
      status: response.status,
    });
  }

  let body = null;
  try {
    body = await response.json();
  } catch {
    body = null;
  }

  return { status: response.status, body };
}

/** 로블록스 닉네임으로 사용자를 조회합니다. 없으면 null 을 반환합니다. */
export async function getUserByUsername(username) {
  const { body } = await request(`${USERS_API}/usernames/users`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ usernames: [username], excludeBannedUsers: false }),
  });

  const entry = Array.isArray(body?.data) ? body.data[0] : null;
  if (!entry) return null;

  return {
    id: String(entry.id),
    name: entry.name,
    displayName: entry.displayName ?? entry.name,
  };
}

/** 로블록스 사용자 ID 로 프로필(소개란 포함)을 조회합니다. */
export async function getUserById(userId) {
  const { status, body } = await request(`${USERS_API}/users/${encodeURIComponent(userId)}`);
  if (status === 404 || !body?.id) return null;

  return {
    id: String(body.id),
    name: body.name,
    displayName: body.displayName ?? body.name,
    description: typeof body.description === 'string' ? body.description : '',
    created: body.created ?? null,
    isBanned: Boolean(body.isBanned),
  };
}

/** 프로필 사진 URL 을 가져옵니다. 실패하면 null 을 반환합니다. */
export async function getAvatarHeadshotUrl(userId) {
  try {
    const { body } = await request(
      `${THUMBNAILS_API}/users/avatar-headshot?userIds=${encodeURIComponent(userId)}&size=150x150&format=Png&isCircular=false`,
    );
    const entry = Array.isArray(body?.data) ? body.data[0] : null;
    if (entry?.state === 'Completed' && entry.imageUrl) return entry.imageUrl;
  } catch (error) {
    log.debug('프로필 사진을 가져오지 못했습니다.', error);
  }
  return null;
}

export function profileUrl(userId) {
  return `https://www.roblox.com/users/${userId}/profile`;
}
