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
import { formatBusinessHours, formatKst } from './time.js';
import { editPayload, errorPanel, neutralPanel, panel, payload, successPanel } from './components.js';
import { notifyAdmins, parseDeadline, postToChannel } from './assignments.js';

const FOOTER = `${config.brandName} 채용`;

export const RECRUIT_IDS = {
  apply: 'hire:apply',
  form: 'hire:form',
};

export function isRecruitCustomId(customId) {
  return customId.startsWith('hire:');
}

// ===========================================================================
//  채용 공고 내용
//
//  팀을 더하거나 문구를 고치려면 아래 목록만 손보면 됩니다.
//  /채용공고 의 선택지도 이 목록에서 그대로 만들어집니다. (디스코드 제한 최대 25개)
// ===========================================================================
export const RECRUIT_TEAMS = [
  {
    value: 'marketing',
    label: '마케팅팀',
    summary: '서버를 알리고 제휴를 맡아 주실 분을 찾습니다.',
    duties: ['서버와 제품 홍보', '제휴 서버 관리와 연락', '공지와 안내문 작성'],
    requirements: [
      '디스코드를 자주 쓰시는 분',
      '하루 한 번 이상 접속하실 수 있는 분',
      '맡은 일을 기한 안에 마치실 수 있는 분',
    ],
    preferred: ['홍보나 제휴를 해 보신 분', '이미지 편집이 가능하신 분'],
  },
  {
    value: 'dev',
    label: '개발팀',
    summary: '의뢰받은 제품을 만들어 주실 분을 찾습니다.',
    duties: ['로블록스 스크립트 작성과 수정', '의뢰받은 제품 제작', '전달한 제품의 A/S'],
    requirements: [
      '직접 만들어 보신 작업물을 보여 주실 수 있는 분',
      '맡은 일을 기한 안에 마치실 수 있는 분',
      '작업 상황을 중간에 알려 주실 수 있는 분',
    ],
    preferred: ['팀으로 작업해 보신 분', '스튜디오 협업(Team Create)에 익숙하신 분'],
  },
  {
    value: 'ops',
    label: '운영팀',
    summary: '문의를 받고 서버를 관리해 주실 분을 찾습니다.',
    duties: ['문의 응대', '서버 규칙 관리', '분쟁 중재와 기록 정리'],
    requirements: [
      '문의 시간에 접속하실 수 있는 분',
      '차분하게 대화하실 수 있는 분',
      '규칙을 일관되게 지키실 수 있는 분',
    ],
    preferred: ['커뮤니티를 운영해 보신 분', '문의 응대를 해 보신 분'],
  },
];

export function getRecruitTeam(value) {
  return RECRUIT_TEAMS.find((team) => team.value === value) ?? null;
}

/** 슬래시 명령 선택지 */
export const RECRUIT_CHOICES = RECRUIT_TEAMS.slice(0, 25).map((team) => ({
  name: team.label,
  value: team.value,
}));

const bullets = (list) => list.map((item) => `- ${item}`).join('\n');

/** 마감 시각을 상호작용 ID 에 짧게 실어 나릅니다. */
export function packDeadline(dueAt) {
  return Math.floor(dueAt / 1000).toString(36);
}

export function unpackDeadline(text) {
  // parseInt 는 뒤에 이상한 글자가 붙어도 앞부분만 읽고 넘어갑니다.
  // 상호작용 ID 가 망가진 경우를 그냥 지나치지 않도록 먼저 모양을 봅니다.
  const value = String(text ?? '');
  if (!/^[0-9a-z]+$/.test(value)) return null;

  const seconds = Number.parseInt(value, 36);
  return Number.isFinite(seconds) && seconds > 0 ? seconds * 1000 : null;
}

/** 팀과 인원, 접수 기간만으로 공고 한 장을 만듭니다. */
export function buildRecruitContainer(
  team,
  count,
  { guildId = null, mentionEveryone = false, dueAt = null } = {},
) {
  const fields = [
    { name: '모집 인원', value: `${count}명` },
    { name: '하는 일', value: bullets(team.duties) },
    { name: '지원 자격', value: bullets(team.requirements) },
  ];

  if (team.preferred?.length > 0) {
    fields.push({ name: '우대 사항', value: bullets(team.preferred) });
  }

  const closed = dueAt !== null && dueAt <= Date.now();

  fields.push(
    { name: '지원 방법', value: '아래 접수하기 버튼을 눌러 지원서를 작성해 주세요.' },
    {
      name: '접수 기간',
      value: dueAt === null
        ? '인원이 채워지면 마감됩니다.'
        : `${formatKst(dueAt)} 까지${closed ? ' (마감)' : ''}`,
    },
    { name: '문의 시간', value: formatBusinessHours() },
  );

  const buttons = [
    new ButtonBuilder()
      .setCustomId(`${RECRUIT_IDS.apply}:${team.value}:${dueAt === null ? '0' : packDeadline(dueAt)}`)
      .setLabel(closed ? '접수 마감' : '접수하기')
      .setStyle(closed ? ButtonStyle.Secondary : ButtonStyle.Success)
      .setDisabled(closed),
  ];

  if (guildId && config.ticketPanelChannelId) {
    buttons.push(
      new ButtonBuilder()
        .setLabel('문의 채널로 가기')
        .setStyle(ButtonStyle.Link)
        .setURL(`https://discord.com/channels/${guildId}/${config.ticketPanelChannelId}`),
    );
  }

  const intro = `${config.brandName} 에서 ${team.label}과 함께하실 ${count}명을 모집합니다.\n${team.summary}`;

  return panel({
    color: config.colors.primary,
    title: `${team.label} 채용`,
    description: mentionEveryone ? `@everyone\n\n${intro}` : intro,
    fields,
    buttons,
    footer: `${config.brandName} 채용`,
  });
}

