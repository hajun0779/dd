import { ButtonBuilder, ButtonStyle } from 'discord.js';

import { config } from './config.js';
import { log } from './log.js';
import { formatKst } from './time.js';
import {
  editPayload,
  errorPanel,
  neutralPanel,
  panel,
  payload,
  successPanel,
  warningPanel,
} from './components.js';
import { isAdmin, notifyAdmins, parseDeadline, postToChannel, sendDm } from './assignments.js';
import { canUseCommand, deniedReason } from './permissions.js';
import { MARKERS, addRecord, getRecord, makeRecordId, updateRecord, StorageError } from './storage.js';

/**
 * 송금 요청입니다.
 *
 * /송금요청 을 하면 대상자에게 계좌가 적힌 DM 이 가고, 보냈다고 누르면
 * 총관리자에게 확인을 요청합니다. 총관리자가 받았다고 하면 로그가 남고,
 * 못 받았다고 하면 대상자에게 다시 보냈다고 누를 수 있는 안내가 갑니다.
 */

const FOOTER = `${config.brandName} 송금`;

export const PAYMENT_IDS = {
  sent: 'paid:sent',
  ok: 'paid:ok',
  no: 'paid:no',
};

const STATUS_LABEL = {
  waiting: '입금 대기',
  sent: '확인 대기',
  done: '확인 완료',
};

export function isPaymentCustomId(customId) {
  return customId.startsWith('paid:');
}

function storageErrorPanel(error) {
  if (error instanceof StorageError) {
    return errorPanel('보관 채널을 쓸 수 없습니다', error.message, { footer: FOOTER });
  }
  log.error('송금 요청 처리 오류', error?.stack ?? error);
  return errorPanel('오류가 발생했습니다', '잠시 후 다시 시도해 주세요.', { footer: FOOTER });
}

/** 계좌 한 줄. .env 의 PAYMENT_BANK, PAYMENT_ACCOUNT, PAYMENT_HOLDER 로 바뀝니다. */
export function formatAccount() {
  return `${config.paymentBank} ${config.paymentAccount} 예금주: \`${config.paymentHolder}\``;
}

/** DM 에서 눌린 버튼은 member 가 없어서, 서버에서 다시 찾아 확인합니다. */
async function isAdminUser(client, guildId, userId) {
  if (!guildId) return false;

  const guild = await client.guilds.fetch(guildId).catch(() => null);
  if (!guild) return false;

  const member = await guild.members.fetch(userId).catch(() => null);
  return isAdmin(member);
}

// --- 대상자에게 가는 안내 ---

function buildRequestPayload(record) {
  const overdue = record.dueAt && record.dueAt <= Date.now();

  return payload(
    panel({
      color: overdue ? config.colors.warning : config.colors.primary,
      title: '송금 요청',
      description: formatAccount(),
      fields: [
        { name: '금액', value: record.amount },
        { name: '기한', value: `${formatKst(record.dueAt)}${overdue ? ' (지남)' : ''}` },
        ...(record.note ? [{ name: '내용', value: record.note }] : []),
        { name: '안내', value: '위 계좌로 보내신 뒤 아래 버튼을 눌러 주세요.' },
      ],
      buttons: [
        new ButtonBuilder()
          .setCustomId(`${PAYMENT_IDS.sent}:${record.id}`)
          .setLabel('보냈습니다')
          .setStyle(ButtonStyle.Success),
      ],
      footer: FOOTER,
    }),
  );
}

/** 총관리자에게 가는 확인 요청 */
function buildConfirmContainer(record) {
  return panel({
    color: config.colors.warning,
    title: '송금 확인 요청',
    description: `<@${record.userId}> 님이 보냈다고 했습니다.`,
    fields: [
      { name: '금액', value: record.amount },
      { name: '보냈다고 누른 시각', value: formatKst(record.sentAt ?? Date.now()) },
      { name: '기한', value: formatKst(record.dueAt) },
      ...(record.failCount ? [{ name: '다시 누른 횟수', value: `${record.failCount}회` }] : []),
      { name: '계좌', value: formatAccount() },
    ],
    buttons: [
      new ButtonBuilder()
        .setCustomId(`${PAYMENT_IDS.ok}:${record.id}`)
        .setLabel('확인됐습니다')
        .setStyle(ButtonStyle.Success),
      new ButtonBuilder()
        .setCustomId(`${PAYMENT_IDS.no}:${record.id}`)
        .setLabel('돈을 받지 못했어요')
        .setStyle(ButtonStyle.Danger),
    ],
    footer: FOOTER,
  });
}

