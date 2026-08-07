import {
  ActionRowBuilder,
  AttachmentBuilder,
  ButtonBuilder,
  ButtonStyle,
  ChannelType,
  MessageFlags,
  PermissionsBitField,
  StringSelectMenuBuilder,
} from 'discord.js';

import { config, TICKET_TYPES, getTicketType } from './config.js';
import { store } from './store.js';
import { log } from './log.js';
import { formatKst, sleep } from './time.js';
import { buildEmbed, errorEmbed, ephemeral, warningEmbed } from './embeds.js';
import { ensurePanel } from './panel.js';
import { buildTranscriptHtml, fetchAllMessages } from './transcript.js';

export const TICKET_IDS = {
  select: 'ticket:create',
  close: 'ticket:close',
  closeConfirm: 'ticket:close:confirm',
  closeCancel: 'ticket:close:cancel',
};

const MAX_DISCORD_UPLOAD_BYTES = 9 * 1024 * 1024;
const closingChannels = new Set();

// --- 패널 ---

export function buildTicketPanelPayload() {
  const embed = buildEmbed({
    title: '문의 티켓',
    color: config.colors.primary,
    description: [
      '아래 목록에서 문의 종류를 선택하면 상담 채널이 새로 만들어집니다.',
      '',
      `만들어진 채널은 작성자 본인과 <@&${config.ticketStaffRoleId}> 역할만 볼 수 있습니다.`,
    ].join('\n'),
    fields: TICKET_TYPES.map((type) => ({
      name: type.label,
      value: type.description,
    })).concat([
      {
        name: '안내',
        value: [
          '문의 내용은 최대한 자세히 적어 주세요.',
          '티켓은 스태프가 확인 후 직접 닫으며, 닫힐 때 모든 대화 내용이 기록으로 저장됩니다.',
          '같은 종류의 티켓은 한 번에 하나만 열 수 있습니다.',
        ].join('\n'),
      },
    ]),
    footer: { text: '예천군 티켓 시스템' },
  });

  const menu = new StringSelectMenuBuilder()
    .setCustomId(TICKET_IDS.select)
    .setPlaceholder('문의 종류를 선택해 주세요')
    .setMinValues(1)
    .setMaxValues(1)
    .addOptions(
      TICKET_TYPES.map((type) => ({
        label: type.label,
        value: type.value,
        description: type.description.slice(0, 100),
      })),
    );

  return { embeds: [embed], components: [new ActionRowBuilder().addComponents(menu)] };
}

export async function deployTicketPanel(client) {
  return ensurePanel(client, {
    name: 'ticket',
    channelId: config.ticketPanelChannelId,
    markers: [TICKET_IDS.select],
    payload: buildTicketPanelPayload(),
  });
}

function buildTicketControlPayload(ticket) {
  const embed = buildEmbed({
    title: `${ticket.typeLabel} 티켓`,
    color: config.colors.primary,
    description: [
      `<@${ticket.ownerId}> 님의 문의입니다.`,
      '',
      '문의 내용을 아래에 남겨 주세요. 스태프가 확인 후 답변드립니다.',
      '',
      `스태프(<@&${config.ticketStaffRoleId}>)는 아래 티켓 닫기 버튼으로 이 티켓을 종료할 수 있습니다.`,
      '티켓이 닫히면 대화 내용과 첨부파일이 기록으로 저장됩니다.',
    ].join('\n'),
    fields: [
      { name: '티켓 번호', value: ticket.name, inline: true },
      { name: '문의 종류', value: ticket.typeLabel, inline: true },
      { name: '만들어진 시간', value: formatKst(ticket.createdAt) },
    ],
    footer: { text: '예천군 티켓 시스템' },
  });

  const row = new ActionRowBuilder().addComponents(
    new ButtonBuilder()
      .setCustomId(TICKET_IDS.close)
      .setLabel('티켓 닫기')
      .setStyle(ButtonStyle.Danger),
  );

  return { embeds: [embed], components: [row] };
}

// --- 티켓 생성 ---

