import {
  ActionRowBuilder,
  ButtonBuilder,
  ButtonStyle,
  ModalBuilder,
  TextInputBuilder,
  TextInputStyle,
} from 'discord.js';

import { config } from './config.js';
import { store } from './store.js';
import { log } from './log.js';
import { formatKst } from './time.js';
import { editPayload, errorPanel, panel, payload, warningPanel } from './components.js';
import { ensurePanel } from './panel.js';
import { generateVerificationCode, descriptionContainsCode } from './roblox-code.js';
import { getAvatarHeadshotUrl, getUserById, getUserByUsername, profileUrl, RobloxApiError } from './roblox-api.js';

export const VERIFY_IDS = {
  start: 'verify:start',
  modal: 'verify:modal',
  usernameInput: 'verify:username',
  check: 'verify:check',
  reissue: 'verify:reissue',
};

const NICKNAME_MAX_LENGTH = 32;
const CHECK_COOLDOWN_MS = 5_000;
const checkCooldowns = new Map();

// --- 패널 ---

export function buildVerifyPanelPayload() {
  const container = panel({
    color: config.colors.primary,
    title: '로블록스 계정 인증',
    description: [
      '예천군 서버를 이용하려면 본인의 로블록스 계정을 연동해야 합니다.',
      '아래 인증 시작 버튼을 눌러 진행해 주세요.',
    ].join('\n'),
    fields: [
      {
        name: '진행 순서',
        value: [
          '1. 인증 시작 버튼을 누르고 로블록스 닉네임을 입력합니다.',
          '2. 발급된 인증 코드를 로블록스 프로필 소개란에 붙여넣고 저장합니다.',
          '3. 코드가 담긴 메시지 아래의 인증 확인 버튼을 누릅니다.',
        ].join('\n'),
      },
      {
        name: '인증 완료 시',
        value: [
          `서버 별명이 \`${config.nicknamePrefix}로블록스 닉네임\` 형식으로 변경됩니다.`,
          `<@&${config.verifiedRoleId}> 역할이 지급됩니다.`,
        ].join('\n'),
      },
      {
        name: '참고',
        value: `인증 코드는 발급 후 ${config.verifyCodeTtlMinutes}분 동안만 유효합니다. 인증이 끝나면 소개란에서 코드를 지워도 됩니다.`,
      },
    ],
    image: config.verifyPanelImageUrl,
    buttons: [
      new ButtonBuilder()
        .setCustomId(VERIFY_IDS.start)
        .setLabel('인증 시작')
        .setStyle(ButtonStyle.Primary),
    ],
    footer: '예천군 인증 시스템',
  });

  return payload(container);
}

export async function deployVerifyPanel(client) {
  return ensurePanel(client, {
    name: 'verify',
    channelId: config.verifyPanelChannelId,
    markers: [VERIFY_IDS.start],
    payload: buildVerifyPanelPayload(),
  });
}

// --- 인증 시작 (모달) ---

export async function openVerifyModal(interaction) {
  const modal = new ModalBuilder()
    .setCustomId(VERIFY_IDS.modal)
    .setTitle('로블록스 계정 인증');

  const input = new TextInputBuilder()
    .setCustomId(VERIFY_IDS.usernameInput)
    .setLabel('로블록스 닉네임')
    .setPlaceholder('프로필에 표시되는 아이디를 입력해 주세요')
    .setStyle(TextInputStyle.Short)
    .setMinLength(3)
    .setMaxLength(20)
    .setRequired(true);

  modal.addComponents(new ActionRowBuilder().addComponents(input));
  await interaction.showModal(modal);
}

/**
 * 먼저 컨테이너로 대기 메시지를 보냅니다.
 * 이렇게 해야 뒤이은 editReply 도 계속 Components V2 로 유지됩니다.
 */
async function replyWorking(interaction, description) {
  await interaction.reply(
    payload(
      panel({
        color: config.colors.neutral,
        title: '확인하는 중입니다',
        description,
        footer: '예천군 인증 시스템',
      }),
      { ephemeral: true },
    ),
  );
}

// --- 모달 제출: 코드 발급 ---

