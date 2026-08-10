import { config } from './config.js';
import { formatBusinessHours } from './time.js';
import { editPayload, errorPanel, neutralPanel, panel, payload, successPanel } from './components.js';

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

export function buildNoticePayload() {
  return payload(
    panel({
      color: config.colors.primary,
      title: '문의 안내',
      // 이름 없는 문단으로 넣으면 사이사이에 구분선만 들어갑니다.
      fields: [
        ...TICKET_NOTICE.map((value) => ({ name: null, value })),
        { name: '문의 가능 시간', value: formatBusinessHours() },
      ],
      footer: `${config.brandName} 문의`,
    }),
  );
}

export async function handleTicketNoticeCommand(interaction) {
  const target = interaction.options.getChannel('채널');

  // 채널을 안 고르면 명령을 쓴 채널에 그대로 올립니다.
  if (!target) {
    await interaction.reply(buildNoticePayload());
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
    await target.send(buildNoticePayload());
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
