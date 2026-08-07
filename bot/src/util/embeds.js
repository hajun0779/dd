import { EmbedBuilder, MessageFlags } from 'discord.js';
import { config } from '../config.js';

/**
 * 이 봇의 모든 메시지는 임베드로만 전송됩니다.
 * 버튼과 드롭다운은 항상 이 임베드에 붙여서 함께 보냅니다.
 */
export function buildEmbed({ title, description, color, fields, footer, thumbnail, image, author, timestamp = true } = {}) {
  const embed = new EmbedBuilder().setColor(color ?? config.colors.primary);

  if (title) embed.setTitle(title);
  if (description) embed.setDescription(description);
  if (Array.isArray(fields) && fields.length > 0) embed.addFields(fields);
  if (footer) embed.setFooter(typeof footer === 'string' ? { text: footer } : footer);
  if (thumbnail) embed.setThumbnail(thumbnail);
  if (image) embed.setImage(image);
  if (author) embed.setAuthor(author);
  if (timestamp) embed.setTimestamp(new Date());

  return embed;
}

export function infoEmbed(title, description, extra = {}) {
  return buildEmbed({ title, description, color: config.colors.primary, ...extra });
}

export function successEmbed(title, description, extra = {}) {
  return buildEmbed({ title, description, color: config.colors.success, ...extra });
}

export function errorEmbed(title, description, extra = {}) {
  return buildEmbed({ title, description, color: config.colors.danger, ...extra });
}

export function warningEmbed(title, description, extra = {}) {
  return buildEmbed({ title, description, color: config.colors.warning, ...extra });
}

/** 임베드 하나만 담긴 임시(본인만 보이는) 응답 페이로드를 만듭니다. */
export function ephemeral(embed, components = []) {
  return { embeds: [embed], components, flags: MessageFlags.Ephemeral };
}

/** 공개 메시지 페이로드를 만듭니다. */
export function publicPayload(embed, components = []) {
  return { embeds: [embed], components };
}