export async function handleVerifyModalSubmit(interaction) {
  await replyWorking(interaction, '로블록스에서 계정 정보를 불러오고 있습니다. 잠시만 기다려 주세요.');

  const guildId = interaction.guildId;
  if (!guildId) {
    await interaction.editReply(
      editPayload(errorPanel('인증 불가', '이 기능은 서버 안에서만 사용할 수 있습니다.')),
    );
    return;
  }

  const rawUsername = interaction.fields.getTextInputValue(VERIFY_IDS.usernameInput).trim();

  if (!/^[A-Za-z0-9_]{3,20}$/.test(rawUsername)) {
    await interaction.editReply(
      editPayload(
        errorPanel(
          '닉네임 형식 오류',
          [
            '로블록스 닉네임은 영문, 숫자, 밑줄(_)만 사용하며 3자에서 20자 사이입니다.',
            '',
            `입력한 값: \`${truncate(rawUsername, 100)}\``,
          ].join('\n'),
          { footer: '예천군 인증 시스템' },
        ),
      ),
    );
    return;
  }

  let robloxUser;
  try {
    robloxUser = await getUserByUsername(rawUsername);
  } catch (error) {
    await interaction.editReply(editPayload(robloxErrorPanel(error)));
    return;
  }

  if (!robloxUser) {
    await interaction.editReply(
      editPayload(
        errorPanel(
          '계정을 찾을 수 없습니다',
          [
            `\`${truncate(rawUsername, 100)}\` 이름의 로블록스 계정을 찾지 못했습니다.`,
            '표시 이름(Display Name)이 아닌 실제 아이디를 입력했는지 확인해 주세요.',
          ].join('\n'),
          { footer: '예천군 인증 시스템' },
        ),
      ),
    );
    return;
  }

  const existing = store.findVerifiedByRobloxId(guildId, robloxUser.id);
  if (existing && existing.userId !== interaction.user.id) {
    await interaction.editReply(
      editPayload(
        errorPanel(
          '이미 연동된 계정',
          [
            `\`${robloxUser.name}\` 계정은 이미 <@${existing.userId}> 님에게 연동되어 있습니다.`,
            '본인 계정이 맞다면 스태프에게 문의해 주세요.',
          ].join('\n'),
          { footer: '예천군 인증 시스템' },
        ),
      ),
    );
    return;
  }

  const code = generateVerificationCode();
  const issuedAt = Date.now();
  const expiresAt = issuedAt + config.verifyCodeTtlMinutes * 60_000;

  store.setPending(guildId, interaction.user.id, {
    code,
    robloxId: robloxUser.id,
    robloxName: robloxUser.name,
    robloxDisplayName: robloxUser.displayName,
    issuedAt,
    expiresAt,
  });

  const avatarUrl = await getAvatarHeadshotUrl(robloxUser.id);

  await interaction.editReply(editPayload(buildCodePanel({
    title: '인증 코드가 발급되었습니다',
    robloxName: robloxUser.name,
    robloxId: robloxUser.id,
    code,
    expiresAt,
    avatarUrl,
    lead: '아래 코드를 로블록스 프로필 소개란에 붙여넣고 저장한 뒤, 인증 확인 버튼을 눌러 주세요.',
    withGuide: true,
  })));
}

function buildCodePanel({ title, robloxName, robloxId, code, expiresAt, avatarUrl, lead, withGuide }) {
  const fields = [
    { name: '인증 코드', value: `\`\`\`\n${code}\n\`\`\`` },
  ];

  if (withGuide) {
    fields.push({
      name: '소개란 입력 방법',
      value: [
        '1. 로블록스 웹사이트 또는 앱에서 내 프로필로 이동합니다.',
        '2. 프로필 사진 옆의 연필(수정) 버튼을 누릅니다.',
        '3. 소개(About) 칸에 위 코드를 붙여넣고 저장합니다.',
      ].join('\n'),
    });
  }

  fields.push({ name: '유효 시간', value: `${formatKst(expiresAt)} 까지` });

  return panel({
    color: config.colors.warning,
    title,
    description: [
      `연동할 계정: **${robloxName}** ([프로필 열기](${profileUrl(robloxId)}))`,
      '',
      lead,
    ].join('\n'),
    thumbnail: avatarUrl ?? null,
    fields,
    buttons: [
      new ButtonBuilder()
        .setCustomId(VERIFY_IDS.check)
        .setLabel('인증 확인')
        .setStyle(ButtonStyle.Success),
      new ButtonBuilder()
        .setCustomId(VERIFY_IDS.reissue)
        .setLabel('코드 재발급')
        .setStyle(ButtonStyle.Secondary),
    ],
    footer: '예천군 인증 시스템',
  });
}

// --- 코드 재발급 ---

