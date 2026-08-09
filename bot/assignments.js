import {
  ActionRowBuilder,
  ButtonBuilder,
  ButtonStyle,
  ModalBuilder,
  PermissionsBitField,
  StringSelectMenuBuilder,
  TextInputBuilder,
  TextInputStyle,
} from 'discord.js';

import { WORK_FIELDS, config, isWorkField } from './config.js';
import { canUseCommand, deniedReason, isAdminMember } from './permissions.js';
import { log } from './log.js';
import { formatKst, formatDuration } from './time.js';
import { editPayload, errorPanel, neutralPanel, panel, payload, successPanel, warningPanel } from './components.js';
import {
  MARKERS,
  addRecord,
  getRecord,
  listRecords,
  makeRecordId,
  readSettings,
  updateRecord,
  writeSettings,
  StorageError,
} from './storage.js';

const FOOTER = `${config.brandName} 업무 배당`;
const MIN_REJECT_REASON = 10;

/**
 * 배당과 수리는 흐름이 같고 문구만 다릅니다.
 * 기록에 kind 를 넣어 두고, 화면에 나갈 말만 여기서 갈라 씁니다.
 * 그래서 수락, 거절, 기간 조정, 연장, 기간 지남 처리는 둘이 그대로 같이 씁니다.
 */
const KINDS = {
  assign: {
    listTitle: '배당 목록',
    offerTitle: '해당 프로젝트를 맡으시겠습니까?',
    accept: '배당 수락',
    reject: '배당 거절',
    footer: `${config.brandName} 업무 배당`,
  },
  repair: {
    listTitle: '수리 목록',
    offerTitle: '해당 수리를 맡으시겠습니까?',
    accept: '수리 수락',
    reject: '수리 거절',
    footer: `${config.brandName} 수리`,
  },
};

function labels(record) {
  return KINDS[record?.kind === 'repair' ? 'repair' : 'assign'];
}

export const ASSIGN_IDS = {
  pick: 'assign:pick',
  newForm: 'assign:new',
  accept: 'assign:accept',
  reject: 'assign:reject',
  acceptForm: 'assign:acceptform',
  rejectForm: 'assign:rejectform',
  adjust: 'assign:adjust',
  adjustForm: 'assign:adjustform',
  adjustAccept: 'assign:adjustok',
  adjustReject: 'assign:adjustno',
  adjustRejectForm: 'assign:adjustnoform',
  extend: 'assign:extend',
  repairPick: 'assign:rpick',
  repairForm: 'assign:rnew',
};

const STATUS_LABEL = {
  pending: '수락 대기',
  accepted: '진행 중',
  rejected: '거절됨',
  overdue: '기간 지남',
};

// --- 권한 ---

export const isAdmin = isAdminMember;

function deniedPanel(commandName = null) {
  if (commandName) {
    return errorPanel('권한이 없습니다', deniedReason(commandName), { footer: FOOTER });
  }
  return deniedPanelDefault();
}

function deniedPanelDefault() {
  return errorPanel(
    '권한이 없습니다',
    config.adminRoleId
      ? `<@&${config.adminRoleId}> 역할을 가진 사람만 쓸 수 있습니다.`
      : '총관리자 역할이 설정되지 않았습니다. .env 의 ADMIN_ROLE_ID 를 채워 주세요.',
    { footer: FOOTER },
  );
}

function storageErrorPanel(error) {
  if (error instanceof StorageError) return errorPanel('보관 채널을 쓸 수 없습니다', error.message, { footer: FOOTER });
  log.error('업무 배당 처리 오류', error?.stack ?? error);
  return errorPanel('오류가 발생했습니다', '잠시 후 다시 시도해 주세요.', { footer: FOOTER });
}

/** 비워 둘 수 있는 칸을 안전하게 읽습니다. 없으면 빈 문자열입니다. */
export function readField(interaction, name) {
  try {
    return (interaction.fields.getTextInputValue(name) ?? '').trim();
  } catch {
    return '';
  }
}

// --- 기간 입력 해석 ---

/**
 * 기간 입력을 읽어 마감 시각(밀리초)으로 바꿉니다.
 * 받는 형식
 *   숫자            시간 단위 (예: 48 -> 48시간 뒤)
 *   3일 / 12시간    단위를 붙인 값
 *   2026-08-10          그날 밤 12시
 *   2026-08-10 18:00    그 시각
 */
export function parseDeadline(input, now = Date.now()) {
  const text = String(input ?? '').trim();
  if (text.length === 0) return null;

  const unit = text.match(/^(\d+(?:\.\d+)?)\s*(일|시간|분|d|h|m)?$/i);
  if (unit) {
    const amount = Number(unit[1]);
    if (!Number.isFinite(amount) || amount <= 0) return null;
    const kind = (unit[2] ?? '시간').toLowerCase();
    const hours = kind === '일' || kind === 'd' ? amount * 24 : kind === '분' || kind === 'm' ? amount / 60 : amount;
    if (hours > 24 * 365) return null;
    return Math.round(now + hours * 3600_000);
  }

  const date = text.match(/^(\d{4})[-./](\d{1,2})[-./](\d{1,2})(?:\s+(\d{1,2}):(\d{2}))?$/);
  if (date) {
    const year = Number(date[1]);
    const month = Number(date[2]);
    const day = Number(date[3]);
    const hour = date[4] === undefined ? 23 : Number(date[4]);
    const minute = date[5] === undefined ? 59 : Number(date[5]);

    if (month < 1 || month > 12) return null;
    if (day < 1 || day > 31) return null;
    if (hour > 23 || minute > 59) return null;

    // 입력은 한국 시간으로 봅니다. (KST = UTC+9)
    const utc = Date.UTC(year, month - 1, day, hour, minute);
    const check = new Date(utc);

    // Date.UTC 는 2026-02-30 처럼 없는 날짜를 다음 달로 넘겨 버립니다.
    // 넣은 값 그대로 나오는지 확인해서 걸러냅니다.
    if (
      check.getUTCFullYear() !== year ||
      check.getUTCMonth() !== month - 1 ||
      check.getUTCDate() !== day
    ) {
      return null;
    }

    return utc - 9 * 3600_000;
  }

  return null;
}

