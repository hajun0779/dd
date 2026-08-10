import { config } from './config.js';
import { log } from './log.js';
import { formatBusinessHours } from './time.js';
import { editPayload, errorPanel, neutralPanel, panel, payload, successPanel } from './components.js';
import {
  MARKERS,
  StorageError,
  addRecord,
  listRecords,
  makeRecordId,
  removeRecord,
} from './storage.js';

const FOOTER = `${config.brandName} 문의`;
const MAX_BLOCK = 900;

// ===========================================================================
//  문의 안내 내용
//
//  /문의안내 로 올라가는 글입니다.
//  문단을 더하거나 지우면 그대로 반영됩니다. 문단 사이에는 구분선이 들어갑니다.
// ===========================================================================
export const TICKET_NOTICE = [
  [
    '제품 문의를 통해 주문 제작 신청이 가능합니다!',
    '현재 로블록스 애셋 및 맵 주문 제작과 디스코드 봇 외주 문의를 주로 받고 있습니다.',
    '주문 제작이 필요하신 경우 제품 문의 티켓을 열어주세요.',
  ].join('\n'),
  [
    '제휴 문의도 언제든지 받고 있습니다!',
    '서버 간 파트너십 및 제휴를 희망하시는 경우 파트너 문의 티켓을 열어주시면 확인 후 안내드리겠습니다.',
  ].join('\n'),
  [
    '문의 가능 시간이 지나거나 문의 시간 이전에 티켓을 생성하실 경우 운영팀에게 별도의 멘션 알림이 전송되지 않습니다.',
    '빠른 확인과 처리를 원하신다면 가급적 문의 가능 시간 내에 티켓을 생성해 주시기 바랍니다.',
  ].join('\n'),
];

function storageErrorPanel(error) {
  if (error instanceof StorageError) {
    return errorPanel('보관 채널을 쓸 수 없습니다', error.message, { footer: FOOTER });
  }
  log.error('문의 안내 처리 오류', error?.stack ?? error);
  return errorPanel('오류가 발생했습니다', '잠시 후 다시 시도해 주세요.', { footer: FOOTER });
}

/** /문의안내추가 로 더한 문단을 읽어옵니다. */
export async function readExtraBlocks(client, guildId) {
  if (!config.storageChannelId) return [];

  try {
    const records = await listRecords(client, MARKERS.notice);
    return records
      .filter((record) => !guildId || record.guildId === guildId)
      .filter((record) => typeof record.text === 'string' && record.text.trim().length > 0);
  } catch (error) {
    log.debug('더한 문의 안내를 읽지 못했습니다.', error?.message ?? error);
    return [];
  }
}

export function buildNoticePayload(extra = []) {
  const blocks = [...TICKET_NOTICE, ...extra.map((item) => item.text ?? item)];

  return payload(
    panel({
      color: config.colors.primary,
      title: '문의 안내',
      // 이름 없는 문단으로 넣으면 사이사이에 구분선만 들어갑니다.
      fields: [
        ...blocks.map((value) => ({ name: null, value })),
        { name: '문의 가능 시간', value: formatBusinessHours() },
      ],
      footer: FOOTER,
    }),
  );
}

export async function handleTicketNoticeCommand(interaction) {
  const target = interaction.options.getChannel('채널');
  const extra = await readExtraBlocks(interaction.client, interaction.guildId);

  // 채널을 안 고르면 명령을 쓴 채널에 그대로 올립니다.
  if (!target) {
    await interaction.reply(buildNoticePayload(extra));
    return;
  }

  await interaction.reply(
    payload(neutralPanel('잠시만 기다려 주세요', '문의 안내를 올리고 있습니다.'), { ephemeral: true }),
  );

  if (!target.isTextBased?.()) {
    await interaction.editReply(
      editPayload(errorPanel('올릴 수 없는 채널입니다', '글을 쓸 수 있는 채널을 골라 주세요.')),
    );
    return;
  }

  try {
    await target.send(buildNoticePayload(extra));
  } catch {
    await interaction.editReply(
      editPayload(
        errorPanel('올리지 못했습니다', `봇에게 ${target} 에 글을 쓸 권한이 있는지 확인해 주세요.`),
      ),
    );
    return;
  }

  await interaction.editReply(
    editPayload(successPanel('올렸습니다', `${target} 에 문의 안내를 올렸습니다.`)),
  );
}

// ---------------------------------------------------------------------------
//  문단 더하기와 빼기
//
//  더한 문단은 보관 채널에 메시지로 남습니다. 봇을 다시 켜도 그대로 있습니다.
//  기본 문단 셋은 notice.js 안에 있어서 여기서는 지울 수 없습니다.
// ---------------------------------------------------------------------------

export async function handleNoticeAddCommand(interaction) {
  await interaction.reply(
    payload(neutralPanel('잠시만 기다려 주세요', '문단을 더하고 있습니다.', { footer: FOOTER }), {
      ephemeral: true,
    }),
  );

  // 줄바꿈을 넣을 수 있도록 \n 을 실제 줄바꿈으로 바꿔 줍니다.
  const text = interaction.options.getString('내용').replaceAll('\\n', '\n').trim();

  if (text.length === 0 || text.length > MAX_BLOCK) {
    await interaction.editReply(
      editPayload(
        errorPanel('내용이 올바르지 않습니다', `1자에서 ${MAX_BLOCK}자 사이로 적어 주세요.`, {
          footer: FOOTER,
        }),
      ),
    );
    return;
  }

  let saved;
  try {
    saved = await addRecord(interaction.client, MARKERS.notice, {
      id: makeRecordId('n'),
      guildId: interaction.guildId,
      text,
      createdAt: Date.now(),
      createdBy: interaction.user.id,
    });
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  const extra = await readExtraBlocks(interaction.client, interaction.guildId);

  await interaction.editReply(
    editPayload(
      successPanel('더했습니다', text, {
        fields: [
          { name: '더한 문단', value: `${extra.length}개` },
          { name: '확인', value: '`/문의안내` 로 올리면 이 문단이 함께 나갑니다.' },
        ],
        footer: FOOTER,
      }),
    ),
  );

  log.info(`문의 안내 문단 추가 (${interaction.user.tag}): ${saved.id}`);
}

export async function handleNoticeRemoveCommand(interaction) {
  await interaction.reply(
    payload(neutralPanel('잠시만 기다려 주세요', '문단을 빼고 있습니다.', { footer: FOOTER }), {
      ephemeral: true,
    }),
  );

  const id = interaction.options.getString('문단');

  let removed = false;
  try {
    removed = await removeRecord(interaction.client, MARKERS.notice, id);
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  await interaction.editReply(
    editPayload(
      removed
        ? successPanel('뺐습니다', '`/문의안내` 로 다시 올리면 반영됩니다.', { footer: FOOTER })
        : errorPanel('찾지 못했습니다', '이미 빠졌거나 없는 문단입니다.', { footer: FOOTER }),
    ),
  );
}

/** 뺄 문단을 목록에서 고르게 합니다. */
export async function handleNoticeAutocomplete(interaction) {
  const focused = String(interaction.options.getFocused() ?? '').toLowerCase();
  const extra = await readExtraBlocks(interaction.client, interaction.guildId);

  const matches = extra
    .filter((record) => record.text.toLowerCase().includes(focused))
    .slice(0, 25)
    .map((record, index) => ({
      name: `${index + 1}. ${record.text.replaceAll('\n', ' ')}`.slice(0, 100),
      value: record.id,
    }));

  await interaction.respond(matches).catch(() => {});
}
