import { AttachmentBuilder, ButtonBuilder, ButtonStyle } from 'discord.js';

import { config } from './config.js';
import { log } from './log.js';
import { editPayload, errorPanel, neutralPanel, panel, payload, successPanel } from './components.js';

const MAX_IMAGE_BYTES = 8 * 1024 * 1024;

function safeFileName(name) {
  const cleaned = String(name ?? 'image.png').replace(/[^A-Za-z0-9._-]/g, '_');
  return cleaned.length > 0 ? cleaned : 'image.png';
}

export async function handlePartnershipCommand(interaction) {
  await interaction.reply(
    payload(neutralPanel('잠시만 기다려 주세요', '파트너 안내를 올리고 있습니다.'), { ephemeral: true }),
  );

  const link = interaction.options.getString('서버링크').trim();
  const mentionEveryone = interaction.options.getBoolean('모두멘션') ?? false;
  const image = interaction.options.getAttachment('사진');
  const title = interaction.options.getString('제목').trim();
  const intro = interaction.options.getString('소개글').trim();

  if (!/^https?:\/\/\S+$/i.test(link)) {
    await interaction.editReply(
      editPayload(
        errorPanel('서버 링크가 올바르지 않습니다', 'https:// 로 시작하는 주소를 넣어 주세요.'),
      ),
    );
    return;
  }

  const files = [];
  let imageRef = null;

  if (image) {
    if (!String(image.contentType ?? '').startsWith('image/')) {
      await interaction.editReply(
        editPayload(errorPanel('사진이 아닙니다', '이미지 파일만 올릴 수 있습니다.')),
      );
      return;
    }

    if (image.size > MAX_IMAGE_BYTES) {
      await interaction.editReply(
        editPayload(errorPanel('사진이 너무 큽니다', '8MB 이하 이미지를 올려 주세요.')),
      );
      return;
    }

    // 원본 첨부 링크는 시간이 지나면 만료되므로, 파일을 그대로 다시 올려서 씁니다.
    try {
      const response = await fetch(image.url, { signal: AbortSignal.timeout(20_000) });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const buffer = Buffer.from(await response.arrayBuffer());
      const fileName = safeFileName(image.name);
      files.push(new AttachmentBuilder(buffer, { name: fileName }));
      imageRef = `attachment://${fileName}`;
    } catch (error) {
      log.error('파트너 사진을 받아오지 못했습니다.', error?.message ?? error);
      await interaction.editReply(
        editPayload(errorPanel('사진을 불러오지 못했습니다', '잠시 후 다시 시도해 주세요.')),
      );
      return;
    }
  }

  const container = panel({
    color: config.colors.primary,
    title,
    description: mentionEveryone ? `@everyone\n\n${intro}` : intro,
    image: imageRef,
    buttons: [new ButtonBuilder().setLabel('서버 들어가기').setStyle(ButtonStyle.Link).setURL(link)],
    footer: `${config.brandName} 파트너`,
  });

  const message = payload(container);
  if (files.length > 0) message.files = files;
  message.allowedMentions = mentionEveryone ? { parse: ['everyone'] } : { parse: [] };

  try {
    await interaction.channel.send(message);
  } catch (error) {
    log.error('파트너 안내 게시 실패', error?.message ?? error);
    await interaction.editReply(
      editPayload(
        errorPanel(
          '올리지 못했습니다',
          mentionEveryone
            ? '봇에게 이 채널에서 모두에게 멘션할 권한이 있는지 확인해 주세요.'
            : '봇에게 이 채널에 메시지를 보낼 권한이 있는지 확인해 주세요.',
        ),
      ),
    );
    return;
  }

  await interaction.editReply(editPayload(successPanel('올렸습니다', '아래에 파트너 안내를 게시했습니다.')));
}