export async function handleTicketCreate(interaction) {
  await interaction.deferReply({ flags: MessageFlags.Ephemeral });

  const guild = interaction.guild;
  if (!guild) {
    await interaction.editReply({
      embeds: [errorEmbed('생성 불가', '이 기능은 서버 안에서만 사용할 수 있습니다.')],
    });
    return;
  }

  const typeValue = interaction.values?.[0];
  const type = getTicketType(typeValue);

  if (!type) {
    await interaction.editReply({
      embeds: [errorEmbed('알 수 없는 문의 종류', '문의 종류를 다시 선택해 주세요.')],
    });
    return;
  }

  // 같은 종류의 티켓이 이미 열려 있는지 확인합니다.
  const existing = store.findOpenTicket(guild.id, interaction.user.id, type.value);
  if (existing) {
    const stillExists = await guild.channels.fetch(existing.channelId).catch(() => null);
    if (stillExists) {
      await interaction.editReply({
        embeds: [
          warningEmbed(
            '이미 열려 있는 티켓이 있습니다',
            `<#${existing.channelId}> 채널에서 계속 진행해 주세요.\n같은 종류의 티켓은 한 번에 하나만 열 수 있습니다.`,
          ),
        ],
      });
      await resetPanel(interaction);
      return;
    }
    store.removeTicket(existing.channelId);
  }

  const category = await guild.channels.fetch(config.ticketCategoryId).catch(() => null);
  if (!category || category.type !== ChannelType.GuildCategory) {
    log.error(`티켓 카테고리(${config.ticketCategoryId})를 찾을 수 없거나 카테고리가 아닙니다.`);
    await interaction.editReply({
      embeds: [
        errorEmbed(
          '티켓을 만들지 못했습니다',
          '티켓 카테고리 설정이 올바르지 않습니다. 스태프에게 문의해 주세요.',
        ),
      ],
    });
    return;
  }

  const number = store.nextTicketNumber(guild.id, type.value);
  const name = `${type.prefix}-${String(number).padStart(4, '0')}`;
  const createdAt = Date.now();

  const overwrites = [
    {
      id: guild.roles.everyone.id,
      deny: [PermissionsBitField.Flags.ViewChannel],
    },
    {
      id: interaction.user.id,
      allow: [
        PermissionsBitField.Flags.ViewChannel,
        PermissionsBitField.Flags.SendMessages,
        PermissionsBitField.Flags.ReadMessageHistory,
        PermissionsBitField.Flags.AttachFiles,
        PermissionsBitField.Flags.EmbedLinks,
        PermissionsBitField.Flags.AddReactions,
      ],
    },
    {
      id: config.ticketStaffRoleId,
      allow: [
        PermissionsBitField.Flags.ViewChannel,
        PermissionsBitField.Flags.SendMessages,
        PermissionsBitField.Flags.ReadMessageHistory,
        PermissionsBitField.Flags.AttachFiles,
        PermissionsBitField.Flags.EmbedLinks,
        PermissionsBitField.Flags.AddReactions,
        PermissionsBitField.Flags.ManageMessages,
      ],
    },
    {
      id: interaction.client.user.id,
      allow: [
        PermissionsBitField.Flags.ViewChannel,
        PermissionsBitField.Flags.SendMessages,
        PermissionsBitField.Flags.ReadMessageHistory,
        PermissionsBitField.Flags.AttachFiles,
        PermissionsBitField.Flags.EmbedLinks,
        PermissionsBitField.Flags.ManageChannels,
      ],
    },
  ];

  let channel;
  try {
    channel = await guild.channels.create({
      name,
      type: ChannelType.GuildText,
      parent: category.id,
      topic: `${type.label} | 작성자: ${interaction.user.tag} (${interaction.user.id}) | 생성: ${formatKst(createdAt)}`,
      permissionOverwrites: overwrites,
      reason: `${type.label} 티켓 생성 (${interaction.user.tag})`,
    });
  } catch (error) {
    log.error('티켓 채널 생성 실패', error?.message ?? error);
    await interaction.editReply({
      embeds: [
        errorEmbed(
          '티켓을 만들지 못했습니다',
          '봇에게 채널 관리 권한이 있는지, 카테고리의 채널 개수 제한(50개)에 걸리지 않았는지 확인해 주세요.',
        ),
      ],
    });
    return;
  }

  const ticket = {
    channelId: channel.id,
    guildId: guild.id,
    type: type.value,
    typeLabel: type.label,
    number,
    name,
    ownerId: interaction.user.id,
    ownerTag: interaction.user.tag,
    createdAt,
  };

  store.addTicket(ticket);

  try {
    const controlMessage = await channel.send(buildTicketControlPayload(ticket));
    await controlMessage.pin().catch(() => {});
  } catch (error) {
    log.error('티켓 안내 메시지 전송 실패', error?.message ?? error);
  }

  await interaction.editReply({
    embeds: [
      buildEmbed({
        title: '티켓이 만들어졌습니다',
        color: config.colors.success,
        description: `<#${channel.id}> 채널에서 문의를 이어가 주세요.`,
        fields: [
          { name: '티켓 번호', value: name, inline: true },
          { name: '문의 종류', value: type.label, inline: true },
          { name: '만들어진 시간', value: formatKst(createdAt) },
        ],
        footer: { text: '예천군 티켓 시스템' },
      }),
    ],
  });

  await resetPanel(interaction);
  log.info(`티켓 생성: ${name} (${channel.id}) - ${interaction.user.tag}`);
}

