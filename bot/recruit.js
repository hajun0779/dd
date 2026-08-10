import { ButtonBuilder, ButtonStyle } from 'discord.js';

import { config } from './config.js';
import { formatBusinessHours } from './time.js';
import { panel, payload } from './components.js';

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

/** 팀과 인원만으로 공고 한 장을 만듭니다. */
export function buildRecruitContainer(team, count, { guildId = null, mentionEveryone = false } = {}) {
  const fields = [
    { name: '모집 인원', value: `${count}명` },
    { name: '하는 일', value: bullets(team.duties) },
    { name: '지원 자격', value: bullets(team.requirements) },
  ];

  if (team.preferred?.length > 0) {
    fields.push({ name: '우대 사항', value: bullets(team.preferred) });
  }

  fields.push(
    { name: '지원 방법', value: '문의 채널에서 통합 문의로 접수해 주세요.' },
    { name: '접수 시간', value: formatBusinessHours() },
    { name: '모집 기간', value: '인원이 채워지면 마감됩니다.' },
  );

  const buttons = [];
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
export function buildRecruitPayload(team, count, { guildId = null, mentionEveryone = false } = {}) {
  const message = payload(buildRecruitContainer(team, count, { guildId, mentionEveryone }));
  // 컨테이너 안의 글은 멘션이 실제로 울립니다. 켰을 때만 울리게 막아 둡니다.
  message.allowedMentions = mentionEveryone ? { parse: ['everyone'] } : { parse: [] };
  return message;
}

export async function handleRecruitCommand(interaction) {
  const team = getRecruitTeam(interaction.options.getString('팀'));
  const count = interaction.options.getInteger('인원');
  const mentionEveryone = interaction.options.getBoolean('모두멘션') ?? false;

  if (!team) {
    await interaction.reply(
      payload(
        panel({
          color: config.colors.danger,
          title: '없는 팀입니다',
          description: '목록에서 골라 주세요.',
          footer: `${config.brandName} 채용`,
        }),
        { ephemeral: true },
      ),
    );
    return;
  }

  // 명령을 쓴 채널에 그대로 올립니다.
  await interaction.reply(
    buildRecruitPayload(team, count, { guildId: interaction.guildId, mentionEveryone }),
  );
}
