import { config, TICKET_TYPES } from './config.js';
import { formatBusinessHours, formatKst } from './time.js';
import { editPayload, neutralPanel, panel, payload } from './components.js';
import { canUseCommand } from './permissions.js';

const FOOTER = `${config.brandName} 안내`;

// ===========================================================================
//  명령 안내
//
//  명령을 더하면 이 목록에도 한 줄 넣어 주세요.
// ===========================================================================
export const COMMAND_GUIDE = [
  {
    value: 'ticket',
    label: '문의',
    commands: [
      ['/티켓패널', '문의 패널을 다시 올립니다.'],
      ['/문의안내', '문의 안내를 올립니다.'],
      ['/문의안내추가', '문의 안내에 문단을 더합니다.'],
      ['/문의안내삭제', '더했던 문단을 뺍니다.'],
    ],
  },
  {
    value: 'notice',
    label: '안내와 명단',
    commands: [
      ['/이용약관', '이용약관을 올립니다.'],
      ['/수리약관', 'A/S 약관을 올립니다.'],
      ['/채용공고', '팀과 인원을 고르면 공고가 완성됩니다.'],
      ['/파트너쉽', '파트너 안내를 올립니다.'],
      ['/직원명단', '직원 명단을 올립니다.'],
      ['/직원명단설정', '명단에 쓸 역할과 직책을 정합니다.'],
    ],
  },
  {
    value: 'invite',
    label: '초대',
    commands: [
      ['/초대코드', '내 초대 코드를 만들고 들어온 사람 수를 봅니다.'],
      ['/초대랭킹', '초대를 많이 한 순서로 봅니다.'],
      ['/초대복구', '부풀려진 초대 수를 되돌립니다.'],
    ],
  },
  {
    value: 'work',
    label: '업무',
    commands: [
      ['/분야설정', '직원을 분야에 넣고 뺍니다.'],
      ['/배당', '분야를 골라 업무를 맡깁니다.'],
      ['/수리', '배당한 프로젝트의 수리를 맡깁니다.'],
      ['/급여지급', '직원에게 급여 안내를 보냅니다.'],
      ['/지급상태', '지금까지 지급된 급여를 봅니다.'],
    ],
  },
  {
    value: 'product',
    label: '제품과 정산',
    commands: [
      ['/제품설정', '제품을 등록하고 관리합니다.'],
      ['/제품전송', '제품을 특정 유저에게 보냅니다.'],
      ['/송금요청', '계좌를 DM 으로 보내고 입금을 확인합니다.'],
    ],
  },
  {
    value: 'etc',
    label: '그 밖에',
    commands: [
      ['/도움말', '이 안내를 봅니다.'],
      ['/설정확인', '아직 안 채운 설정과 그래서 안 되는 기능을 봅니다.'],
    ],
  },
];

export const HELP_CHOICES = COMMAND_GUIDE.map((group) => ({
  name: group.label,
  value: group.value,
}));