/** 공고 메시지 하나를 통째로 만듭니다. */
export function buildRecruitPayload(
  team,
  count,
  { guildId = null, mentionEveryone = false, dueAt = null } = {},
) {
  const message = payload(buildRecruitContainer(team, count, { guildId, mentionEveryone, dueAt }));
  // 컨테이너 안의 글은 멘션이 실제로 울립니다. 켰을 때만 울리게 막아 둡니다.
  message.allowedMentions = mentionEveryone ? { parse: ['everyone'] } : { parse: [] };
  return message;
}

export async function handleRecruitCommand(interaction) {
  const team = getRecruitTeam(interaction.options.getString('팀'));
  const count = interaction.options.getInteger('인원');
  const mentionEveryone = interaction.options.getBoolean('모두멘션') ?? false;
  const deadlineInput = interaction.options.getString('접수기간').trim();

  if (!team) {
    await interaction.reply(
      payload(errorPanel('없는 팀입니다', '목록에서 골라 주세요.', { footer: FOOTER }), {
        ephemeral: true,
      }),
    );
    return;
  }

  const dueAt = parseDeadline(deadlineInput);
  if (dueAt === null || dueAt <= Date.now()) {
    await interaction.reply(
      payload(
        errorPanel(
          '접수 기간을 읽지 못했습니다',
          '`7일`, `48시간`, `2026-08-20 23:59` 처럼 적어 주세요. 지난 시각은 넣을 수 없습니다.',
          { footer: FOOTER },
        ),
        { ephemeral: true },
      ),
    );
    return;
  }

  // 명령을 쓴 채널에 그대로 올립니다.
  await interaction.reply(
    buildRecruitPayload(team, count, { guildId: interaction.guildId, mentionEveryone, dueAt }),
  );
}

// ---------------------------------------------------------------------------
//  접수하기
// ---------------------------------------------------------------------------

/**
 * 지원서 칸입니다.
 * 디스코드 창에는 다섯 칸까지 들어갑니다.
 * 포트폴리오는 개발팀만 구글 드라이브 링크를 필수로 받습니다.
 */
export function buildApplicationModal(team, deadlinePart) {
  const isDev = team.value === 'dev';

  const modal = new ModalBuilder()
    .setCustomId(`${RECRUIT_IDS.form}:${team.value}:${deadlinePart}`)
    .setTitle(`${team.label} 지원서`.slice(0, 45));

  const inputs = [
    new TextInputBuilder()
      .setCustomId('intro')
      .setLabel('자기소개')
      .setPlaceholder('이름 또는 별명, 나이대, 어떤 일을 해 오셨는지 적어 주세요.')
      .setStyle(TextInputStyle.Paragraph)
      .setMaxLength(900)
      .setRequired(true),

    new TextInputBuilder()
      .setCustomId('portfolio')
      .setLabel(isDev ? '포트폴리오 (구글 드라이브 링크)' : '포트폴리오 (없으면 없음)')
      .setPlaceholder(isDev ? 'https://drive.google.com/...' : '링크 또는 없음')
      .setStyle(TextInputStyle.Short)
      .setMaxLength(300)
      .setRequired(isDev),

    new TextInputBuilder()
      .setCustomId('available')
      .setLabel('활동 가능 시간')
      .setPlaceholder('예: 평일 오후 7시 ~ 11시, 주말 종일')
      .setStyle(TextInputStyle.Short)
      .setMaxLength(100)
      .setRequired(true),

    new TextInputBuilder()
      .setCustomId('reason')
      .setLabel('지원 동기')
      .setPlaceholder('왜 지원하셨는지 적어 주세요.')
      .setStyle(TextInputStyle.Paragraph)
      .setMaxLength(900)
      .setRequired(true),

    new TextInputBuilder()
      .setCustomId('commitment')
      .setLabel('열심히 할 의향이 있으신가요')
      .setPlaceholder('예: 네, 맡은 일은 끝까지 책임지고 하겠습니다.')
      .setStyle(TextInputStyle.Paragraph)
      .setMaxLength(300)
      .setRequired(true),
  ];

  modal.addComponents(...inputs.map((input) => new ActionRowBuilder().addComponents(input)));
  return modal;
}

