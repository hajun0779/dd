import { store } from './store.js';
import { log } from './log.js';

/**
 * 메시지에 들어 있는 모든 custom_id 를 모읍니다.
 * Components V2 에서는 버튼이 컨테이너 안에 들어가므로 중첩을 따라 내려갑니다.
 */
export function collectCustomIds(message) {
  const ids = [];
  const seen = new WeakSet();

  const visit = (node, depth) => {
    if (!node || typeof node !== 'object' || depth > 10) return;
    if (seen.has(node)) return;
    seen.add(node);

    if (Array.isArray(node)) {
      for (const item of node) visit(item, depth + 1);
      return;
    }

    if (typeof node.custom_id === 'string') ids.push(node.custom_id);
    else if (typeof node.customId === 'string') ids.push(node.customId);

    for (const value of Object.values(node)) {
      if (value && typeof value === 'object') visit(value, depth + 1);
    }
  };

  for (const component of message.components ?? []) {
    let node = component;
    try {
      if (typeof component?.toJSON === 'function') node = component.toJSON();
    } catch {
      node = component;
    }
    visit(node, 0);
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