// --- /송금요청 ---

export async function handlePaymentRequestCommand(interaction) {
  await interaction.reply(
    payload(neutralPanel('잠시만 기다려 주세요', '송금 요청을 보내고 있습니다.', { footer: FOOTER }), {
      ephemeral: true,
    }),
  );

  if (!canUseCommand(interaction.member, interaction.commandName)) {
    await interaction.editReply(
      editPayload(errorPanel('권한이 없습니다', deniedReason(interaction.commandName), { footer: FOOTER })),
    );
    return;
  }

  // 확인 버튼을 받을 곳이 하나도 없으면 요청해도 소용이 없습니다.
  if (!config.adminRoleId && !config.paymentLogChannelId) {
    await interaction.editReply(
      editPayload(
        errorPanel(
          '확인할 곳이 없습니다',
          '.env 의 ADMIN_ROLE_ID 또는 PAYMENT_LOG_CHANNEL_ID 중 하나는 채워 주세요.',
          { footer: FOOTER },
        ),
      ),
    );
    return;
  }

  const target = interaction.options.getUser('유저');
  const amount = interaction.options.getString('얼마').trim();
  const deadlineInput = interaction.options.getString('기한').trim();
  const note = (interaction.options.getString('내용') ?? '').trim();

  const dueAt = parseDeadline(deadlineInput);
  if (dueAt === null || dueAt <= Date.now()) {
    await interaction.editReply(
      editPayload(
        errorPanel(
          '기한을 읽지 못했습니다',
          '`3일`, `48시간`, `2026-08-10 18:00` 처럼 적어 주세요. 지난 시각은 넣을 수 없습니다.',
          { footer: FOOTER },
        ),
      ),
    );
    return;
  }

  const record = {
    id: makeRecordId('m'),
    userId: target.id,
    amount,
    note,
    dueAt,
    status: 'waiting',
    createdAt: Date.now(),
    createdBy: interaction.user.id,
    guildId: interaction.guildId,
    sentAt: null,
    confirmedAt: null,
    confirmedBy: null,
    failCount: 0,
  };

  let saved;
  try {
    saved = await addRecord(interaction.client, MARKERS.payment, record);
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  const delivered = await sendDm(interaction.client, target.id, buildRequestPayload(saved));

  await interaction.editReply(
    editPayload(
      delivered
        ? successPanel('보냈습니다', `${target} 님에게 **${amount}** 송금 요청을 보냈습니다.`, {
            fields: [{ name: '기한', value: formatKst(dueAt) }],
            footer: FOOTER,
          })
        : warningPanel(
            '요청은 되었지만 DM 이 가지 않았습니다',
            `${target} 님이 DM 을 닫아 두었습니다. 계좌를 직접 알려 주세요.`,
            { fields: [{ name: '계좌', value: formatAccount() }], footer: FOOTER },
          ),
    ),
  );

  log.info(`송금 요청: ${target.tag ?? target.id} ${amount} (${interaction.user.tag})`);
}

// --- 보냈습니다 ---

export async function handlePaymentSent(interaction) {
  const id = interaction.customId.slice(`${PAYMENT_IDS.sent}:`.length);

  await interaction.reply(
    payload(neutralPanel('잠시만 기다려 주세요', '확인을 요청하고 있습니다.', { footer: FOOTER }), {
      ephemeral: true,
    }),
  );

  let record;
  try {
    record = await getRecord(interaction.client, MARKERS.payment, id);
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  if (!record) {
    await interaction.editReply(
      editPayload(errorPanel('찾지 못했습니다', '없는 요청입니다.', { footer: FOOTER })),
    );
    return;
  }

  if (record.userId !== interaction.user.id) {
    await interaction.editReply(
      editPayload(errorPanel('누를 수 없습니다', '본인에게 온 요청만 누를 수 있습니다.', { footer: FOOTER })),
    );
    return;
  }

  if (record.status === 'done') {
    await interaction.editReply(
      editPayload(successPanel('이미 확인됐습니다', '더 하실 일이 없습니다.', { footer: FOOTER })),
    );
    return;
  }

  try {
    record = await updateRecord(interaction.client, MARKERS.payment, id, {
      status: 'sent',
      sentAt: Date.now(),
    });
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  const container = buildConfirmContainer(record);

  // 총관리자에게 DM 으로 보내고, 로그 채널에도 같은 버튼을 올려 둡니다.
  // DM 을 닫아 둔 경우에도 확인할 수 있게 하기 위해서입니다.
  const guild = await interaction.client.guilds.fetch(record.guildId).catch(() => null);
  await notifyAdmins(interaction.client, guild, container);
  await postToChannel(interaction.client, config.paymentLogChannelId, container);

  // 대상자의 DM 은 버튼을 빼고 대기 안내로 바꿉니다.
  await interaction.message
    ?.edit(
      editPayload(
        panel({
          color: config.colors.neutral,
          title: '확인 중입니다',
          description: '보내 주셔서 감사합니다. 확인되면 다시 알려 드리겠습니다.',
          fields: [{ name: '금액', value: record.amount }],
          footer: FOOTER,
        }),
      ),
    )
    .catch(() => {});

  await interaction.editReply(
    editPayload(successPanel('전달했습니다', '확인되면 다시 알려 드리겠습니다.', { footer: FOOTER })),
  );
}

// --- 총관리자 확인 ---

async function loadForAdmin(interaction, prefix) {
  const id = interaction.customId.slice(`${prefix}:`.length);

  let record;
  try {
    record = await getRecord(interaction.client, MARKERS.payment, id);
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return null;
  }

  if (!record) {
    await interaction.editReply(
      editPayload(errorPanel('찾지 못했습니다', '없는 요청입니다.', { footer: FOOTER })),
    );
    return null;
  }

  const allowed =
    isAdmin(interaction.member) ||
    (await isAdminUser(interaction.client, record.guildId, interaction.user.id));

  if (!allowed) {
    await interaction.editReply(
      editPayload(errorPanel('권한이 없습니다', '총관리자만 누를 수 있습니다.', { footer: FOOTER })),
    );
    return null;
  }

  return record;
}

/** 이미 처리된 요청에 다시 누른 경우를 막습니다. */
async function rejectIfDone(interaction, record) {
  if (record.status !== 'done') return false;

  await interaction.editReply(
    editPayload(
      neutralPanel('이미 확인된 요청입니다', `확인 시각: ${formatKst(record.confirmedAt)}`, {
        footer: FOOTER,
      }),
    ),
  );
  return true;
}

export async function handlePaymentConfirm(interaction) {
  await interaction.reply(
    payload(neutralPanel('잠시만 기다려 주세요', '확인을 처리하고 있습니다.', { footer: FOOTER }), {
      ephemeral: true,
    }),
  );

  let record = await loadForAdmin(interaction, PAYMENT_IDS.ok);
  if (!record) return;
  if (await rejectIfDone(interaction, record)) return;

  try {
    record = await updateRecord(interaction.client, MARKERS.payment, record.id, {
      status: 'done',
      confirmedAt: Date.now(),
      confirmedBy: interaction.user.id,
    });
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  // 로그 채널에 남깁니다.
  await postToChannel(
    interaction.client,
    config.paymentLogChannelId,
    panel({
      color: config.colors.success,
      title: '송금 확인',
      description: `<@${record.userId}> 님의 송금이 확인됐습니다.`,
      fields: [
        { name: '금액', value: record.amount },
        ...(record.note ? [{ name: '내용', value: record.note }] : []),
        { name: '요청한 사람', value: `<@${record.createdBy}>` },
        { name: '요청 시각', value: formatKst(record.createdAt) },
        { name: '확인한 사람', value: `<@${record.confirmedBy}>` },
        { name: '확인 시각', value: formatKst(record.confirmedAt) },
        ...(record.failCount ? [{ name: '미확인 처리', value: `${record.failCount}회` }] : []),
      ],
      footer: FOOTER,
    }),
  );

  // 보낸 사람에게 알립니다.
  await sendDm(
    interaction.client,
    record.userId,
    payload(
      successPanel('확인됐습니다', '보내 주신 금액이 확인됐습니다. 감사합니다.', {
        fields: [
          { name: '금액', value: record.amount },
          { name: '확인 시각', value: formatKst(record.confirmedAt) },
        ],
        footer: FOOTER,
      }),
    ),
  );

  await disableConfirm(interaction, '확인됨');

  await interaction.editReply(
    editPayload(successPanel('확인 처리했습니다', '보낸 사람에게 알렸습니다.', { footer: FOOTER })),
  );

  log.info(`송금 확인: ${record.userId} ${record.amount} (${interaction.user.tag})`);
}

export async function handlePaymentFail(interaction) {
  await interaction.reply(
    payload(neutralPanel('잠시만 기다려 주세요', '처리하고 있습니다.', { footer: FOOTER }), {
      ephemeral: true,
    }),
  );

  let record = await loadForAdmin(interaction, PAYMENT_IDS.no);
  if (!record) return;
  if (await rejectIfDone(interaction, record)) return;

  const failCount = (record.failCount ?? 0) + 1;

  try {
    record = await updateRecord(interaction.client, MARKERS.payment, record.id, {
      status: 'waiting',
      sentAt: null,
      failCount,
    });
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  await postToChannel(
    interaction.client,
    config.paymentLogChannelId,
    panel({
      color: config.colors.danger,
      title: '송금 미확인',
      description: `<@${record.userId}> 님의 송금이 확인되지 않았습니다.`,
      fields: [
        { name: '금액', value: record.amount },
        { name: '확인한 사람', value: `<@${interaction.user.id}>` },
        { name: '처리 시각', value: formatKst(Date.now()) },
        { name: '미확인 처리', value: `${failCount}회` },
      ],
      footer: FOOTER,
    }),
  );

  // 보낸 사람에게 다시 누를 수 있는 안내를 보냅니다.
  await sendDm(
    interaction.client,
    record.userId,
    payload(
      panel({
        color: config.colors.danger,
        title: '입금이 확인되지 않았습니다',
        description: [
          '아직 입금이 확인되지 않았습니다.',
          '계좌와 금액을 다시 확인해 주세요.',
          '이미 보내셨다면 잠시 뒤에 아래 버튼을 다시 눌러 주세요.',
        ].join('\n'),
        fields: [
          { name: '계좌', value: formatAccount() },
          { name: '금액', value: record.amount },
          { name: '기한', value: formatKst(record.dueAt) },
        ],
        buttons: [
          new ButtonBuilder()
            .setCustomId(`${PAYMENT_IDS.sent}:${record.id}`)
            .setLabel('보냈습니다')
            .setStyle(ButtonStyle.Success),
        ],
        footer: FOOTER,
      }),
    ),
  );

  await disableConfirm(interaction, '미확인 처리됨');

  await interaction.editReply(
    editPayload(
      successPanel('처리했습니다', '보낸 사람에게 다시 확인해 달라고 알렸습니다.', { footer: FOOTER }),
    ),
  );

  log.info(`송금 미확인: ${record.userId} ${record.amount} (${interaction.user.tag}, ${failCount}회)`);
}

/** 눌린 확인 요청 메시지의 버튼을 지웁니다. */
async function disableConfirm(interaction, label) {
  await interaction.message
    ?.edit(
      editPayload(
        panel({
          color: config.colors.neutral,
          title: '처리되었습니다',
          description: `이 요청은 **${label}** 상태입니다.`,
          footer: FOOTER,
        }),
      ),
    )
    .catch(() => {});
}

export { STATUS_LABEL as PAYMENT_STATUS_LABEL };
