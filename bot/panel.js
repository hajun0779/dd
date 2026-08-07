import { store } from './store.js';
import { log } from './log.js';

function collectCustomIds(message) {
  const ids = [];
  for (const row of message.components ?? []) {
    for (const component of row.components ?? []) {
      if (component?.customId) ids.push(component.customId);
    }
  }
  return ids;
}

/**
 * 지정한 채널에 패널을 하나만 유지합니다.
 * 봇이 이전에 올린 같은 종류의 패널은 지우고 새로 게시합니다.
 */
export async function ensurePanel(client, { name, channelId, markers, payload }) {
  const channel = await client.channels.fetch(channelId).catch((error) => {
    log.error(`패널 채널(${channelId})을 불러오지 못했습니다.`, error?.message ?? error);
    return null;
  });

  if (!channel) return null;

  if (!channel.isTextBased() || channel.isDMBased()) {
    log.error(`패널 채널(${channelId})이 서버의 텍스트 채널이 아닙니다.`);
    return null;
  }

  const recent = await channel.messages.fetch({ limit: 50 }).catch(() => null);
  if (recent) {
    for (const message of recent.values()) {
      if (message.author?.id !== client.user.id) continue;
      const ids = collectCustomIds(message);
      if (!ids.some((id) => markers.some((marker) => id.startsWith(marker)))) continue;
      await message.delete().catch(() => {});
    }
  }

  try {
    const sent = await channel.send(payload);
    store.setPanel(name, { channelId, messageId: sent.id });
    log.info(`${name} 패널을 #${channel.name} 채널에 게시했습니다.`);
    return sent;
  } catch (error) {
    log.error(`${name} 패널 게시에 실패했습니다. 봇 권한을 확인해 주세요.`, error?.message ?? error);
    return null;
  }
}
