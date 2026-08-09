import { AttachmentBuilder } from 'discord.js';

import { config } from './config.js';
import { log } from './log.js';
import { panel, payload } from './components.js';
import { getAsset, saveAsset } from './storage.js';

/**
 * 서버에 사람이 들어오면 안내 채널에 컨테이너를 올립니다.
 *
 * 컨테이너에 들어가는 그림은 봇이 켜질 때 한 번 받아 두고 메모리에 담아 둡니다.
 * 디스코드 첨부 주소는 시간이 지나면 만료되므로, 받아 둔 파일을 보관 채널에도
 * 옮겨 두고 다음 실행 때는 그쪽에서 가져옵니다.
 */

const ASSET_KEY = 'welcome-image';
const IMAGE_FILE_NAME = 'welcome.png';
const MAX_IMAGE_BYTES = 8 * 1024 * 1024;

let imageBuffer = null;
let prepared = false;

async function download(url) {
  const response = await fetch(url, { signal: AbortSignal.timeout(20_000) });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);

  const buffer = Buffer.from(await response.arrayBuffer());
  if (buffer.length === 0) throw new Error('내용이 비어 있습니다');
  if (buffer.length > MAX_IMAGE_BYTES) throw new Error('그림이 너무 큽니다');
  return buffer;
}

/** 환영 그림을 준비합니다. 봇이 켜질 때 한 번 부르면 됩니다. */
export async function prepareWelcomeImage(client) {
  if (prepared) return imageBuffer;
  prepared = true;

  if (!config.welcomeChannelId) return null;

  // 1) 보관 채널에 옮겨 둔 것이 있으면 그걸 씁니다.
  if (config.storageChannelId) {
    try {
      const asset = await getAsset(client, ASSET_KEY);
      if (asset?.url) {
        imageBuffer = await download(asset.url);
        log.info('환영 그림을 보관 채널에서 불러왔습니다.');
        return imageBuffer;
      }
    } catch (error) {
      log.debug('보관 채널의 환영 그림을 불러오지 못했습니다.', error?.message ?? error);
    }
  }

  // 2) 설정에 적힌 주소에서 받아옵니다.
  if (!config.welcomeImageUrl) return null;

  try {
    imageBuffer = await download(config.welcomeImageUrl);
    log.info('환영 그림을 내려받았습니다.');
  } catch (error) {
    log.warn(
      '환영 그림을 내려받지 못했습니다. .env 의 WELCOME_IMAGE_URL 에 새 주소를 넣어 주세요.',
      error?.message ?? error,
    );
    return null;
  }

  // 3) 다음 실행에도 쓸 수 있도록 보관 채널에 옮겨 둡니다.
  if (config.storageChannelId) {
    try {
      await saveAsset(client, ASSET_KEY, imageBuffer, IMAGE_FILE_NAME);
      log.info('환영 그림을 보관 채널에 옮겨 두었습니다.');
    } catch (error) {
      log.debug('환영 그림을 보관 채널에 옮기지 못했습니다.', error?.message ?? error);
    }
  }

  return imageBuffer;
}

/** 안내 문구를 만듭니다. {user} 자리에 들어온 사람 멘션이 들어갑니다. */
export function formatWelcomeDescription(userId) {
  return String(config.welcomeDescription).replaceAll('{user}', `<@${userId}>`);
}

export function buildWelcomePayload(userId, { image = null } = {}) {
  const container = panel({
    color: config.colors.primary,
    title: config.welcomeTitle,
    description: formatWelcomeDescription(userId),
    image,
    footer: config.brandName,
  });

  const message = payload(container);
  // 컨테이너 안의 글은 멘션이 실제로 울립니다. 들어온 사람만 부르도록 막아 둡니다.
  message.allowedMentions = { users: [String(userId)] };
  return message;
}

export const WELCOME_IMAGE_REF = `attachment://${IMAGE_FILE_NAME}`;

export async function handleMemberJoin(member) {
  if (!config.welcomeChannelId) return;
  if (config.welcomeSkipBots && member?.user?.bot) return;

  const client = member.client;

  const channel = await client.channels.fetch(config.welcomeChannelId).catch(() => null);
  if (!channel?.isTextBased?.()) {
    log.warn(`환영 채널을 찾지 못했습니다: ${config.welcomeChannelId}`);
    return;
  }

  // 다른 서버에서 들어온 사람에게 이 채널이 보이면 안 됩니다.
  if (channel.guildId && member.guild?.id && channel.guildId !== member.guild.id) return;

  const buffer = prepared ? imageBuffer : await prepareWelcomeImage(client).catch(() => null);

  const message = buildWelcomePayload(member.id, {
    image: buffer ? WELCOME_IMAGE_REF : config.welcomeImageUrl,
  });
  if (buffer) message.files = [new AttachmentBuilder(buffer, { name: IMAGE_FILE_NAME })];

  try {
    await channel.send(message);
    log.info(`환영 메시지: ${member.user?.tag ?? member.id}`);
    return;
  } catch (error) {
    log.warn('환영 메시지를 올리지 못했습니다. 그림 없이 다시 시도합니다.', error?.message ?? error);
  }

  // 그림 주소가 만료됐을 수 있으니, 글만이라도 올립니다.
  try {
    await channel.send(buildWelcomePayload(member.id));
    log.info(`환영 메시지(그림 없음): ${member.user?.tag ?? member.id}`);
  } catch (error) {
    log.error('환영 메시지를 올리지 못했습니다.', error?.message ?? error);
  }
}