/** 이름 앞의 슬래시를 떼서 권한 판정에 씁니다. */
function commandName(entry) {
  return entry[0].replace(/^\//, '').split(' ')[0];
}

export function buildHelpFields(member, only = null) {
  const groups = only ? COMMAND_GUIDE.filter((g) => g.value === only) : COMMAND_GUIDE;
  const fields = [];

  for (const group of groups) {
    const usable = group.commands.filter((entry) => canUseCommand(member, commandName(entry)));
    if (usable.length === 0) continue;
    fields.push({
      name: group.label,
      value: usable.map(([name, desc]) => `${name} — ${desc}`).join('\n'),
    });
  }

  return fields;
}

export async function handleHelpCommand(interaction) {
  const only = interaction.options.getString('분류');
  const fields = buildHelpFields(interaction.member, only);

  await interaction.reply(
    payload(
      panel({
        color: config.colors.primary,
        title: '명령 안내',
        description:
          fields.length === 0
            ? '지금 쓸 수 있는 명령이 없습니다.'
            : '쓸 수 있는 명령만 보여 드립니다.',
        fields: [
          ...fields,
          { name: '문의 시간', value: formatBusinessHours() },
        ],
        footer: FOOTER,
      }),
      { ephemeral: true },
    ),
  );
}

// ===========================================================================
//  설정 확인
// ===========================================================================

/** 채워야 하는 값과, 비었을 때 못 쓰는 기능 */
function checklist() {
  return [
    ['STORAGE_CHANNEL_ID', config.storageChannelId, 'channel',
      '제품, 배당, 급여, 송금, 초대 코드, 문의 안내 문단'],
    ['ADMIN_ROLE_ID', config.adminRoleId, 'role', '총관리자 보고와 확인 버튼'],
    ['ASSIGN_LIST_CHANNEL_ID', config.assignListChannelId, 'channel', '배당 목록 게시'],
    ['ASSIGN_STATUS_CHANNEL_ID', config.assignStatusChannelId, 'channel', '수락, 완료, 중단 알림'],
    ['WARNING_CHANNEL_ID', config.warningChannelId, 'channel', '직원 경고 상태판'],
    ['PAYROLL_CHANNEL_ID', config.payrollChannelId, 'channel', '급여 신청 게시'],
    ['PAYMENT_LOG_CHANNEL_ID', config.paymentLogChannelId, 'channel', '송금 확인 기록'],
    ['RECRUIT_CHANNEL_ID', config.recruitChannelId, 'channel', '채용 지원서 접수'],
    ['REVIEW_CHANNEL_ID', config.reviewChannelId, 'channel', '후기 게시'],
    ['PRODUCT_APPROVAL_ROLE_ID', config.productRoleId, 'role', '제품 등록과 전송'],
    ['INVITE_LOG_CHANNEL_ID', config.inviteLogChannelId, 'channel', '초대 기록 채널 게시'],
    ['TICKET_PANEL_CHANNEL_ID', config.ticketPanelChannelId, 'channel', '문의 패널'],
    ['TICKET_STAFF_ROLE_ID', config.ticketStaffRoleId, 'role', '문의 채널 열람'],
    ['TICKET_TRANSCRIPT_CHANNEL_ID', config.ticketTranscriptChannelId, 'channel', '문의 기록 보관'],
    ['WELCOME_CHANNEL_ID', config.welcomeChannelId, 'channel', '환영 메시지'],
    ['STAFF_LIST_CHANNEL_ID', config.staffListChannelId, 'channel', '직원 명단 자동 갱신'],
  ];
}

/** 설정한 ID 가 실제로 보이는지 확인합니다. */
async function probe(interaction, kind, id) {
  if (!id) return 'empty';

  if (kind === 'role') {
    const role = await interaction.guild?.roles.fetch(id).catch(() => null);
    return role ? 'ok' : 'missing';
  }

  const channel = await interaction.client.channels.fetch(id).catch(() => null);
  if (!channel?.isTextBased?.()) return 'missing';
  return channel.guildId && channel.guildId !== interaction.guildId ? 'other' : 'ok';
}

const MARK = {
  ok: '확인됨',
  empty: '비어 있음',
  missing: '찾지 못함',
  other: '다른 서버',
};

export async function handleConfigCheckCommand(interaction) {
  await interaction.reply(
    payload(neutralPanel('잠시만 기다려 주세요', '설정을 확인하고 있습니다.', { footer: FOOTER }), {
      ephemeral: true,
    }),
  );

  const rows = [];
  for (const [name, value, kind, feature] of checklist()) {
    rows.push({ name, value, feature, state: await probe(interaction, kind, value) });
  }

  const broken = rows.filter((row) => row.state === 'missing' || row.state === 'other');
  const empty = rows.filter((row) => row.state === 'empty');
  const fine = rows.filter((row) => row.state === 'ok');

  const fields = [];

  if (broken.length > 0) {
    fields.push({
      name: '고쳐야 합니다',
      value: broken
        .map((row) => `${row.name} — ${MARK[row.state]} (\`${row.value}\`)`)
        .join('\n'),
    });
  }

  if (empty.length > 0) {
    fields.push({
      name: '아직 안 채웠습니다',
      value: empty.map((row) => `${row.name} — ${row.feature}`).join('\n'),
    });
  }

  fields.push({ name: '확인된 설정', value: `${fine.length}개 / 전체 ${rows.length}개` });

  const sharedCategories = TICKET_TYPES.filter(
    (type) => type.value !== 'general' && type.categoryId === TICKET_TYPES[0].categoryId,
  );
  if (sharedCategories.length > 0) {
    fields.push({
      name: '문의 카테고리',
      value: `${sharedCategories.map((t) => t.label).join(', ')} 가 통합 문의 카테고리를 같이 씁니다.`,
    });
  }

  fields.push({ name: '문의 시간', value: formatBusinessHours() });
  fields.push({ name: '지금 한국 시간', value: formatKst(Date.now()) });

  const color = broken.length > 0
    ? config.colors.danger
    : empty.length > 0
      ? config.colors.warning
      : config.colors.success;

  await interaction.editReply(
    editPayload(
      panel({
        color,
        title: '설정 확인',
        description:
          broken.length > 0
            ? '값이 잘못되었거나 봇이 못 보는 설정이 있습니다.'
            : empty.length > 0
              ? '비어 있는 설정이 있습니다. 그만큼 기능이 꺼져 있습니다.'
              : '설정이 모두 확인되었습니다.',
        fields,
        footer: FOOTER,
      }),
    ),
  );
}