/** 드롭다운에 선택된 항목이 남아 있지 않도록 패널을 새로 고칩니다. */
async function resetPanel(interaction) {
  try {
    if (interaction.message?.editable) {
      await interaction.message.edit(buildTicketPanelPayload());
    }
  } catch (error) {
    log.debug('티켓 패널 새로 고침 실패', error?.message ?? error);
  }
}

// --- 티켓 닫기 ---

function isStaff(member) {
  if (!member) return false;
  if (member.roles?.cache?.has(config.ticketStaffRoleId)) return true;
  return Boolean(member.permissions?.has(PermissionsBitField.Flags.Administrator));
}

/** 저장소에 없으면 채널 정보로 티켓 데이터를 복원합니다. */
function resolveTicket(channel) {
  const stored = store.getTicket(channel.id);
  if (stored) return stored;

  const type = TICKET_TYPES.find((item) => channel.name.startsWith(item.prefix)) ?? null;
  const numberMatch = channel.name.match(/(\d{1,6})$/);
  const ownerMatch = channel.topic?.match(/\((\d{17,20})\)/);

  return {
    channelId: channel.id,
    guildId: channel.guildId,
    type: type?.value ?? 'unknown',
    typeLabel: type?.label ?? '알 수 없음',
    number: numberMatch ? Number(numberMatch[1]) : null,
    name: channel.name,
    ownerId: ownerMatch?.[1] ?? null,
    ownerTag: null,
    createdAt: channel.createdTimestamp,
    recovered: true,
  };
}

export async function handleTicketCloseRequest(interaction) {
  const channel = interaction.channel;

  if (!interaction.guild || !channel) {
    await interaction.reply(
      ephemeral(errorEmbed('사용 불가', '이 기능은 서버 채널에서만 사용할 수 있습니다.')),
    );
    return;
  }

  if (!isStaff(interaction.member)) {
    await interaction.reply(
      ephemeral(
        errorEmbed(
          '권한이 없습니다',
          `티켓은 <@&${config.ticketStaffRoleId}> 역할을 가진 스태프만 닫을 수 있습니다.`,
        ),
      ),
    );
    return;
  }

  if (closingChannels.has(channel.id)) {
    await interaction.reply(
      ephemeral(warningEmbed('처리 중입니다', '이 티켓은 이미 닫히는 중입니다. 잠시만 기다려 주세요.')),
    );
    return;
  }

  const ticket = resolveTicket(channel);

  const embed = buildEmbed({
    title: '티켓을 닫을까요',
    color: config.colors.warning,
    description: [
      `**${ticket.name}** 티켓을 닫습니다.`,
      '',
      '대화 내용, 이미지, 동영상, 링크, 첨부파일이 모두 HTML 기록으로 저장되어',
      `<#${config.ticketTranscriptChannelId}> 채널로 전송된 뒤 이 채널은 삭제됩니다.`,
      '',
      '이 작업은 되돌릴 수 없습니다.',
    ].join('\n'),
    footer: { text: '예천군 티켓 시스템' },
  });

  const row = new ActionRowBuilder().addComponents(
    new ButtonBuilder()
      .setCustomId(TICKET_IDS.closeConfirm)
      .setLabel('닫기 확인')
      .setStyle(ButtonStyle.Danger),
    new ButtonBuilder()
      .setCustomId(TICKET_IDS.closeCancel)
      .setLabel('취소')
      .setStyle(ButtonStyle.Secondary),
  );

  await interaction.reply(ephemeral(embed, [row]));
}