export function isDriveLink(value) {
  return /^https:\/\/(drive|docs)\.google\.com\/\S+$/i.test(String(value ?? '').trim());
}

/** 접수하기 버튼 */
export async function handleRecruitApply(interaction) {
  const [teamValue, deadlinePart] = interaction.customId
    .slice(`${RECRUIT_IDS.apply}:`.length)
    .split(':');

  const team = getRecruitTeam(teamValue);
  if (!team) {
    await interaction.reply(
      payload(errorPanel('접수할 수 없습니다', '없는 공고입니다.', { footer: FOOTER }), {
        ephemeral: true,
      }),
    );
    return;
  }

  const dueAt = deadlinePart === '0' ? null : unpackDeadline(deadlinePart);
  if (dueAt !== null && dueAt <= Date.now()) {
    await interaction.reply(
      payload(
        errorPanel('접수가 마감되었습니다', `${formatKst(dueAt)} 에 마감되었습니다.`, { footer: FOOTER }),
        { ephemeral: true },
      ),
    );
    return;
  }

  await interaction.showModal(buildApplicationModal(team, deadlinePart));
}

/** 지원서 제출 */
export async function handleRecruitSubmit(interaction) {
  const [teamValue, deadlinePart] = interaction.customId
    .slice(`${RECRUIT_IDS.form}:`.length)
    .split(':');

  await interaction.reply(
    payload(neutralPanel('잠시만 기다려 주세요', '지원서를 접수하고 있습니다.', { footer: FOOTER }), {
      ephemeral: true,
    }),
  );

  const team = getRecruitTeam(teamValue);
  if (!team) {
    await interaction.editReply(
      editPayload(errorPanel('접수할 수 없습니다', '없는 공고입니다.', { footer: FOOTER })),
    );
    return;
  }

  const dueAt = deadlinePart === '0' ? null : unpackDeadline(deadlinePart);
  if (dueAt !== null && dueAt <= Date.now()) {
    await interaction.editReply(
      editPayload(
        errorPanel('접수가 마감되었습니다', `${formatKst(dueAt)} 에 마감되었습니다.`, { footer: FOOTER }),
      ),
    );
    return;
  }

  const answers = {
    intro: interaction.fields.getTextInputValue('intro').trim(),
    portfolio: (interaction.fields.getTextInputValue('portfolio') ?? '').trim(),
    available: interaction.fields.getTextInputValue('available').trim(),
    reason: interaction.fields.getTextInputValue('reason').trim(),
    commitment: interaction.fields.getTextInputValue('commitment').trim(),
  };

  // 개발팀은 포트폴리오를 구글 드라이브로만 받습니다.
  if (team.value === 'dev' && !isDriveLink(answers.portfolio)) {
    await interaction.editReply(
      editPayload(
        errorPanel(
          '포트폴리오 링크를 확인해 주세요',
          [
            '개발팀은 포트폴리오를 구글 드라이브로 받습니다.',
            '`https://drive.google.com/...` 로 시작하는 링크를 넣어 주세요.',
            '링크를 아는 사람은 볼 수 있게 공유 설정을 바꾼 뒤 넣어 주세요.',
          ].join('\n'),
          { footer: FOOTER },
        ),
      ),
    );
    return;
  }

  const container = panel({
    color: config.colors.primary,
    title: `${team.label} 지원서`,
    description: `<@${interaction.user.id}> (${interaction.user.tag})`,
    fields: [
      { name: '자기소개', value: answers.intro },
      { name: '포트폴리오', value: answers.portfolio.length > 0 ? answers.portfolio : '없음' },
      { name: '활동 가능 시간', value: answers.available },
      { name: '지원 동기', value: answers.reason },
      { name: '열심히 할 의향', value: answers.commitment },
      { name: '접수 시각', value: formatKst(Date.now()) },
    ],
    footer: FOOTER,
  });

  const posted = await postToChannel(interaction.client, config.recruitChannelId, container);
  if (!posted) {
    // 지원서 채널이 없으면 총관리자에게라도 보냅니다.
    await notifyAdmins(interaction.client, interaction.guild, container);
  }

  await interaction.editReply(
    editPayload(
      successPanel('접수했습니다', `${team.label} 지원서를 받았습니다. 확인 후 따로 연락드리겠습니다.`, {
        footer: FOOTER,
      }),
    ),
  );

  log.info(`채용 지원: ${team.label} <- ${interaction.user.tag}`);
}