export async function handleVerifyReissue(interaction) {
  const guildId = interaction.guildId;
  const pending = guildId ? store.getPending(guildId, interaction.user.id) : null;

  if (!pending) {
    await interaction.update(
      editPayload(
        warningPanel(
          '진행 중인 인증이 없습니다',
          '인증 패널에서 인증 시작 버튼을 눌러 다시 진행해 주세요.',
          { footer: '예천군 인증 시스템' },
        ),
      ),
    );
    return;
  }

  const code = generateVerificationCode();
  const issuedAt = Date.now();
  const expiresAt = issuedAt + config.verifyCodeTtlMinutes * 60_000;

  store.setPending(guildId, interaction.user.id, { ...pending, code, issuedAt, expiresAt });

  await interaction.update(editPayload(buildCodePanel({
    title: '인증 코드가 재발급되었습니다',
    robloxName: pending.robloxName,
    robloxId: pending.robloxId,
    code,
    expiresAt,
    avatarUrl: null,
    lead: '이전 코드는 더 이상 사용할 수 없습니다. 아래 새 코드를 소개란에 붙여넣어 주세요.',
    withGuide: false,
  })));
}

// --- 인증 확인 ---

export async function handleVerifyCheck(interaction) {
  const guildId = interaction.guildId;
  if (!guildId) {
    await interaction.reply(
      payload(errorPanel('인증 불가', '이 기능은 서버 안에서만 사용할 수 있습니다.'), { ephemeral: true }),
    );
    return;
  }

  const cooldownKey = `${guildId}:${interaction.user.id}`;
  const now = Date.now();
  const readyAt = checkCooldowns.get(cooldownKey) ?? 0;
  if (readyAt > now) {
    const seconds = Math.ceil((readyAt - now) / 1000);
    await interaction.reply(
      payload(
        warningPanel('잠시만 기다려 주세요', `${seconds}초 후에 다시 시도할 수 있습니다.`, {
          footer: '예천군 인증 시스템',
        }),
        { ephemeral: true },
      ),
    );
    return;
  }
  checkCooldowns.set(cooldownKey, now + CHECK_COOLDOWN_MS);

  await replyWorking(interaction, '로블록스 프로필 소개란에서 인증 코드를 찾고 있습니다.');

  const pending = store.getPending(guildId, interaction.user.id);

  if (!pending) {
    await interaction.editReply(
      editPayload(
        warningPanel(
          '진행 중인 인증이 없습니다',
          '인증 패널에서 인증 시작 버튼을 눌러 처음부터 다시 진행해 주세요.',
          { footer: '예천군 인증 시스템' },
        ),
      ),
    );
    return;
  }

  if (pending.expiresAt <= now) {
    store.clearPending(guildId, interaction.user.id);
    await interaction.editReply(
      editPayload(
        warningPanel(
          '인증 코드가 만료되었습니다',
          '인증 패널에서 인증 시작 버튼을 눌러 새 코드를 발급받아 주세요.',
          { footer: '예천군 인증 시스템' },
        ),
      ),
    );
    return;
  }

  let profile;
  try {
    profile = await getUserById(pending.robloxId);
  } catch (error) {
    await interaction.editReply(editPayload(robloxErrorPanel(error)));
    return;
  }

  if (!profile) {
    await interaction.editReply(
      editPayload(
        errorPanel('프로필 조회 실패', '로블록스 프로필을 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.', {
          footer: '예천군 인증 시스템',
        }),
      ),
    );
    return;
  }

  if (!descriptionContainsCode(profile.description, pending.code)) {
    await interaction.editReply(
      editPayload(
        panel({
          color: config.colors.danger,
          title: '코드를 찾지 못했습니다',
          description: [
            `**${profile.name}** 계정의 소개란에서 인증 코드를 찾지 못했습니다.`,
            '',
            '아래 내용을 확인한 뒤 다시 눌러 주세요.',
            '- 소개란에 코드를 붙여넣고 저장 버튼까지 눌렀는지',
            '- 다른 사람의 계정이 아닌 본인 계정인지',
            '- 저장 직후에는 반영까지 몇 초 걸릴 수 있습니다',
          ].join('\n'),
          fields: [{ name: '현재 코드', value: `\`\`\`\n${pending.code}\n\`\`\`` }],
          buttons: [
            new ButtonBuilder()
              .setCustomId(VERIFY_IDS.check)
              .setLabel('다시 확인')
              .setStyle(ButtonStyle.Success),
            new ButtonBuilder()
              .setCustomId(VERIFY_IDS.reissue)
              .setLabel('코드 재발급')
              .setStyle(ButtonStyle.Secondary),
          ],
          footer: '예천군 인증 시스템',
        }),
      ),
    );
    return;
  }

  await applyVerification(interaction, profile, pending);
}