export async function handleTicketCloseCancel(interaction) {
  await interaction.update({
    embeds: [
      buildEmbed({
        title: '취소되었습니다',
        color: config.colors.neutral,
        description: '티켓은 그대로 열려 있습니다.',
        footer: { text: '예천군 티켓 시스템' },
      }),
    ],
    components: [],
  });
}

export async function handleTicketCloseConfirm(interaction) {
  const channel = interaction.channel;
  const guild = interaction.guild;

  if (!guild || !channel) {
    await interaction.update({
      embeds: [errorEmbed('사용 불가', '이 기능은 서버 채널에서만 사용할 수 있습니다.')],
      components: [],
    });
    return;
  }

  if (!isStaff(interaction.member)) {
    await interaction.update({
      embeds: [
        errorEmbed('권한이 없습니다', `<@&${config.ticketStaffRoleId}> 역할을 가진 스태프만 닫을 수 있습니다.`),
      ],
      components: [],
    });
    return;
  }

  if (closingChannels.has(channel.id)) {
    await interaction.update({
      embeds: [warningEmbed('처리 중입니다', '이 티켓은 이미 닫히는 중입니다.')],
      components: [],
    });
    return;
  }

  closingChannels.add(channel.id);

  await interaction.update({
    embeds: [
      buildEmbed({
        title: '티켓을 닫는 중입니다',
        color: config.colors.warning,
        description: '대화 내용을 모아 기록 파일을 만들고 있습니다. 잠시만 기다려 주세요.',
        footer: { text: '예천군 티켓 시스템' },
      }),
    ],
    components: [],
  });

  const ticket = resolveTicket(channel);
  const closedAt = Date.now();

  try {
    await channel.send({
      embeds: [
        buildEmbed({
          title: '티켓이 닫힙니다',
          color: config.colors.danger,
          description: [
            `${interaction.user} 님이 이 티켓을 닫았습니다.`,
            '',
            '대화 기록을 저장하는 중이며, 저장이 끝나면 이 채널은 삭제됩니다.',
          ].join('\n'),
          fields: [
            { name: '만들어진 시간', value: formatKst(ticket.createdAt), inline: true },
            { name: '닫힌 시간', value: formatKst(closedAt), inline: true },
          ],
          footer: { text: '예천군 티켓 시스템' },
        }),
      ],
    });
  } catch (error) {
    log.debug('티켓 종료 안내 전송 실패', error?.message ?? error);
  }

  let result = null;
  try {
    const { messages, truncated } = await fetchAllMessages(channel);
    result = await buildTranscriptHtml({
      guild,
      channel,
      ticket,
      messages,
      truncated,
      closedBy: { tag: interaction.user.tag, id: interaction.user.id },
      closedAt,
    });
  } catch (error) {
    log.error('기록 생성 실패', error?.stack ?? error);
  }

  const transcriptChannel = await guild.channels
    .fetch(config.ticketTranscriptChannelId)
    .catch(() => null);

  if (!transcriptChannel || !transcriptChannel.isTextBased()) {
    log.error(`기록 채널(${config.ticketTranscriptChannelId})을 찾지 못했습니다.`);
  } else if (result) {
    await sendTranscript({ transcriptChannel, guild, ticket, result, interaction, closedAt });
  } else {
    await transcriptChannel
      .send({
        embeds: [
          errorEmbed(
            '티켓 기록 생성 실패',
            [
              `**${ticket.name}** 티켓의 기록 파일을 만들지 못했습니다.`,
              `닫은 사람: ${interaction.user.tag} (${interaction.user.id})`,
              `닫힌 시간: ${formatKst(closedAt)}`,
            ].join('\n'),
          ),
        ],
      })
      .catch(() => {});
  }

  store.removeTicket(channel.id);

  const delay = Math.max(0, config.ticketDeleteDelaySeconds) * 1000;
  if (delay > 0) await sleep(delay);

  try {
    await channel.delete(`티켓 종료 (${interaction.user.tag})`);
    log.info(`티켓 종료: ${ticket.name} (${channel.id}) - ${interaction.user.tag}`);
  } catch (error) {
    log.error('티켓 채널 삭제 실패', error?.message ?? error);
  } finally {
    closingChannels.delete(channel.id);
  }
}

