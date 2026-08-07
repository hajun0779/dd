import {
  ActionRowBuilder,
  ButtonBuilder,
  ButtonStyle,
  ModalBuilder,
  TextInputBuilder,
  TextInputStyle,
} from 'discord.js';

import { config } from './config.js';
import { log } from './log.js';
import { formatKst } from './time.js';
import { editPayload, errorPanel, neutralPanel, panel, payload, successPanel, warningPanel } from './components.js';
import { isAdmin, notifyAdmins, postToChannel, readField, sendDm } from './assignments.js';
import { MARKERS, addRecord, getRecord, listRecords, makeRecordId, updateRecord, StorageError } from './storage.js';

const FOOTER = `${config.brandName} 급여`;

export const PAYROLL_IDS = {
  start: 'pay:start',
  form: 'pay:form',
  done: 'pay:done',
};

function storageErrorPanel(error) {
  if (error instanceof StorageError) return errorPanel('보관 채널을 쓸 수 없습니다', error.message, { footer: FOOTER });
  log.error('급여 처리 오류', error?.stack ?? error);
  return errorPanel('오류가 발생했습니다', '잠시 후 다시 시도해 주세요.', { footer: FOOTER });
}

/** 지금까지 지급이 끝난 금액을 더합니다. 숫자로 읽히는 부분만 셉니다. */
export function sumPaid(records, userId) {
  let total = 0;
  let count = 0;

  for (const record of records) {
    if (record.userId !== userId || record.status !== 'paid') continue;
    count += 1;
    const digits = String(record.amount ?? '').replace(/[^\d]/g, '');
    if (digits.length > 0) total += Number(digits);
  }

  return { total, count };
}

export function formatMoney(value) {
  return `${Number(value || 0).toLocaleString('ko-KR')}원`;
}

// --- 급여 보내기 ---

