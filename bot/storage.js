import { config } from './config.js';
import { log } from './log.js';

/**
 * 설정과 제품은 파일이 아니라 디스코드 메시지에 보관합니다.
 * 보관 채널에 봇이 올린 메시지를 읽고 고치는 방식이라 봇을 옮겨도 그대로 남습니다.
 */

const SETTINGS_MARKER = 'ROSTATION_SETTINGS_V1';
const PRODUCT_MARKER = 'ROSTATION_PRODUCT_V1';
const CACHE_MS = 20_000;

const DEFAULT_SETTINGS = {
  // 직원 명단에 쓰는 역할 목록
  staffRoles: [],
};

let settingsCache = null;

export class StorageError extends Error {}

async function getStorageChannel(client) {
  if (!config.storageChannelId) {
    throw new StorageError('보관 채널이 설정되지 않았습니다. .env 의 STORAGE_CHANNEL_ID 를 채워 주세요.');
  }

  // DM 에서 눌린 버튼도 처리해야 하므로 서버가 아니라 클라이언트로 찾습니다.
  const channel = await client.channels.fetch(config.storageChannelId).catch(() => null);
  if (!channel || !channel.isTextBased()) {
    throw new StorageError('보관 채널을 찾지 못했습니다. STORAGE_CHANNEL_ID 를 확인해 주세요.');
  }
  return channel;
}

function wrap(marker, data) {
  return ['```json', marker, JSON.stringify(data, null, 2), '```'].join('\n');
}

function unwrap(marker, content) {
  if (typeof content !== 'string' || !content.includes(marker)) return null;
  const start = content.indexOf(marker) + marker.length;
  const end = content.lastIndexOf('```');
  if (end <= start) return null;
  try {
    return JSON.parse(content.slice(start, end).trim());
  } catch {
    return null;
  }
}

// --- 설정 ---

async function findSettingsMessage(channel, client) {
  const recent = await channel.messages.fetch({ limit: 50 }).catch(() => null);
  if (!recent) return null;
  return (
    recent.find(
      (message) => message.author?.id === client.user.id && message.content.includes(SETTINGS_MARKER),
    ) ?? null
  );
}

export async function readSettings(client) {
  if (settingsCache && settingsCache.expiresAt > Date.now()) return settingsCache.data;

  const channel = await getStorageChannel(client);
  const message = await findSettingsMessage(channel, client);
  const parsed = message ? unwrap(SETTINGS_MARKER, message.content) : null;
  const data = { ...structuredClone(DEFAULT_SETTINGS), ...(parsed ?? {}) };
  if (!Array.isArray(data.staffRoles)) data.staffRoles = [];

  settingsCache = { data, expiresAt: Date.now() + CACHE_MS };
  return data;
}

export async function writeSettings(client, data) {
  const channel = await getStorageChannel(client);
  const message = await findSettingsMessage(channel, client);
  const content = wrap(SETTINGS_MARKER, data);

  if (content.length > 1900) {
    throw new StorageError('설정이 너무 길어 저장할 수 없습니다. 역할 수를 줄여 주세요.');
  }

  if (message) {
    await message.edit({ content });
  } else {
    const sent = await channel.send({ content });
    await sent.pin().catch(() => {});
  }

  settingsCache = { data, expiresAt: Date.now() + CACHE_MS };
  return data;
}

export function clearSettingsCache() {
  settingsCache = null;
}

// --- 제품 ---

function parseProductMessage(message) {
  const data = unwrap(PRODUCT_MARKER, message.content);
  if (!data?.id || !data?.name) return null;

  const attachment = message.attachments.first();
  return {
    ...data,
    messageId: message.id,
    // 디스코드 첨부 링크는 시간이 지나면 만료됩니다. 보낼 때마다 새로 읽어옵니다.
    fileUrl: attachment?.url ?? null,
    fileName: attachment?.name ?? null,
    fileSize: attachment?.size ?? 0,
  };
}

/** 보관 채널에 올라간 제품을 모두 읽어옵니다. */
export async function listProducts(client) {
  const channel = await getStorageChannel(client);
  const products = [];
  let before;

  for (let page = 0; page < 3; page += 1) {
    const batch = await channel.messages
      .fetch({ limit: 100, ...(before ? { before } : {}) })
      .catch(() => null);

    if (!batch || batch.size === 0) break;

    for (const message of batch.values()) {
      if (message.author?.id !== client.user.id) continue;
      const product = parseProductMessage(message);
      if (product) products.push(product);
    }

    const ordered = [...batch.values()];
    before = ordered[ordered.length - 1].id;
    if (batch.size < 100) break;
  }

  // 같은 이름이 여러 번 등록되면 가장 최근 것만 씁니다.
  const seen = new Set();
  const unique = [];
  for (const product of products) {
    if (seen.has(product.id)) continue;
    seen.add(product.id);
    unique.push(product);
  }

  return unique.sort((a, b) => a.name.localeCompare(b.name, 'ko'));
}

/** 제품 하나를 다시 읽어옵니다. 첨부 링크가 새로 발급되므로 보낼 때마다 호출합니다. */
export async function getProduct(client, id) {
  const channel = await getStorageChannel(client);
  let before;

  for (let page = 0; page < 3; page += 1) {
    const batch = await channel.messages
      .fetch({ limit: 100, ...(before ? { before } : {}) })
      .catch(() => null);

    if (!batch || batch.size === 0) break;

    for (const message of batch.values()) {
      if (message.author?.id !== client.user.id) continue;
      const product = parseProductMessage(message);
      if (product?.id === id) return product;
    }

    const ordered = [...batch.values()];
    before = ordered[ordered.length - 1].id;
    if (batch.size < 100) break;
  }

  return null;
}

/**
 * 제품을 보관 채널에 올립니다.
 * zip 파일을 그대로 다시 올려 두고, 나중에 그 메시지에서 새 다운로드 링크를 받아옵니다.
 */
export async function addProduct(client, { id, name, description, buffer, fileName, author }) {
  const channel = await getStorageChannel(client);
  const { AttachmentBuilder } = await import('discord.js');

  const meta = {
    id,
    name,
    description,
    createdAt: Date.now(),
    createdBy: author,
  };

  const sent = await channel.send({
    content: wrap(PRODUCT_MARKER, meta),
    files: [new AttachmentBuilder(buffer, { name: fileName })],
  });

  log.info(`제품 등록: ${name} (${id})`);
  return parseProductMessage(sent);
}

/** 등록된 제품을 지웁니다. */
export async function removeProduct(client, id) {
  const channel = await getStorageChannel(client);
  const recent = await channel.messages.fetch({ limit: 100 }).catch(() => null);
  if (!recent) return false;

  for (const message of recent.values()) {
    if (message.author?.id !== client.user.id) continue;
    const product = parseProductMessage(message);
    if (product?.id === id) {
      await message.delete().catch(() => {});
      return true;
    }
  }
  return false;
}

/** 이름에서 제품 ID 를 만듭니다. 상호작용 ID 에 들어가므로 짧고 안전하게 만듭니다. */
export function makeProductId(name) {
  const base = String(name)
    .toLowerCase()
    .replace(/[^a-z0-9가-힣]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 24);
  return base.length > 0 ? base : `p${Date.now().toString(36)}`;
}