// --- 분야 설정 ---

export async function handleFieldSetupCommand(interaction) {
  await interaction.reply(
    payload(neutralPanel('잠시만 기다려 주세요', '설정을 불러오고 있습니다.', { footer: FOOTER }), {
      ephemeral: true,
    }),
  );

  if (!canUseCommand(interaction.member, interaction.commandName)) {
    await interaction.editReply(editPayload(deniedPanel(interaction.commandName)));
    return;
  }

  const user = interaction.options.getUser('유저');
  const field = interaction.options.getString('분야').trim();
  const nickname = interaction.options.getString('별명').trim();

  if (!isWorkField(field)) {
    await interaction.editReply(
      editPayload(
        errorPanel('없는 분야입니다', `쓸 수 있는 분야: ${WORK_FIELDS.join(', ')}`, { footer: FOOTER }),
      ),
    );
    return;
  }

  if (nickname.length === 0 || nickname.length > 30) {
    await interaction.editReply(
      editPayload(errorPanel('별명이 올바르지 않습니다', '1자에서 30자 사이로 적어 주세요.', { footer: FOOTER })),
    );
    return;
  }

  let settings;
  try {
    settings = await readSettings(interaction.client);
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  const index = settings.fields.findIndex((entry) => entry.userId === user.id && entry.field === field);
  const entry = { userId: user.id, field, nickname };

  if (index === -1) settings.fields.push(entry);
  else settings.fields[index] = entry;

  try {
    await writeSettings(interaction.client, settings);
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  await interaction.editReply(
    editPayload(
      successPanel(index === -1 ? '등록했습니다' : '고쳤습니다', `${user} 님을 **${field}** 분야에 넣었습니다.`, {
        fields: [{ name: '별명', value: nickname }],
        footer: FOOTER,
      }),
    ),
  );
}

export async function handleFieldListCommand(interaction) {
  await interaction.reply(
    payload(neutralPanel('잠시만 기다려 주세요', '분야를 불러오고 있습니다.', { footer: FOOTER }), {
      ephemeral: true,
    }),
  );

  let settings;
  try {
    settings = await readSettings(interaction.client);
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  await interaction.editReply(
    editPayload(
      panel({
        color: config.colors.neutral,
        title: '분야별 직원',
        description: formatFieldList(settings.fields),
        footer: FOOTER,
      }),
    ),
  );
}

export async function handleFieldRemoveCommand(interaction) {
  await interaction.reply(
    payload(neutralPanel('잠시만 기다려 주세요', '설정을 불러오고 있습니다.', { footer: FOOTER }), {
      ephemeral: true,
    }),
  );

  if (!canUseCommand(interaction.member, interaction.commandName)) {
    await interaction.editReply(editPayload(deniedPanel(interaction.commandName)));
    return;
  }

  const user = interaction.options.getUser('유저');
  const field = interaction.options.getString('분야').trim();

  let settings;
  try {
    settings = await readSettings(interaction.client);
    const before = settings.fields.length;
    settings.fields = settings.fields.filter(
      (entry) => !(entry.userId === user.id && entry.field === field),
    );

    if (settings.fields.length === before) {
      await interaction.editReply(
        editPayload(errorPanel('없는 등록입니다', `${user} 님은 **${field}** 분야에 없습니다.`, { footer: FOOTER })),
      );
      return;
    }

    await writeSettings(interaction.client, settings);
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  await interaction.editReply(
    editPayload(successPanel('지웠습니다', `${user} 님을 **${field}** 분야에서 뺐습니다.`, { footer: FOOTER })),
  );
}

/**
 * 정해진 분야를 전부 보여 줍니다. 아무도 없는 분야는 비어 있다고 적습니다.
 *
 * @param {Array<{userId: string, field: string, nickname: string}>} entries
 */
export function formatFieldList(entries) {
  return WORK_FIELDS.map((field) => {
    const members = entries.filter((entry) => entry.field === field);
    const body =
      members.length > 0
        ? members.map((entry) => `${entry.nickname} - <@${entry.userId}>`).join('\n')
        : '비어 있음';
    return `**${field}**\n${body}`;
  }).join('\n\n');
}

// --- 배당 시작 ---

export async function handleAssignCommand(interaction) {
  await interaction.reply(
    payload(neutralPanel('잠시만 기다려 주세요', '직원 목록을 불러오고 있습니다.', { footer: FOOTER }), {
      ephemeral: true,
    }),
  );

  if (!canUseCommand(interaction.member, interaction.commandName)) {
    await interaction.editReply(editPayload(deniedPanel(interaction.commandName)));
    return;
  }

  const field = interaction.options.getString('분야').trim();

  let settings;
  try {
    settings = await readSettings(interaction.client);
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  const entries = settings.fields.filter((entry) => entry.field === field).slice(0, 25);

  if (entries.length === 0) {
    await interaction.editReply(
      editPayload(
        errorPanel('직원이 없습니다', `**${field}** 분야에 등록된 직원이 없습니다.\n\`/분야설정\` 으로 먼저 등록해 주세요.`, {
          footer: FOOTER,
        }),
      ),
    );
    return;
  }

  const menu = new StringSelectMenuBuilder()
    .setCustomId(ASSIGN_IDS.pick)
    .setPlaceholder('배당할 직원을 선택해 주세요')
    .setMinValues(1)
    .setMaxValues(1)
    .addOptions(
      entries.map((entry) => ({
        label: entry.nickname.slice(0, 100),
        value: entry.userId,
        description: `${entry.field}`.slice(0, 100),
      })),
    );

  await interaction.editReply(
    editPayload(
      panel({
        color: config.colors.primary,
        title: '업무 배당',
        description: `**${field}** 분야입니다.\n아래 목록에서 배당할 직원을 선택해 주세요.`,
        buttons: [menu],
        footer: FOOTER,
      }),
    ),
  );
}

export async function handleAssignPick(interaction) {
  const userId = interaction.values?.[0];

  const modal = new ModalBuilder()
    .setCustomId(`${ASSIGN_IDS.newForm}:${userId}`)
    .setTitle('업무 배당');

  modal.addComponents(
    new ActionRowBuilder().addComponents(
      new TextInputBuilder()
        .setCustomId('title')
        .setLabel('업무명')
        .setStyle(TextInputStyle.Short)
        .setMaxLength(80)
        .setRequired(true),
    ),
    new ActionRowBuilder().addComponents(
      new TextInputBuilder()
        .setCustomId('description')
        .setLabel('업무 설명')
        .setStyle(TextInputStyle.Paragraph)
        .setMaxLength(900)
        .setRequired(true),
    ),
    new ActionRowBuilder().addComponents(
      new TextInputBuilder()
        .setCustomId('pay')
        .setLabel('급여')
        .setPlaceholder('예: 100,000원')
        .setStyle(TextInputStyle.Short)
        .setMaxLength(40)
        .setRequired(true),
    ),
  );

  await interaction.showModal(modal);
}

export async function handleAssignCreate(interaction) {
  const userId = interaction.customId.slice(`${ASSIGN_IDS.newForm}:`.length);

  await interaction.reply(
    payload(neutralPanel('잠시만 기다려 주세요', '배당을 등록하고 있습니다.', { footer: FOOTER }), {
      ephemeral: true,
    }),
  );

  const title = interaction.fields.getTextInputValue('title').trim();
  const description = interaction.fields.getTextInputValue('description').trim();
  const pay = interaction.fields.getTextInputValue('pay').trim();

  let settings;
  try {
    settings = await readSettings(interaction.client);
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  const entry = settings.fields.find((item) => item.userId === userId);

  const record = {
    id: makeRecordId('a'),
    userId,
    nickname: entry?.nickname ?? null,
    field: entry?.field ?? null,
    title,
    description,
    pay,
    status: 'pending',
    createdAt: Date.now(),
    createdBy: interaction.user.id,
    guildId: interaction.guildId,
    acceptedAt: null,
    dueAt: null,
    report: null,
    rejectReason: null,
    extensions: 0,
    warnings: 0,
    lastNoticeAt: null,
  };

  let saved;
  try {
    saved = await addRecord(interaction.client, MARKERS.assignment, record);
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  // 배당 목록 채널에 올립니다.
  await postToChannel(interaction.client, config.assignListChannelId, buildListContainer(saved));

  // 대상자에게 DM 을 보냅니다.
  const delivered = await sendDm(interaction.client, userId, buildOfferPayload(saved));

  await notifyAdmins(
    interaction.client,
    interaction.guild,
    panel({
      color: config.colors.primary,
      title: '새 배당',
      description: `<@${userId}> 님에게 **${title}** 을 배당했습니다.`,
      fields: [
        { name: '배당한 사람', value: `${interaction.user} (${interaction.user.id})` },
        { name: '급여', value: pay },
      ],
      footer: FOOTER,
    }),
  );

  await interaction.editReply(
    editPayload(
      delivered
        ? successPanel('배당했습니다', `<@${userId}> 님에게 **${title}** 을 보냈습니다.`, { footer: FOOTER })
        : warningPanel(
            '배당은 되었지만 DM 이 가지 않았습니다',
            `<@${userId}> 님이 DM 을 닫아 두었습니다. 직접 알려 주세요.`,
            { footer: FOOTER },
          ),
    ),
  );
}

// --- 수리 ---
//
// /수리 는 /배당 과 흐름이 같습니다.
// 이미 배당한 기록을 골라서 그 프로젝트의 수리를 다시 맡기는 것이라,
// 만들어지는 기록도 같은 자리에 kind: 'repair' 로 저장합니다.
// 그래서 수락, 거절, 기간 조정, 연장, 기간 지남 처리가 그대로 이어집니다.

/** /수리 의 프로젝트 칸에서 이미 배당한 업무를 골라 줍니다. */
export async function handleRepairAutocomplete(interaction) {
  const focused = String(interaction.options.getFocused() ?? '').toLowerCase();

  let records = [];
  try {
    records = await listRecords(interaction.client, MARKERS.assignment);
  } catch {
    records = [];
  }

  const matches = records
    .filter((record) => record.kind !== 'repair')
    .filter((record) => record.guildId === interaction.guildId)
    .filter((record) => String(record.title ?? '').toLowerCase().includes(focused))
    .reverse()
    .slice(0, 25)
    .map((record) => ({
      name: `${record.title}`.slice(0, 100),
      value: record.id,
    }));

  await interaction.respond(matches).catch(() => {});
}

export async function handleRepairCommand(interaction) {
  await interaction.reply(
    payload(neutralPanel('잠시만 기다려 주세요', '직원 목록을 불러오고 있습니다.', { footer: KINDS.repair.footer }), {
      ephemeral: true,
    }),
  );

  if (!canUseCommand(interaction.member, interaction.commandName)) {
    await interaction.editReply(editPayload(deniedPanel(interaction.commandName)));
    return;
  }

  const projectId = interaction.options.getString('프로젝트').trim();
  const field = interaction.options.getString('분야').trim();

  let settings;
  let source;
  try {
    settings = await readSettings(interaction.client);
    source = await getRecord(interaction.client, MARKERS.assignment, projectId);
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  if (!source) {
    await interaction.editReply(
      editPayload(
        errorPanel(
          '프로젝트를 찾지 못했습니다',
          '목록에서 배당한 프로젝트를 골라 주세요.',
          { footer: KINDS.repair.footer },
        ),
      ),
    );
    return;
  }

  const entries = settings.fields.filter((entry) => entry.field === field).slice(0, 25);

  if (entries.length === 0) {
    await interaction.editReply(
      editPayload(
        errorPanel(
          '직원이 없습니다',
          `**${field}** 분야에 등록된 직원이 없습니다.\n\`/분야설정\` 으로 먼저 등록해 주세요.`,
          { footer: KINDS.repair.footer },
        ),
      ),
    );
    return;
  }

  const menu = new StringSelectMenuBuilder()
    .setCustomId(`${ASSIGN_IDS.repairPick}:${source.id}`)
    .setPlaceholder('수리를 맡길 직원을 선택해 주세요')
    .setMinValues(1)
    .setMaxValues(1)
    .addOptions(
      entries.map((entry) => ({
        label: entry.nickname.slice(0, 100),
        value: entry.userId,
        description: `${entry.field}`.slice(0, 100),
      })),
    );

  await interaction.editReply(
    editPayload(
      panel({
        color: config.colors.primary,
        title: '수리',
        description: `**${source.title}** 의 수리입니다.\n**${field}** 분야에서 맡길 직원을 선택해 주세요.`,
        buttons: [menu],
        footer: KINDS.repair.footer,
      }),
    ),
  );
}

export async function handleRepairPick(interaction) {
  const sourceId = interaction.customId.slice(`${ASSIGN_IDS.repairPick}:`.length);
  const userId = interaction.values?.[0];

  const modal = new ModalBuilder()
    .setCustomId(`${ASSIGN_IDS.repairForm}:${sourceId}:${userId}`)
    .setTitle('수리');

  modal.addComponents(
    new ActionRowBuilder().addComponents(
      new TextInputBuilder()
        .setCustomId('title')
        .setLabel('수리 항목')
        .setPlaceholder('예: 상점 스크립트 오류')
        .setStyle(TextInputStyle.Short)
        .setMaxLength(80)
        .setRequired(true),
    ),
    new ActionRowBuilder().addComponents(
      new TextInputBuilder()
        .setCustomId('description')
        .setLabel('수리 내용')
        .setStyle(TextInputStyle.Paragraph)
        .setMaxLength(900)
        .setRequired(true),
    ),
    new ActionRowBuilder().addComponents(
      new TextInputBuilder()
        .setCustomId('pay')
        .setLabel('급여')
        .setPlaceholder('예: 무료 또는 30,000원')
        .setStyle(TextInputStyle.Short)
        .setMaxLength(40)
        .setRequired(true),
    ),
  );

  await interaction.showModal(modal);
}

export async function handleRepairCreate(interaction) {
  const rest = interaction.customId.slice(`${ASSIGN_IDS.repairForm}:`.length);
  const separator = rest.lastIndexOf(':');
  const sourceId = rest.slice(0, separator);
  const userId = rest.slice(separator + 1);

  await interaction.reply(
    payload(neutralPanel('잠시만 기다려 주세요', '수리를 등록하고 있습니다.', { footer: KINDS.repair.footer }), {
      ephemeral: true,
    }),
  );

  const title = interaction.fields.getTextInputValue('title').trim();
  const description = interaction.fields.getTextInputValue('description').trim();
  const pay = interaction.fields.getTextInputValue('pay').trim();

  let settings;
  let source;
  try {
    settings = await readSettings(interaction.client);
    source = await getRecord(interaction.client, MARKERS.assignment, sourceId);
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  const entry = settings.fields.find((item) => item.userId === userId);

  const record = {
    id: makeRecordId('a'),
    kind: 'repair',
    project: source?.title ?? null,
    sourceId,
    userId,
    nickname: entry?.nickname ?? null,
    field: entry?.field ?? null,
    title,
    description,
    pay,
    status: 'pending',
    createdAt: Date.now(),
    createdBy: interaction.user.id,
    guildId: interaction.guildId,
    acceptedAt: null,
    dueAt: null,
    report: null,
    rejectReason: null,
    extensions: 0,
    warnings: 0,
    lastNoticeAt: null,
  };

  let saved;
  try {
    saved = await addRecord(interaction.client, MARKERS.assignment, record);
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  await postToChannel(interaction.client, config.assignListChannelId, buildListContainer(saved));

  const delivered = await sendDm(interaction.client, userId, buildOfferPayload(saved));

  await notifyAdmins(
    interaction.client,
    interaction.guild,
    panel({
      color: config.colors.primary,
      title: '새 수리',
      description: `<@${userId}> 님에게 **${title}** 수리를 맡겼습니다.`,
      fields: [
        ...(saved.project ? [{ name: '프로젝트', value: saved.project }] : []),
        { name: '맡긴 사람', value: `${interaction.user} (${interaction.user.id})` },
        { name: '급여', value: pay },
      ],
      footer: KINDS.repair.footer,
    }),
  );

  await interaction.editReply(
    editPayload(
      delivered
        ? successPanel('맡겼습니다', `<@${userId}> 님에게 **${title}** 수리를 보냈습니다.`, {
            footer: KINDS.repair.footer,
          })
        : warningPanel(
            '등록은 되었지만 DM 이 가지 않았습니다',
            `<@${userId}> 님이 DM 을 닫아 두었습니다. 직접 알려 주세요.`,
            { footer: KINDS.repair.footer },
          ),
    ),
  );
}

function buildListContainer(record) {
  const text = labels(record);
  return panel({
    color: config.colors.primary,
    title: text.listTitle,
    description: `**${record.title}**\n\n${record.description}`,
    fields: [
      ...(record.project ? [{ name: '프로젝트', value: record.project }] : []),
      { name: '담당', value: `<@${record.userId}>${record.nickname ? ` (${record.nickname})` : ''}` },
      { name: '분야', value: record.field ?? '미지정' },
      { name: '급여', value: record.pay },
      { name: '배당 시각', value: formatKst(record.createdAt) },
      { name: '상태', value: STATUS_LABEL[record.status] ?? record.status },
    ],
    footer: text.footer,
  });
}

function buildOfferPayload(record) {
  const text = labels(record);
  return payload(
    panel({
      color: config.colors.primary,
      title: text.offerTitle,
      description: `**${record.title}**\n\n${record.description}`,
      fields: [
        ...(record.project ? [{ name: '프로젝트', value: record.project }] : []),
        { name: '급여', value: record.pay },
        { name: '분야', value: record.field ?? '미지정' },
      ],
      buttons: [
        new ButtonBuilder()
          .setCustomId(`${ASSIGN_IDS.accept}:${record.id}`)
          .setLabel(text.accept)
          .setStyle(ButtonStyle.Success),
        new ButtonBuilder()
          .setCustomId(`${ASSIGN_IDS.reject}:${record.id}`)
          .setLabel(text.reject)
          .setStyle(ButtonStyle.Danger),
      ],
      footer: text.footer,
    }),
  );
}

// --- 수락 / 거절 ---

export async function handleAssignAccept(interaction) {
  const id = interaction.customId.slice(`${ASSIGN_IDS.accept}:`.length);

  const modal = new ModalBuilder().setCustomId(`${ASSIGN_IDS.acceptForm}:${id}`).setTitle('수락');

  modal.addComponents(
    new ActionRowBuilder().addComponents(
      new TextInputBuilder()
        .setCustomId('deadline')
        .setLabel('기간')
        .setPlaceholder('예: 3일, 48시간, 2026-08-10 18:00')
        .setStyle(TextInputStyle.Short)
        .setMaxLength(40)
        .setRequired(true),
    ),
    new ActionRowBuilder().addComponents(
      new TextInputBuilder()
        .setCustomId('report')
        .setLabel('보고사항')
        .setPlaceholder('진행 계획이나 참고할 내용을 적어 주세요.')
        .setStyle(TextInputStyle.Paragraph)
        .setMaxLength(900)
        .setRequired(true),
    ),
  );

  await interaction.showModal(modal);
}

export async function handleAssignAcceptForm(interaction) {
  const id = interaction.customId.slice(`${ASSIGN_IDS.acceptForm}:`.length);
  const deadlineInput = interaction.fields.getTextInputValue('deadline').trim();
  const report = interaction.fields.getTextInputValue('report').trim();

  await interaction.reply(
    payload(neutralPanel('잠시만 기다려 주세요', '수락을 처리하고 있습니다.', { footer: FOOTER }), {
      ephemeral: true,
    }),
  );

  const dueAt = parseDeadline(deadlineInput);
  if (dueAt === null || dueAt <= Date.now()) {
    await interaction.editReply(
      editPayload(
        errorPanel(
          '기간을 읽지 못했습니다',
          '`3일`, `48시간`, `2026-08-10 18:00` 처럼 적어 주세요. 지난 시각은 넣을 수 없습니다.',
          { footer: FOOTER },
        ),
      ),
    );
    return;
  }

  let record;
  try {
    record = await updateRecord(interaction.client, MARKERS.assignment, id, {
      status: 'accepted',
      acceptedAt: Date.now(),
      dueAt,
      report,
      lastNoticeAt: null,
    });
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  if (!record) {
    await interaction.editReply(
      editPayload(errorPanel('찾지 못했습니다', '이미 처리되었거나 없는 기록입니다.', { footer: FOOTER })),
    );
    return;
  }

  const statusFields = [
    { name: '담당', value: `<@${record.userId}>` },
    { name: '기간', value: `${formatKst(dueAt)} 까지 (${formatDuration(dueAt - Date.now())} 남음)` },
    { name: '보고사항', value: report },
  ];

  // 상황 채널 글에는 총관리자가 누를 기간 조정 버튼을 컨테이너 안에 함께 넣습니다.
  await postToChannel(
    interaction.client,
    config.assignStatusChannelId,
    panel({
      color: config.colors.success,
      title: labels(record).accept,
      description: `**${record.title}**`,
      fields: statusFields,
      buttons: [
        new ButtonBuilder()
          .setCustomId(`${ASSIGN_IDS.adjust}:${record.id}`)
          .setLabel('기간 조정')
          .setStyle(ButtonStyle.Secondary),
      ],
      footer: FOOTER,
    }),
  );

  await notifyAdmins(
    interaction.client,
    await fetchGuild(interaction.client, record.guildId),
    panel({
      color: config.colors.success,
      title: labels(record).accept,
      description: `**${record.title}**`,
      fields: statusFields,
      footer: labels(record).footer,
    }),
  );

  await interaction.editReply(
    editPayload(
      successPanel('수락했습니다', `기간은 ${formatKst(dueAt)} 까지입니다.`, { footer: FOOTER }),
    ),
  );

  await disableOffer(interaction, '수락함');
}

export async function handleAssignReject(interaction) {
  const id = interaction.customId.slice(`${ASSIGN_IDS.reject}:`.length);

  const modal = new ModalBuilder().setCustomId(`${ASSIGN_IDS.rejectForm}:${id}`).setTitle('거절');

  modal.addComponents(
    new ActionRowBuilder().addComponents(
      new TextInputBuilder()
        .setCustomId('reason')
        .setLabel(`거절 사유 (${MIN_REJECT_REASON}자 이상)`)
        .setStyle(TextInputStyle.Paragraph)
        .setMinLength(MIN_REJECT_REASON)
        .setMaxLength(900)
        .setRequired(true),
    ),
  );

  await interaction.showModal(modal);
}

export async function handleAssignRejectForm(interaction) {
  const id = interaction.customId.slice(`${ASSIGN_IDS.rejectForm}:`.length);
  const reason = interaction.fields.getTextInputValue('reason').trim();

  await interaction.reply(
    payload(neutralPanel('잠시만 기다려 주세요', '거절을 처리하고 있습니다.', { footer: FOOTER }), {
      ephemeral: true,
    }),
  );

  if (reason.length < MIN_REJECT_REASON) {
    await interaction.editReply(
      editPayload(
        errorPanel('사유가 너무 짧습니다', `${MIN_REJECT_REASON}자 이상 적어 주세요.`, { footer: FOOTER }),
      ),
    );
    return;
  }

  let record;
  try {
    record = await updateRecord(interaction.client, MARKERS.assignment, id, {
      status: 'rejected',
      rejectReason: reason,
      rejectedAt: Date.now(),
    });
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  if (!record) {
    await interaction.editReply(
      editPayload(errorPanel('찾지 못했습니다', '이미 처리되었거나 없는 기록입니다.', { footer: FOOTER })),
    );
    return;
  }

  const container = panel({
    color: config.colors.danger,
    title: labels(record).reject,
    description: `**${record.title}**`,
    fields: [
      { name: '담당', value: `<@${record.userId}>` },
      { name: '거절 사유', value: reason },
      { name: '거절 시각', value: formatKst(Date.now()) },
    ],
    footer: FOOTER,
  });

  await postToChannel(interaction.client, config.assignStatusChannelId, container);
  await notifyAdmins(interaction.client, await fetchGuild(interaction.client, record.guildId), container);

  await interaction.editReply(
    editPayload(successPanel('거절했습니다', '사유가 전달되었습니다.', { footer: FOOTER })),
  );

  await disableOffer(interaction, '거절함');
}

/** DM 에 있던 수락/거절 버튼을 지웁니다. */
async function disableOffer(interaction, label) {
  await interaction.message
    ?.edit(
      editPayload(
        panel({
          color: config.colors.neutral,
          title: '처리되었습니다',
          description: `이미 **${label}** 상태입니다.`,
          footer: FOOTER,
        }),
      ),
    )
    .catch(() => {});
}

// --- 기간 조정 ---

export async function handleAdjustRequest(interaction) {
  const id = interaction.customId.slice(`${ASSIGN_IDS.adjust}:`.length);

  if (!isAdmin(interaction.member)) {
    await interaction.reply(payload(deniedPanel(), { ephemeral: true }));
    return;
  }

  const modal = new ModalBuilder().setCustomId(`${ASSIGN_IDS.adjustForm}:${id}`).setTitle('기간 조정');

  modal.addComponents(
    new ActionRowBuilder().addComponents(
      new TextInputBuilder()
        .setCustomId('deadline')
        .setLabel('새 기간')
        .setPlaceholder('예: 5일, 72시간, 2026-08-15 18:00')
        .setStyle(TextInputStyle.Short)
        .setMaxLength(40)
        .setRequired(true),
    ),
    new ActionRowBuilder().addComponents(
      new TextInputBuilder()
        .setCustomId('reason')
        .setLabel('조정 사유')
        .setStyle(TextInputStyle.Paragraph)
        .setMaxLength(500)
        .setRequired(false),
    ),
  );

  await interaction.showModal(modal);
}

export async function handleAdjustForm(interaction) {
  const id = interaction.customId.slice(`${ASSIGN_IDS.adjustForm}:`.length);
  const deadlineInput = readField(interaction, 'deadline');
  const reason = readField(interaction, 'reason');

  await interaction.reply(
    payload(neutralPanel('잠시만 기다려 주세요', '기간 조정을 보내고 있습니다.', { footer: FOOTER }), {
      ephemeral: true,
    }),
  );

  const dueAt = parseDeadline(deadlineInput);
  if (dueAt === null) {
    await interaction.editReply(
      editPayload(
        errorPanel('기간을 읽지 못했습니다', '`5일`, `72시간`, `2026-08-15 18:00` 처럼 적어 주세요.', {
          footer: FOOTER,
        }),
      ),
    );
    return;
  }

  let record;
  try {
    record = await updateRecord(interaction.client, MARKERS.assignment, id, {
      pendingDueAt: dueAt,
      pendingReason: reason || null,
    });
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  if (!record) {
    await interaction.editReply(
      editPayload(errorPanel('찾지 못했습니다', '없는 기록입니다.', { footer: FOOTER })),
    );
    return;
  }

  const delivered = await sendDm(
    interaction.client,
    record.userId,
    payload(
      panel({
        color: config.colors.warning,
        title: '기간이 조정되었습니다',
        description: `**${record.title}**`,
        fields: [
          { name: '새 기간', value: `${formatKst(dueAt)} 까지` },
          ...(reason ? [{ name: '사유', value: reason }] : []),
        ],
        buttons: [
          new ButtonBuilder()
            .setCustomId(`${ASSIGN_IDS.adjustAccept}:${record.id}`)
            .setLabel('수락')
            .setStyle(ButtonStyle.Success),
          new ButtonBuilder()
            .setCustomId(`${ASSIGN_IDS.adjustReject}:${record.id}`)
            .setLabel('거절')
            .setStyle(ButtonStyle.Danger),
        ],
        footer: FOOTER,
      }),
    ),
  );

  await interaction.editReply(
    editPayload(
      delivered
        ? successPanel('보냈습니다', `<@${record.userId}> 님에게 기간 조정을 보냈습니다.`, { footer: FOOTER })
        : warningPanel('DM 이 가지 않았습니다', '상대가 DM 을 닫아 두었습니다.', { footer: FOOTER }),
    ),
  );
}

export async function handleAdjustAccept(interaction) {
  const id = interaction.customId.slice(`${ASSIGN_IDS.adjustAccept}:`.length);

  await interaction.reply(
    payload(neutralPanel('잠시만 기다려 주세요', '처리하고 있습니다.', { footer: FOOTER }), { ephemeral: true }),
  );

  let record;
  try {
    record = await getRecord(interaction.client, MARKERS.assignment, id);
    if (record?.pendingDueAt) {
      record = await updateRecord(interaction.client, MARKERS.assignment, id, {
        dueAt: record.pendingDueAt,
        pendingDueAt: null,
        pendingReason: null,
        lastNoticeAt: null,
        status: 'accepted',
      });
    }
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  if (!record) {
    await interaction.editReply(
      editPayload(errorPanel('찾지 못했습니다', '없는 기록입니다.', { footer: FOOTER })),
    );
    return;
  }

  const container = panel({
    color: config.colors.success,
    title: '기간 조정 수락',
    description: `**${record.title}**`,
    fields: [
      { name: '담당', value: `<@${record.userId}>` },
      { name: '새 기간', value: `${formatKst(record.dueAt)} 까지` },
    ],
    footer: FOOTER,
  });

  await postToChannel(interaction.client, config.assignStatusChannelId, container);
  await notifyAdmins(interaction.client, await fetchGuild(interaction.client, record.guildId), container);

  await interaction.editReply(
    editPayload(successPanel('수락했습니다', `${formatKst(record.dueAt)} 까지로 바뀌었습니다.`, { footer: FOOTER })),
  );
  await disableOffer(interaction, '기간 조정 수락');
}

export async function handleAdjustReject(interaction) {
  const id = interaction.customId.slice(`${ASSIGN_IDS.adjustReject}:`.length);

  const modal = new ModalBuilder()
    .setCustomId(`${ASSIGN_IDS.adjustRejectForm}:${id}`)
    .setTitle('기간 조정 거절');

  modal.addComponents(
    new ActionRowBuilder().addComponents(
      new TextInputBuilder()
        .setCustomId('reason')
        .setLabel(`거절 사유 (${MIN_REJECT_REASON}자 이상)`)
        .setStyle(TextInputStyle.Paragraph)
        .setMinLength(MIN_REJECT_REASON)
        .setMaxLength(900)
        .setRequired(true),
    ),
  );

  await interaction.showModal(modal);
}

export async function handleAdjustRejectForm(interaction) {
  const id = interaction.customId.slice(`${ASSIGN_IDS.adjustRejectForm}:`.length);
  const reason = interaction.fields.getTextInputValue('reason').trim();

  await interaction.reply(
    payload(neutralPanel('잠시만 기다려 주세요', '처리하고 있습니다.', { footer: FOOTER }), { ephemeral: true }),
  );

  if (reason.length < MIN_REJECT_REASON) {
    await interaction.editReply(
      editPayload(errorPanel('사유가 너무 짧습니다', `${MIN_REJECT_REASON}자 이상 적어 주세요.`, { footer: FOOTER })),
    );
    return;
  }

  let record;
  try {
    record = await updateRecord(interaction.client, MARKERS.assignment, id, {
      pendingDueAt: null,
      pendingReason: null,
    });
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  if (!record) {
    await interaction.editReply(
      editPayload(errorPanel('찾지 못했습니다', '없는 기록입니다.', { footer: FOOTER })),
    );
    return;
  }

  const container = panel({
    color: config.colors.danger,
    title: '기간 조정 거절',
    description: `**${record.title}**`,
    fields: [
      { name: '담당', value: `<@${record.userId}>` },
      { name: '거절 사유', value: reason },
      { name: '유지되는 기간', value: record.dueAt ? `${formatKst(record.dueAt)} 까지` : '없음' },
    ],
    footer: FOOTER,
  });

  await postToChannel(interaction.client, config.assignStatusChannelId, container);
  await notifyAdmins(interaction.client, await fetchGuild(interaction.client, record.guildId), container);

  await interaction.editReply(
    editPayload(successPanel('거절했습니다', '사유가 전달되었습니다.', { footer: FOOTER })),
  );
  await disableOffer(interaction, '기간 조정 거절');
}

// --- 연장 ---

export async function handleExtend(interaction) {
  const id = interaction.customId.slice(`${ASSIGN_IDS.extend}:`.length);

  await interaction.reply(
    payload(neutralPanel('잠시만 기다려 주세요', '연장하고 있습니다.', { footer: FOOTER }), { ephemeral: true }),
  );

  let record;
  try {
    record = await getRecord(interaction.client, MARKERS.assignment, id);
    if (record) {
      const base = Math.max(Date.now(), Number(record.dueAt) || Date.now());
      record = await updateRecord(interaction.client, MARKERS.assignment, id, {
        dueAt: base + config.extendHours * 3600_000,
        extensions: (record.extensions ?? 0) + 1,
        lastNoticeAt: null,
        status: 'accepted',
      });
    }
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  if (!record) {
    await interaction.editReply(
      editPayload(errorPanel('찾지 못했습니다', '없는 기록입니다.', { footer: FOOTER })),
    );
    return;
  }

  const container = panel({
    color: config.colors.warning,
    title: '기간 연장',
    description: `**${record.title}**`,
    fields: [
      { name: '담당', value: `<@${record.userId}>` },
      { name: '연장 후 기간', value: `${formatKst(record.dueAt)} 까지` },
      { name: '연장 횟수', value: `${record.extensions}회` },
    ],
    footer: FOOTER,
  });

  await postToChannel(interaction.client, config.assignStatusChannelId, container);
  await notifyAdmins(interaction.client, await fetchGuild(interaction.client, record.guildId), container);

  await interaction.editReply(
    editPayload(
      successPanel('연장했습니다', `${config.extendHours}시간 늘려 ${formatKst(record.dueAt)} 까지입니다.`, {
        footer: FOOTER,
      }),
    ),
  );
}

// --- 기간 지남 확인 ---

/**
 * 진행 중인 배당 가운데 기간이 지난 것을 찾아 알립니다.
 * 첫 알림은 안내만 하고, 한 번이라도 연장한 뒤에도 계속 지나면 경고가 쌓입니다.
 */
export async function checkOverdue(client) {
  if (!config.storageChannelId) return;

  let records;
  try {
    records = await listRecords(client, MARKERS.assignment);
  } catch (error) {
    log.debug('기간 확인을 건너뜁니다.', error?.message ?? error);
    return;
  }

  const now = Date.now();
  const noticeGap = Math.max(1, config.overdueNoticeHours) * 3600_000;
  let warningsChanged = false;

  for (const record of records) {
    if (record.status !== 'accepted' && record.status !== 'overdue') continue;
    if (!record.dueAt || record.dueAt > now) continue;
    if (record.lastNoticeAt && now - record.lastNoticeAt < noticeGap) continue;

    const addWarning = (record.extensions ?? 0) > 0;
    const warnings = (record.warnings ?? 0) + (addWarning ? 1 : 0);

    let updated;
    try {
      updated = await updateRecord(client, MARKERS.assignment, record.id, {
        status: 'overdue',
        lastNoticeAt: now,
        warnings,
      });
    } catch (error) {
      log.error('기간 지남 처리 실패', error?.message ?? error);
      continue;
    }
    if (!updated) continue;
    if (addWarning) warningsChanged = true;

    await sendDm(
      client,
      record.userId,
      payload(
        panel({
          color: config.colors.danger,
          title: '기간이 지났습니다',
          description: `**${record.title}**\n\n연장하시겠습니까?`,
          fields: [
            { name: '원래 기간', value: `${formatKst(record.dueAt)} 까지` },
            { name: '지난 시간', value: formatDuration(now - record.dueAt) },
            ...(addWarning ? [{ name: '경고', value: `${warnings}회 쌓였습니다.` }] : []),
          ],
          buttons: [
            new ButtonBuilder()
              .setCustomId(`${ASSIGN_IDS.extend}:${record.id}`)
              .setLabel(`${config.extendHours}시간 연장`)
              .setStyle(ButtonStyle.Primary),
          ],
          footer: FOOTER,
        }),
      ),
    );

    const container = panel({
      color: config.colors.danger,
      title: '기간이 지났습니다',
      description: `**${record.title}**`,
      fields: [
        { name: '담당', value: `<@${record.userId}>` },
        { name: '원래 기간', value: `${formatKst(record.dueAt)} 까지` },
        { name: '지난 시간', value: formatDuration(now - record.dueAt) },
        { name: '연장 횟수', value: `${record.extensions ?? 0}회` },
        { name: '경고', value: `${warnings}회` },
      ],
      footer: FOOTER,
    });

    await postToChannel(client, config.assignStatusChannelId, container);
    await notifyAdmins(client, await fetchGuild(client, record.guildId), container);
  }

  if (warningsChanged) await refreshWarningBoard(client);
}

// --- 경고 상태판 ---

/** 경고 상태 채널에 있는 판을 항상 최신으로 고쳐 둡니다. */
export async function refreshWarningBoard(client) {
  if (!config.warningChannelId || !config.storageChannelId) return;

  let records;
  try {
    records = await listRecords(client, MARKERS.assignment);
  } catch (error) {
    log.debug('경고 상태판을 고치지 못했습니다.', error?.message ?? error);
    return;
  }

  const totals = new Map();
  for (const record of records) {
    const count = Number(record.warnings) || 0;
    if (count === 0) continue;
    totals.set(record.userId, (totals.get(record.userId) ?? 0) + count);
  }

  const lines = [...totals.entries()]
    .sort((a, b) => b[1] - a[1])
    .map(([userId, count]) => `<@${userId}> - 경고 ${count}회`);

  const container = panel({
    color: lines.length > 0 ? config.colors.danger : config.colors.neutral,
    title: '직원 경고 상태',
    description: lines.length > 0 ? lines.join('\n') : '경고가 쌓인 직원이 없습니다.',
    fields: [{ name: '갱신 시각', value: formatKst(Date.now()) }],
    footer: FOOTER,
  });

  const channel = await client.channels.fetch(config.warningChannelId).catch(() => null);
  if (!channel?.isTextBased()) return;

  // 판은 하나만 두고 계속 고쳐 씁니다. 봇이 마지막으로 올린 글을 찾습니다.
  const recent = await channel.messages.fetch({ limit: 50 }).catch(() => null);
  const board = recent?.find((message) => message.author?.id === client.user.id) ?? null;

  try {
    if (board) await board.edit(editPayload(container));
    else await channel.send({ ...payload(container), allowedMentions: { parse: [] } });
  } catch (error) {
    log.error('경고 상태판 갱신 실패', error?.message ?? error);
  }
}

// --- 도우미 ---

async function fetchGuild(client, guildId) {
  if (!guildId) return null;
  return client.guilds.fetch(guildId).catch(() => null);
}

/** 컨테이너를 채널에 올립니다. 버튼은 부르는 쪽에서 컨테이너 안에 넣어 주세요. */
export async function postToChannel(client, channelId, container) {
  if (!channelId) return null;

  const channel = await client.channels.fetch(channelId).catch(() => null);
  if (!channel?.isTextBased()) {
    log.warn(`채널(${channelId})을 찾지 못해 올리지 못했습니다.`);
    return null;
  }

  try {
    return await channel.send({ ...payload(container), allowedMentions: { parse: [] } });
  } catch (error) {
    log.error(`채널(${channelId}) 전송 실패`, error?.message ?? error);
    return null;
  }
}

export async function sendDm(client, userId, message) {
  if (!userId) return false;
  try {
    const user = await client.users.fetch(userId);
    await user.send(message);
    return true;
  } catch (error) {
    log.warn(`DM 을 보내지 못했습니다 (${userId}).`, error?.message ?? error);
    return false;
  }
}

/** 총관리자 역할을 가진 사람 모두에게 DM 으로 보고합니다. */
export async function notifyAdmins(client, guild, container) {
  if (!guild || !config.adminRoleId) return;

  const role = await guild.roles.fetch(config.adminRoleId).catch(() => null);
  if (!role) return;

  for (const member of role.members.values()) {
    await sendDm(client, member.id, payload(container));
  }
}

export function isAssignCustomId(customId) {
  return customId.startsWith('assign:');
}