async function sendTranscript({ transcriptChannel, guild, ticket, result, interaction, closedAt }) {
  const buffer = Buffer.from(result.html, 'utf8');
  const safeName = ticket.name.replace(/[\\/:*?"<>|]/g, '_');
  const fileName = `${safeName}.html`;

  const summary = buildEmbed({
    title: `${ticket.name} 티켓 기록`,
    color: config.colors.neutral,
    description: [
      `**${ticket.typeLabel}** 티켓이 종료되어 기록을 저장했습니다.`,
      '',
      '첨부된 HTML 파일을 내려받아 열면 대화 내용, 이미지, 동영상, 링크, 첨부파일을 모두 확인할 수 있습니다.',
    ].join('\n'),
    fields: [
      { name: '티켓 이름', value: ticket.name, inline: true },
      { name: '문의 종류', value: ticket.typeLabel, inline: true },
      {
        name: '작성자',
        value: ticket.ownerId ? `<@${ticket.ownerId}> (${ticket.ownerId})` : '알 수 없음',
      },
      { name: '만들어진 시간', value: formatKst(result.stats.createdAt), inline: true },
      { name: '닫힌 시간', value: formatKst(closedAt), inline: true },
      { name: '유지 시간', value: result.stats.duration, inline: true },
      { name: '닫은 사람', value: `${interaction.user} (${interaction.user.id})` },
      {
        name: '기록 요약',
        value: [
          `메시지 ${result.stats.messageCount}개`,
          `참여자 ${result.stats.participantCount}명`,
          `첨부파일 ${result.stats.attachmentCount}개`,
          `링크 ${result.stats.linkCount}개`,
        ].join(' · '),
      },
      { name: '기록 파일 크기', value: `${(buffer.byteLength / 1024).toFixed(1)} KB`, inline: true },
      { name: '서버', value: guild.name, inline: true },
    ],
    footer: { text: '예천군 티켓 시스템' },
  });

  if (result.stats.truncated || result.stats.inlineSkipped > 0) {
    const notes = [];
    if (result.stats.truncated) notes.push('메시지가 많아 오래된 일부는 기록에서 생략되었습니다.');
    if (result.stats.inlineSkipped > 0) {
      notes.push(`용량 제한으로 첨부파일 ${result.stats.inlineSkipped}개는 원본 링크로만 남았습니다.`);
    }
    summary.addFields({ name: '참고', value: notes.join('\n') });
  }

  if (buffer.byteLength > MAX_DISCORD_UPLOAD_BYTES) {
    log.error(`기록 파일이 너무 큽니다 (${buffer.byteLength} 바이트). 첨부 없이 전송합니다.`);
    summary.addFields({
      name: '경고',
      value: '기록 파일이 업로드 한도를 넘어 첨부하지 못했습니다. 설정에서 첨부파일 포함 용량을 줄여 주세요.',
    });
    await transcriptChannel.send({ embeds: [summary] }).catch((error) => {
      log.error('기록 전송 실패', error?.message ?? error);
    });
    return;
  }

  try {
    await transcriptChannel.send({
      embeds: [summary],
      files: [new AttachmentBuilder(buffer, { name: fileName, description: `${ticket.name} 티켓 기록` })],
    });
  } catch (error) {
    log.error('기록 전송 실패', error?.message ?? error);
  }
}

export function isTicketCustomId(customId) {
  return customId.startsWith('ticket:');
}
