import {
  ActionRowBuilder,
  ModalBuilder,
  StringSelectMenuBuilder,
  TextInputBuilder,
  TextInputStyle,
} from 'discord.js';

import { config } from './config.js';
import { log } from './log.js';
import { formatKst } from './time.js';
import { editPayload, errorPanel, panel, payload, successPanel } from './components.js';

export const REVIEW_IDS = {
  pick: 'review:pick',
  form: 'review:form',
  textInput: 'review:text',
};

const MAX_STARS = 5;

const KIND_LABEL = {
  ticket: '문의',
  product: '제품',
};

function starText(count) {
  const value = Math.min(MAX_STARS, Math.max(1, Number(count) || 1));
  return `${'★'.repeat(value)}${'☆'.repeat(MAX_STARS - value)}`;
}

/**
 * 후기 요청 메시지를 만듭니다.
 * 별점을 목록에서 고르면 후기를 적는 창이 열립니다.
 */
export function buildReviewRequest({ kind, ref, subject }) {
  const label = KIND_LABEL[kind] ?? '이용';

  const menu = new StringSelectMenuBuilder()
    .setCustomId(`${REVIEW_IDS.pick}:${kind}:${ref}`)
    .setPlaceholder('별점을 선택해 주세요')
    .setMinValues(1)
    .setMaxValues(1)
    .addOptions(
      Array.from({ length: MAX_STARS }, (_, index) => {
        const value = MAX_STARS - index;
        return {
          label: starText(value),
          value: String(value),
          description: `${value}점`,
        };
      }),
    );

  const container = panel({
    color: config.colors.primary,
    title: `${label} 후기`,
    description: `**${subject}**\n\n이용해 주셔서 감사합니다. 별점을 선택해 주세요.`,
    buttons: [menu],
    footer: `${config.brandName} ${label} 후기`,
  });

  return payload(container);
}

/** 문의나 제품을 받은 사람에게 후기 요청을 DM 으로 보냅니다. */
export async function sendReviewRequest(client, userId, options) {
  if (!userId) return false;

  try {
    const user = await client.users.fetch(userId);
    await user.send(buildReviewRequest(options));
    return true;
  } catch (error) {
    log.warn(`후기 요청을 보내지 못했습니다 (${userId}). DM 이 닫혀 있을 수 있습니다.`, error?.message ?? error);
    return false;
  }
}

// --- 별점 선택 ---

export async function handleReviewPick(interaction) {
  const [, , kind, ...rest] = interaction.customId.split(':');
  const ref = rest.join(':');
  const stars = Number(interaction.values?.[0]);

  if (!Number.isInteger(stars) || stars < 1 || stars > MAX_STARS) {
    await interaction.reply(
      payload(errorPanel('별점을 읽지 못했습니다', '다시 선택해 주세요.'), { ephemeral: true }),
    );
    return;
  }

  const label = KIND_LABEL[kind] ?? '이용';

  const modal = new ModalBuilder()
    .setCustomId(`${REVIEW_IDS.form}:${kind}:${stars}:${ref}`)
    .setTitle(`${label} 후기 (${stars}점)`);

  const input = new TextInputBuilder()
    .setCustomId(REVIEW_IDS.textInput)
    .setLabel('후기를 적어 주세요')
    .setPlaceholder('좋았던 점이나 아쉬웠던 점을 자유롭게 적어 주세요.')
    .setStyle(TextInputStyle.Paragraph)
    .setMinLength(1)
    .setMaxLength(1000)
    .setRequired(true);

  modal.addComponents(new ActionRowBuilder().addComponents(input));
  await interaction.showModal(modal);
}

// --- 후기 제출 ---

export async function handleReviewSubmit(interaction) {
  const [, , kind, starsRaw, ...rest] = interaction.customId.split(':');
  const ref = rest.join(':');
  const stars = Number(starsRaw);
  const label = KIND_LABEL[kind] ?? '이용';
  const text = interaction.fields.getTextInputValue(REVIEW_IDS.textInput).trim();

  await interaction.reply(
    payload(successPanel('보내 주셔서 감사합니다', '후기가 잘 전달되었습니다.'), { ephemeral: true }),
  );

  if (!config.reviewChannelId) {
    log.warn('후기 채널이 설정되지 않아 후기를 남기지 못했습니다. REVIEW_CHANNEL_ID 를 채워 주세요.');
    return;
  }

  const channel = await interaction.client.channels.fetch(config.reviewChannelId).catch(() => null);
  if (!channel?.isTextBased()) {
    log.error(`후기 채널(${config.reviewChannelId})을 찾지 못했습니다.`);
    return;
  }

  const container = panel({
    color: config.colors.success,
    title: `${label} 후기`,
    description: `**${starText(stars)}** ${stars}점`,
    fields: [
      { name: '내용', value: text.slice(0, 1000) },
      { name: kind === 'product' ? '제품' : '문의 번호', value: ref || '알 수 없음' },
      { name: '작성자', value: `${interaction.user} (${interaction.user.id})` },
      { name: '남긴 시간', value: formatKst(Date.now()) },
    ],
    footer: `${config.brandName} 후기`,
  });

  await channel
    .send({ ...payload(container), allowedMentions: { parse: [] } })
    .catch((error) => log.error('후기 전송 실패', error?.message ?? error));

  // 이미 답한 후기 요청은 다시 누르지 못하게 막습니다.
  await interaction.message
    ?.edit(
      editPayload(
        panel({
          color: config.colors.neutral,
          title: `${label} 후기`,
          description: `**${starText(stars)}** ${stars}점\n\n후기를 남겨 주셔서 감사합니다.`,
          footer: `${config.brandName} ${label} 후기`,
        }),
      ),
    )
    .catch(() => {});
}

export function isReviewCustomId(customId) {
  return customId.startsWith('review:');
}