async function applyVerification(interaction, profile, pending) {
  const guildId = interaction.guildId;
  const member = await interaction.guild.members.fetch(interaction.user.id).catch(() => null);

  if (!member) {
    await interaction.editReply(
      editPayload(
        errorPanel('멤버 정보 오류', '서버에서 회원 정보를 불러오지 못했습니다. 스태프에게 문의해 주세요.', {
          footer: '예천군 인증 시스템',
        }),
      ),
    );
    return;
  }

  const desiredNickname = truncate(`${config.nicknamePrefix}${profile.name}`, NICKNAME_MAX_LENGTH);
  const results = [];

  // 역할 지급
  let roleGranted = false;
  const role = interaction.guild.roles.cache.get(config.verifiedRoleId)
    ?? (await interaction.guild.roles.fetch(config.verifiedRoleId).catch(() => null));

  if (!role) {
    results.push(`역할 지급 실패: 역할(${config.verifiedRoleId})을 찾을 수 없습니다.`);
  } else if (member.roles.cache.has(role.id)) {
    roleGranted = true;
    results.push(`역할 확인: ${role.name} (이미 보유 중)`);
  } else {
    try {
      await member.roles.add(role, '로블록스 계정 인증 완료');
      roleGranted = true;
      results.push(`역할 지급: ${role.name}`);
    } catch (error) {
      log.error('역할 지급 실패', error?.message ?? error);
      results.push('역할 지급 실패: 봇의 역할이 지급할 역할보다 위에 있는지, 역할 관리 권한이 있는지 확인해 주세요.');
    }
  }

  // 별명 변경
  let nicknameChanged = false;
  if (member.nickname === desiredNickname) {
    nicknameChanged = true;
    results.push(`별명 확인: ${desiredNickname} (이미 적용됨)`);
  } else {
    try {
      await member.setNickname(desiredNickname, '로블록스 계정 인증 완료');
      nicknameChanged = true;
      results.push(`별명 변경: ${desiredNickname}`);
    } catch (error) {
      log.error('별명 변경 실패', error?.message ?? error);
      results.push(
        `별명 변경 실패: \`${desiredNickname}\` 로 직접 변경해 주세요. (서버 소유자이거나 봇보다 높은 역할인 경우 변경할 수 없습니다.)`,
      );
    }
  }

  store.clearPending(guildId, interaction.user.id);
  store.setVerified(guildId, interaction.user.id, {
    robloxId: profile.id,
    robloxName: profile.name,
    robloxDisplayName: profile.displayName,
    verifiedAt: Date.now(),
  });

  const avatarUrl = await getAvatarHeadshotUrl(profile.id);
  const fullSuccess = roleGranted && nicknameChanged;

  await interaction.editReply(
    editPayload(
      panel({
        color: fullSuccess ? config.colors.success : config.colors.warning,
        title: fullSuccess ? '인증이 완료되었습니다' : '인증은 완료되었으나 일부 적용에 실패했습니다',
        description: [
          `**${profile.name}** 계정과 연동되었습니다.`,
          `[로블록스 프로필 열기](${profileUrl(profile.id)})`,
          '',
          '소개란에 넣은 인증 코드는 이제 지우셔도 됩니다.',
        ].join('\n'),
        thumbnail: avatarUrl ?? null,
        fields: [
          { name: '연동 계정', value: `${profile.name} (ID: ${profile.id})` },
          { name: '인증 시각', value: formatKst(Date.now()) },
          { name: '처리 결과', value: results.join('\n') },
        ],
        footer: '예천군 인증 시스템',
      }),
    ),
  );

  log.info(
    `인증 완료: ${interaction.user.tag} (${interaction.user.id}) -> 로블록스 ${profile.name} (${profile.id})`,
  );
}

// --- 도우미 ---

function robloxErrorPanel(error) {
  if (error instanceof RobloxApiError) {
    return errorPanel('로블록스 연결 오류', `${error.message}\n\n잠시 후 다시 시도해 주세요.`, {
      footer: '예천군 인증 시스템',
    });
  }
  log.error('예상하지 못한 로블록스 오류', error);
  return errorPanel('알 수 없는 오류', '요청을 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.', {
    footer: '예천군 인증 시스템',
  });
}

function truncate(value, max) {
  const text = String(value ?? '');
  return text.length <= max ? text : text.slice(0, max);
}

export function isVerificationCustomId(customId) {
  return customId.startsWith('verify:');
}
