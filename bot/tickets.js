import {
  AttachmentBuilder,
  ButtonBuilder,
  ButtonStyle,
  ChannelType,
  PermissionsBitField,
  StringSelectMenuBuilder,
} from 'discord.js';

import { config, TICKET_TYPES, getTicketType } from './config.js';
import { log } from './log.js';
import { formatBusinessHours, formatKst, isBusinessHours, sleep } from './time.js';
import { editPayload, errorPanel, neutralPanel, panel, payload, warningPanel } from './components.js';
import { ensurePanel } from './panel.js';
import { buildTranscriptHtml, fetchAllMessages } from './transcript.js';

const FOOTER = `${config.brandName} 문의`;

export const TICKET_IDS = {
  select: 'ticket:create',
  close: 'ticket:close',
  closeConfirm: 'ticket:close:confirm',
  closeCancel: 'ticket:close:cancel',
};

const MAX_DISCORD_UPLOAD_BYTES = 9 * 1024 * 1024;
const TRANSCRIPT_SCAN_PAGES = 2;

const closingChannels = new Set();
// 같은 종류의 티켓 번호가 겹치지 않도록 종류별로 순서를 지켜 만듭니다.
const creationQueues = new Map();

function escapeRegExp(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// --- 패널 ---

export function buildTicketPanelPayload() {
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

  const container = panel({
    color: config.colors.primary,
    title: '문의하기',
    description: '아래에서 문의 종류를 선택해 주세요.',
    fields: [
      { name: '문의 시간', value: formatBusinessHours() },
      ...TICKET_TYPES.map((type) => ({ name: type.label, value: type.description })),
    ],
    image: config.ticketPanelImageUrl,
    buttons: [menu],
    footer: FOOTER,
  });

  return payload(container);
}

export async function deployTicketPanel(client) {
  return ensurePanel(client, {
    name: 'ticket',
    channelId: config.ticketPanelChannelId,
    markers: [TICKET_IDS.select],
    payload: buildTicketPanelPayload(),
  });
}

export function buildTicketControlPayload(ticket, openDuringBusinessHours) {
  const fields = [
    { name: '문의 번호', value: ticket.name },
    { name: '접수 시간', value: formatKst(ticket.createdAt) },
  ];

  if (openDuringBusinessHours) {
    fields.push({ name: '담당', value: `<@&${config.ticketStaffRoleId}>` });
  } else {
    fields.push({
      name: '문의 시간',
      value: `${formatBusinessHours()}\n지금은 문의 시간이 아닙니다. 문의 시간에 순서대로 답변드립니다.`,
    });
  }

  const container = panel({
    color: config.colors.primary,
    title: ticket.typeLabel,
    description: `<@${ticket.ownerId}> 님, 문의 내용을 남겨 주세요.`,
    fields,
    buttons: [
      new ButtonBuilder()
        .setCustomId(TICKET_IDS.close)
        .setLabel('문의 닫기')
        .setStyle(ButtonStyle.Danger),
    ],
    footer: FOOTER,
  });

  const message = payload(container);
  // 문의 시간 안에 올라온 문의만 담당 역할을 부릅니다.
  message.allowedMentions = {
    users: [ticket.ownerId],
    roles: openDuringBusinessHours ? [config.ticketStaffRoleId] : [],
  };

  return message;
}

// --- 열려 있는 문의 찾기 ---

export function findOpenTicket(guild, ownerId, type) {
  return (
    guild.channels.cache.find(
      (channel) =>
        channel.parentId === type.categoryId &&
        channel.name.startsWith(`${type.prefix}-`) &&
        typeof channel.topic === 'string' &&
        channel.topic.includes(`(${ownerId})`),
    ) ?? null
  );
}

// --- 문의 번호 ---

/**
 * 다음 문의 번호를 정합니다.
 * 별도 저장 파일 없이, 열려 있는 채널 이름과 기록 채널에 올라간 파일 이름에서 가장 큰 번호를 찾습니다.
 */
export async function findNextNumber(guild, type) {
  const channelPattern = new RegExp(`^${escapeRegExp(type.prefix)}-(\\d{1,6})$`);
  const filePattern = new RegExp(`^${escapeRegExp(type.prefix)}-(\\d{1,6})\\.html$`, 'i');
  let max = 0;

  for (const channel of guild.channels.cache.values()) {
    if (channel.parentId !== type.categoryId) continue;
    const match = channel.name.match(channelPattern);
    if (match) max = Math.max(max, Number(match[1]));
  }

  const transcriptChannel = await guild.channels
    .fetch(config.ticketTranscriptChannelId)
    .catch(() => null);

  if (transcriptChannel?.isTextBased()) {
    let before;
    for (let page = 0; page < TRANSCRIPT_SCAN_PAGES; page += 1) {
      const batch = await transcriptChannel.messages
        .fetch({ limit: 100, ...(before ? { before } : {}) })
        .catch(() => null);

      if (!batch || batch.size === 0) break;

      for (const message of batch.values()) {
        for (const attachment of message.attachments.values()) {
          const match = attachment.name?.match(filePattern);
          if (match) max = Math.max(max, Number(match[1]));
        }
      }

      const ordered = [...batch.values()];
      before = ordered[ordered.length - 1].id;
      if (batch.size < 100) break;
    }
  }

  return max + 1;
}

/** 같은 종류의 문의는 한 번에 하나씩만 만들어 번호가 겹치지 않게 합니다. */
function queueCreation(guild, type, task) {
  const key = `${guild.id}:${type.value}`;
  const previous = creationQueues.get(key) ?? Promise.resolve();
  const next = previous.then(task, task);
  creationQueues.set(
    key,
    next.then(
      () => {
        if (creationQueues.get(key) === next) creationQueues.delete(key);
      },
      () => {
        if (creationQueues.get(key) === next) creationQueues.delete(key);
      },
    ),
  );
  return next;
}

// --- 문의 만들기 ---

export async function handleTicketCreate(interaction) {
  // 먼저 컨테이너로 응답해야 뒤이은 editReply 도 Components V2 로 유지됩니다.
  await interaction.reply(
    payload(neutralPanel('잠시만 기다려 주세요', '문의 채널을 만들고 있습니다.', { footer: FOOTER }), {
      ephemeral: true,
    }),
  );

  const guild = interaction.guild;
  if (!guild) {
    await interaction.editReply(
      editPayload(errorPanel('문의를 열 수 없습니다', '서버 안에서만 사용할 수 있습니다.', { footer: FOOTER })),
    );
    return;
  }

  const type = getTicketType(interaction.values?.[0]);
  if (!type) {
    await interaction.editReply(
      editPayload(errorPanel('문의를 열 수 없습니다', '문의 종류를 다시 선택해 주세요.', { footer: FOOTER })),
    );
    return;
  }

  const existing = findOpenTicket(guild, interaction.user.id, type);
  if (existing) {
    await interaction.editReply(
      editPayload(
        warningPanel('이미 열려 있는 문의가 있습니다', `<#${existing.id}> 에서 이어서 말씀해 주세요.`, {
          footer: FOOTER,
        }),
      ),
    );
    await resetPanel(interaction);
    return;
  }

  const category = await guild.channels.fetch(type.categoryId).catch(() => null);
  if (!category || category.type !== ChannelType.GuildCategory) {
    log.error(`${type.label} 카테고리(${type.categoryId})를 찾을 수 없거나 카테고리가 아닙니다.`);
    await interaction.editReply(
      editPayload(
        errorPanel('문의를 열 수 없습니다', '잠시 후 다시 시도해 주세요.', { footer: FOOTER }),
      ),
    );
    return;
  }

  const createdAt = Date.now();
  const openDuringBusinessHours = isBusinessHours(createdAt);

  let channel = null;
  let name = null;

  try {
    ({ channel, name } = await queueCreation(guild, type, async () => {
      const number = await findNextNumber(guild, type);
      const channelName = `${type.prefix}-${String(number).padStart(4, '0')}`;

      const created = await guild.channels.create({
        name: channelName,
        type: ChannelType.GuildText,
        parent: category.id,
        topic: `${type.label} | 작성자: ${interaction.user.tag} (${interaction.user.id}) | 접수: ${formatKst(createdAt)}`,
        permissionOverwrites: buildOverwrites(guild, interaction),
        reason: `${type.label} 접수 (${interaction.user.tag})`,
      });

      return { channel: created, name: channelName };
    }));
  } catch (error) {
    log.error('문의 채널 생성 실패', error?.message ?? error);
    await interaction.editReply(
      editPayload(
        errorPanel(
          '문의를 열 수 없습니다',
          '잠시 후 다시 시도해 주세요. 계속 안 되면 스태프에게 알려 주세요.',
          { footer: FOOTER },
        ),
      ),
    );
    return;
  }

  const ticket = {
    channelId: channel.id,
    guildId: guild.id,
    type: type.value,
    typeLabel: type.label,
    name,
    ownerId: interaction.user.id,
    ownerTag: interaction.user.tag,
    createdAt,
  };

  try {
    const controlMessage = await channel.send(buildTicketControlPayload(ticket, openDuringBusinessHours));
    await controlMessage.pin().catch(() => {});
  } catch (error) {
    log.error('문의 안내 메시지 전송 실패', error?.message ?? error);
  }

  await interaction.editReply(
    editPayload(
      panel({
        color: config.colors.success,
        title: '문의가 접수되었습니다',
        description: `<#${channel.id}> 에서 이어서 말씀해 주세요.`,
        fields: [
          { name: '문의 번호', value: name },
          ...(openDuringBusinessHours
            ? []
            : [
                {
                  name: '문의 시간',
                  value: `${formatBusinessHours()}\n지금은 문의 시간이 아닙니다. 문의 시간에 순서대로 답변드립니다.`,
                },
              ]),
        ],
        footer: FOOTER,
      }),
    ),
  );

  await resetPanel(interaction);
  log.info(
    `문의 접수: ${name} (${channel.id}) - ${interaction.user.tag} / 담당 호출 ${openDuringBusinessHours ? '함' : '안 함'}`,
  );
}

function buildOverwrites(guild, interaction) {
  return [
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
}

/** 드롭다운에 선택된 항목이 남아 있지 않도록 패널을 새로 고칩니다. */
async function resetPanel(interaction) {
  try {
    if (interaction.message?.editable) {
      await interaction.message.edit(buildTicketPanelPayload());
    }
  } catch (error) {
    log.debug('문의 패널 새로 고침 실패', error?.message ?? error);
  }
}

// --- 문의 닫기 ---

function isStaff(member) {
  if (!member) return false;
  if (member.roles?.cache?.has(config.ticketStaffRoleId)) return true;
  return Boolean(member.permissions?.has(PermissionsBitField.Flags.Administrator));
}

/** 채널 이름과 주제만 보고 문의 정보를 되살립니다. */
function resolveTicket(channel) {
  const type = TICKET_TYPES.find((item) => channel.name.startsWith(`${item.prefix}-`)) ?? null;
  const ownerMatch = channel.topic?.match(/\((\d{17,20})\)/);

  return {
    channelId: channel.id,
    guildId: channel.guildId,
    type: type?.value ?? 'unknown',
    typeLabel: type?.label ?? '문의',
    name: channel.name,
    ownerId: ownerMatch?.[1] ?? null,
    ownerTag: null,
    createdAt: channel.createdTimestamp,
  };
}

export async function handleTicketCloseRequest(interaction) {
  const channel = interaction.channel;

  if (!interaction.guild || !channel) {
    await interaction.reply(
      payload(errorPanel('사용할 수 없습니다', '서버 채널에서만 사용할 수 있습니다.', { footer: FOOTER }), {
        ephemeral: true,
      }),
    );
    return;
  }

  if (!isStaff(interaction.member)) {
    await interaction.reply(
      payload(errorPanel('권한이 없습니다', '스태프만 문의를 닫을 수 있습니다.', { footer: FOOTER }), {
        ephemeral: true,
      }),
    );
    return;
  }

  if (closingChannels.has(channel.id)) {
    await interaction.reply(
      payload(warningPanel('처리 중입니다', '잠시만 기다려 주세요.', { footer: FOOTER }), {
        ephemeral: true,
      }),
    );
    return;
  }

  const ticket = resolveTicket(channel);

  await interaction.reply(
    payload(
      panel({
        color: config.colors.warning,
        title: '문의를 닫습니다',
        description: `**${ticket.name}** 을 닫고 이 채널을 삭제합니다.\n되돌릴 수 없습니다.`,
        buttons: [
          new ButtonBuilder()
            .setCustomId(TICKET_IDS.closeConfirm)
            .setLabel('닫기')
            .setStyle(ButtonStyle.Danger),
          new ButtonBuilder()
            .setCustomId(TICKET_IDS.closeCancel)
            .setLabel('취소')
            .setStyle(ButtonStyle.Secondary),
        ],
        footer: FOOTER,
      }),
      { ephemeral: true },
    ),
  );
}

export async function handleTicketCloseCancel(interaction) {
  await interaction.update(
    editPayload(neutralPanel('취소되었습니다', '문의는 그대로 열려 있습니다.', { footer: FOOTER })),
  );
}

export async function handleTicketCloseConfirm(interaction) {
  const channel = interaction.channel;
  const guild = interaction.guild;

  if (!guild || !channel) {
    await interaction.update(
      editPayload(errorPanel('사용할 수 없습니다', '서버 채널에서만 사용할 수 있습니다.', { footer: FOOTER })),
    );
    return;
  }

  if (!isStaff(interaction.member)) {
    await interaction.update(
      editPayload(errorPanel('권한이 없습니다', '스태프만 문의를 닫을 수 있습니다.', { footer: FOOTER })),
    );
    return;
  }

  if (closingChannels.has(channel.id)) {
    await interaction.update(
      editPayload(warningPanel('처리 중입니다', '잠시만 기다려 주세요.', { footer: FOOTER })),
    );
    return;
  }

  closingChannels.add(channel.id);

  await interaction.update(
    editPayload(neutralPanel('닫는 중입니다', '기록을 만들고 있습니다.', { footer: FOOTER })),
  );

  const ticket = resolveTicket(channel);
  const closedAt = Date.now();

  try {
    await channel.send(
      payload(
        panel({
          color: config.colors.danger,
          title: '문의가 닫혔습니다',
          description: `${interaction.user} 님이 문의를 닫았습니다.\n이 채널은 곧 삭제됩니다.`,
          footer: FOOTER,
        }),
      ),
    );
  } catch (error) {
    log.debug('문의 종료 안내 전송 실패', error?.message ?? error);
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
      .send(
        payload(
          errorPanel(
            '기록을 만들지 못했습니다',
            [
              `**${ticket.name}**`,
              `닫은 사람: ${interaction.user.tag} (${interaction.user.id})`,
              `닫힌 시간: ${formatKst(closedAt)}`,
            ].join('\n'),
            { footer: FOOTER },
          ),
        ),
      )
      .catch(() => {});
  }

  const delay = Math.max(0, config.ticketDeleteDelaySeconds) * 1000;
  if (delay > 0) await sleep(delay);

  try {
    await channel.delete(`문의 종료 (${interaction.user.tag})`);
    log.info(`문의 종료: ${ticket.name} (${channel.id}) - ${interaction.user.tag}`);
  } catch (error) {
    log.error('문의 채널 삭제 실패', error?.message ?? error);
  } finally {
    closingChannels.delete(channel.id);
  }
}

async function sendTranscript({ transcriptChannel, guild, ticket, result, interaction, closedAt }) {
  const buffer = Buffer.from(result.html, 'utf8');
  // 파일 이름이 곧 문의 번호 기록이 됩니다. 다음 번호를 정할 때 이 이름을 읽습니다.
  const fileName = `${ticket.name.replace(/[\\/:*?"<>|]/g, '_')}.html`;

  const notes = [];
  if (result.stats.truncated) notes.push('메시지가 많아 오래된 일부는 빠졌습니다.');
  if (result.stats.inlineSkipped > 0) {
    notes.push(`용량이 큰 첨부파일 ${result.stats.inlineSkipped}개는 링크로만 남았습니다.`);
  }

  const tooBig = buffer.byteLength > MAX_DISCORD_UPLOAD_BYTES;
  if (tooBig) {
    log.error(`기록 파일이 너무 큽니다 (${buffer.byteLength} 바이트). 첨부 없이 전송합니다.`);
    notes.push('기록 파일이 너무 커서 첨부하지 못했습니다.');
  }

  const fields = [
    { name: '문의 종류', value: ticket.typeLabel },
    { name: '작성자', value: ticket.ownerId ? `<@${ticket.ownerId}> (${ticket.ownerId})` : '알 수 없음' },
    { name: '접수 시간', value: formatKst(result.stats.createdAt) },
    { name: '닫힌 시간', value: formatKst(closedAt) },
    { name: '유지 시간', value: result.stats.duration },
    { name: '닫은 사람', value: `${interaction.user} (${interaction.user.id})` },
    {
      name: '요약',
      value: [
        `메시지 ${result.stats.messageCount}개`,
        `참여자 ${result.stats.participantCount}명`,
        `첨부파일 ${result.stats.attachmentCount}개`,
        `링크 ${result.stats.linkCount}개`,
      ].join(' · '),
    },
  ];

  if (notes.length > 0) fields.push({ name: '참고', value: notes.join('\n') });

  const container = panel({
    color: config.colors.neutral,
    title: `${ticket.name} 기록`,
    description: '아래 HTML 파일을 내려받으면 대화 내용을 볼 수 있습니다.',
    fields,
    footer: `${config.brandName} 문의 기록 · ${guild.name}`,
  });

  const message = payload(container);
  if (!tooBig) {
    message.files = [new AttachmentBuilder(buffer, { name: fileName, description: `${ticket.name} 기록` })];
  }

  try {
    await transcriptChannel.send(message);
  } catch (error) {
    log.error('기록 전송 실패', error?.message ?? error);
  }
}

export function isTicketCustomId(customId) {
  return customId.startsWith('ticket:');
}