export async function handlePayCommand(interaction) {
  await interaction.reply(
    payload(neutralPanel('잠시만 기다려 주세요', '급여 안내를 보내고 있습니다.', { footer: FOOTER }), {
      ephemeral: true,
    }),
  );

  if (!isAdmin(interaction.member)) {
    await interaction.editReply(
      editPayload(
        errorPanel(
          '권한이 없습니다',
          config.adminRoleId
            ? `<@&${config.adminRoleId}> 역할을 가진 사람만 쓸 수 있습니다.`
            : '총관리자 역할이 설정되지 않았습니다. .env 의 ADMIN_ROLE_ID 를 채워 주세요.',
          { footer: FOOTER },
        ),
      ),
    );
    return;
  }

  const amount = interaction.options.getString('급여').trim();
  const target = interaction.options.getUser('직원');

  const record = {
    id: makeRecordId('p'),
    userId: target.id,
    amount,
    status: 'sent',
    createdAt: Date.now(),
    createdBy: interaction.user.id,
    guildId: interaction.guildId,
    account: null,
    holder: null,
    thanks: null,
    requestedAt: null,
    paidAt: null,
  };

  let saved;
  try {
    saved = await addRecord(interaction.client, MARKERS.payroll, record);
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  const delivered = await sendDm(
    interaction.client,
    target.id,
    payload(
      panel({
        color: config.colors.success,
        title: '급여가 도착했습니다',
        description: '아래 버튼을 눌러 받으실 계좌를 알려 주세요.',
        fields: [
          { name: '급여', value: amount },
          { name: '보낸 시각', value: formatKst(saved.createdAt) },
        ],
        buttons: [
          new ButtonBuilder()
            .setCustomId(`${PAYROLL_IDS.start}:${saved.id}`)
            .setLabel('계좌 입력')
            .setStyle(ButtonStyle.Primary),
        ],
        footer: FOOTER,
      }),
    ),
  );

  await interaction.editReply(
    editPayload(
      delivered
        ? successPanel('보냈습니다', `${target} 님에게 급여 안내를 보냈습니다.`, { footer: FOOTER })
        : warningPanel('DM 이 가지 않았습니다', `${target} 님이 DM 을 닫아 두었습니다.`, { footer: FOOTER }),
    ),
  );
}

// --- 계좌 입력 ---

export async function handlePayStart(interaction) {
  const id = interaction.customId.slice(`${PAYROLL_IDS.start}:`.length);

  const modal = new ModalBuilder().setCustomId(`${PAYROLL_IDS.form}:${id}`).setTitle('급여 신청');

  modal.addComponents(
    new ActionRowBuilder().addComponents(
      new TextInputBuilder()
        .setCustomId('account')
        .setLabel('계좌번호')
        .setPlaceholder('은행 이름과 계좌번호를 함께 적어 주세요.')
        .setStyle(TextInputStyle.Short)
        .setMaxLength(60)
        .setRequired(true),
    ),
    new ActionRowBuilder().addComponents(
      new TextInputBuilder()
        .setCustomId('holder')
        .setLabel('예금주')
        .setStyle(TextInputStyle.Short)
        .setMaxLength(30)
        .setRequired(true),
    ),
    new ActionRowBuilder().addComponents(
      new TextInputBuilder()
        .setCustomId('thanks')
        .setLabel('감사의 말')
        .setStyle(TextInputStyle.Paragraph)
        .setMaxLength(500)
        .setRequired(false),
    ),
  );

  await interaction.showModal(modal);
}

export async function handlePayForm(interaction) {
  const id = interaction.customId.slice(`${PAYROLL_IDS.form}:`.length);

  await interaction.reply(
    payload(neutralPanel('잠시만 기다려 주세요', '신청을 보내고 있습니다.', { footer: FOOTER }), {
      ephemeral: true,
    }),
  );

  const account = readField(interaction, 'account');
  const holder = readField(interaction, 'holder');
  const thanks = readField(interaction, 'thanks');

  let record;
  try {
    record = await updateRecord(interaction.client, MARKERS.payroll, id, {
      status: 'requested',
      account,
      holder,
      thanks: thanks || null,
      requestedAt: Date.now(),
    });
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  if (!record) {
    await interaction.editReply(
      editPayload(errorPanel('찾지 못했습니다', '이미 처리되었거나 없는 급여입니다.', { footer: FOOTER })),
    );
    return;
  }

  // 급여 신청 채널에 올립니다. 지급 완료 버튼은 총관리자만 쓸 수 있습니다.
  const posted = await postToChannel(
    interaction.client,
    config.payrollChannelId,
    buildRequestContainer(record),
  );

  if (posted) {
    try {
      await updateRecord(interaction.client, MARKERS.payroll, id, { requestMessageId: posted.id });
    } catch (error) {
      log.debug('급여 신청 메시지 ID 를 저장하지 못했습니다.', error?.message ?? error);
    }
  }

  await interaction.editReply(
    editPayload(successPanel('신청했습니다', '확인 후 지급해 드리겠습니다.', { footer: FOOTER })),
  );

  await interaction.message
    ?.edit(
      editPayload(
        panel({
          color: config.colors.neutral,
          title: '급여 신청이 접수되었습니다',
          description: '확인 후 지급해 드리겠습니다.',
          fields: [{ name: '급여', value: record.amount }],
          footer: FOOTER,
        }),
      ),
    )
    .catch(() => {});
}

function buildRequestContainer(record) {
  return panel({
    color: config.colors.warning,
    title: '급여 신청',
    description: `<@${record.userId}> 님의 급여 신청입니다.`,
    fields: [
      { name: '급여', value: record.amount },
      { name: '계좌번호', value: record.account },
      { name: '예금주', value: record.holder },
      ...(record.thanks ? [{ name: '감사의 말', value: record.thanks }] : []),
      { name: '신청 시각', value: formatKst(record.requestedAt) },
      { name: '상태', value: '지급 대기' },
    ],
    buttons: [
      new ButtonBuilder()
        .setCustomId(`${PAYROLL_IDS.done}:${record.id}`)
        .setLabel('지급 완료')
        .setStyle(ButtonStyle.Success),
    ],
    footer: FOOTER,
  });
}

// --- 지급 완료 ---

export async function handlePayDone(interaction) {
  const id = interaction.customId.slice(`${PAYROLL_IDS.done}:`.length);

  if (!isAdmin(interaction.member)) {
    await interaction.reply(
      payload(
        errorPanel('권한이 없습니다', '총관리자만 지급 완료를 누를 수 있습니다.', { footer: FOOTER }),
        { ephemeral: true },
      ),
    );
    return;
  }

  await interaction.reply(
    payload(neutralPanel('잠시만 기다려 주세요', '지급을 기록하고 있습니다.', { footer: FOOTER }), {
      ephemeral: true,
    }),
  );

  let record;
  try {
    record = await getRecord(interaction.client, MARKERS.payroll, id);
    if (record?.status === 'paid') {
      await interaction.editReply(
        editPayload(warningPanel('이미 지급되었습니다', `${formatKst(record.paidAt)} 에 처리되었습니다.`, { footer: FOOTER })),
      );
      return;
    }
    record = await updateRecord(interaction.client, MARKERS.payroll, id, {
      status: 'paid',
      paidAt: Date.now(),
      paidBy: interaction.user.id,
    });
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  if (!record) {
    await interaction.editReply(
      editPayload(errorPanel('찾지 못했습니다', '없는 급여입니다.', { footer: FOOTER })),
    );
    return;
  }

  // 지금까지 받은 금액을 더합니다.
  let summary = { total: 0, count: 0 };
  try {
    const all = await listRecords(interaction.client, MARKERS.payroll);
    summary = sumPaid(all, record.userId);
  } catch (error) {
    log.debug('지급 합계를 내지 못했습니다.', error?.message ?? error);
  }

  const paidFields = [
    { name: '급여', value: record.amount },
    { name: '계좌번호', value: record.account ?? '알 수 없음' },
    { name: '예금주', value: record.holder ?? '알 수 없음' },
    { name: '지급 시각', value: formatKst(record.paidAt) },
    { name: '지급 처리', value: `${interaction.user} (${interaction.user.id})` },
    { name: '지급 상태', value: '지급 완료' },
    { name: '지금까지 받은 금액', value: `${formatMoney(summary.total)} (${summary.count}건)` },
  ];

  // 신청 채널의 글을 지급 완료로 고칩니다.
  await interaction.message
    ?.edit(
      editPayload(
        panel({
          color: config.colors.success,
          title: '급여 지급 완료',
          description: `<@${record.userId}> 님의 급여를 지급했습니다.`,
          fields: paidFields,
          footer: FOOTER,
        }),
      ),
    )
    .catch(() => {});

  await sendDm(
    interaction.client,
    record.userId,
    payload(
      panel({
        color: config.colors.success,
        title: '급여가 지급되었습니다',
        description: '보내 주신 계좌로 지급을 마쳤습니다.',
        fields: [
          { name: '급여', value: record.amount },
          { name: '지급 시각', value: formatKst(record.paidAt) },
          { name: '지금까지 받은 금액', value: `${formatMoney(summary.total)} (${summary.count}건)` },
        ],
        footer: FOOTER,
      }),
    ),
  );

  await notifyAdmins(
    interaction.client,
    interaction.guild,
    panel({
      color: config.colors.success,
      title: '급여 지급 완료',
      description: `<@${record.userId}> 님에게 지급했습니다.`,
      fields: paidFields,
      footer: FOOTER,
    }),
  );

  await interaction.editReply(
    editPayload(successPanel('지급 처리했습니다', `${record.amount} 을 지급 완료로 바꿨습니다.`, { footer: FOOTER })),
  );
}

// --- 지급 상태 보기 ---

export async function handlePayStatusCommand(interaction) {
  await interaction.reply(
    payload(neutralPanel('잠시만 기다려 주세요', '지급 상태를 불러오고 있습니다.', { footer: FOOTER }), {
      ephemeral: true,
    }),
  );

  const target = interaction.options.getUser('직원') ?? interaction.user;

  let records = [];
  try {
    records = await listRecords(interaction.client, MARKERS.payroll);
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  const mine = records.filter((record) => record.userId === target.id);
  const summary = sumPaid(mine, target.id);
  const waiting = mine.filter((record) => record.status !== 'paid');

  await interaction.editReply(
    editPayload(
      panel({
        color: config.colors.neutral,
        title: '급여 지급 상태',
        description: `${target} 님의 급여 내역입니다.`,
        fields: [
          { name: '지금까지 받은 금액', value: `${formatMoney(summary.total)} (${summary.count}건)` },
          { name: '지급 대기', value: waiting.length > 0 ? `${waiting.length}건` : '없음' },
          {
            name: '최근 내역',
            value:
              mine.length === 0
                ? '내역이 없습니다.'
                : mine
                    .slice(-10)
                    .reverse()
                    .map(
                      (record) =>
                        `${record.status === 'paid' ? '지급 완료' : '지급 대기'} · ${record.amount} · ${formatKst(
                          record.paidAt ?? record.requestedAt ?? record.createdAt,
                        )}`,
                    )
                    .join('\n'),
          },
        ],
        footer: FOOTER,
      }),
    ),
  );
}

export function isPayrollCustomId(customId) {
  return customId.startsWith('pay:');
}
