import { config } from './config.js';
import { log } from './log.js';
import { editPayload, errorPanel, neutralPanel, panel, payload, successPanel } from './components.js';
import { readSettings, writeSettings, StorageError } from './storage.js';

const MAX_STARS = 5;
const MAX_ROLES = 20;

function stars(count) {
  const value = Math.min(MAX_STARS, Math.max(1, Number(count) || 1));
  return '★'.repeat(value);
}

/** 별이 많은 순서로, 같으면 먼저 등록한 순서로 정렬합니다. */
function sortRoles(roles) {
  return [...roles].sort((a, b) => b.stars - a.stars || a.addedAt - b.addedAt);
}

/**
 * 명단 본문을 만듭니다.
 *
 *   [★★★★★]
 *   Head Director - @사람
 *
 * @param {Array<{roleId: string, title: string, stars: number, addedAt: number}>} entries
 * @param {(roleId: string) => string[]} getMemberIds 역할에 속한 사람의 ID 목록
 */
export function formatStaffList(entries, getMemberIds) {
  return sortRoles(entries)
    .map((entry) => {
      const ids = getMemberIds(entry.roleId) ?? [];
      const names = ids.map((id) => `<@${id}>`).join(' ');
      return `**[${stars(entry.stars)}]**\n${entry.title} - ${names.length > 0 ? names : '공석'}`;
    })
    .join('\n\n');
}

// --- 명단 ---

export async function handleStaffListCommand(interaction) {
  await interaction.reply(
    payload(neutralPanel('잠시만 기다려 주세요', '명단을 불러오고 있습니다.'), { ephemeral: true }),
  );

  let settings;
  try {
    settings = await readSettings(interaction.client);
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  const roles = sortRoles(settings.staffRoles);
  if (roles.length === 0) {
    await interaction.editReply(
      editPayload(
        neutralPanel(
          '등록된 직책이 없습니다',
          '`/직원명단설정 추가` 로 역할과 직책을 먼저 등록해 주세요.',
        ),
      ),
    );
    return;
  }

  // 역할에 속한 사람을 세려면 서버 인원 정보를 한 번 받아와야 합니다.
  await interaction.guild.members.fetch().catch((error) => {
    log.warn('서버 인원 정보를 받아오지 못했습니다. SERVER MEMBERS INTENT 를 확인해 주세요.', error?.message ?? error);
  });

  const description = formatStaffList(roles, (roleId) => {
    const role = interaction.guild.roles.cache.get(roleId);
    return role ? [...role.members.keys()] : [];
  });

  const container = panel({
    color: config.colors.primary,
    title: '직원 명단',
    description,
    footer: `${config.brandName} 직원 명단`,
  });

  // 명령을 쓴 채널에 그대로 올립니다.
  await interaction.editReply(editPayload(successPanel('올렸습니다', '아래에 명단을 게시했습니다.')));
  await interaction.channel
    ?.send({ ...payload(container), allowedMentions: { parse: [] } })
    .catch((error) => log.error('직원 명단 게시 실패', error?.message ?? error));
}

// --- 설정 ---

export async function handleStaffSetupCommand(interaction) {
  const sub = interaction.options.getSubcommand();

  await interaction.reply(
    payload(neutralPanel('잠시만 기다려 주세요', '설정을 불러오고 있습니다.'), { ephemeral: true }),
  );

  let settings;
  try {
    settings = await readSettings(interaction.client);
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  if (sub === '목록') {
    const roles = sortRoles(settings.staffRoles);
    await interaction.editReply(
      editPayload(
        panel({
          color: config.colors.neutral,
          title: '등록된 직책',
          description:
            roles.length === 0
              ? '아직 등록된 직책이 없습니다.'
              : roles
                  .map((entry) => `[${stars(entry.stars)}] ${entry.title} - <@&${entry.roleId}>`)
                  .join('\n'),
        }),
      ),
    );
    return;
  }

  if (sub === '삭제') {
    const role = interaction.options.getRole('역할');
    const before = settings.staffRoles.length;
    settings.staffRoles = settings.staffRoles.filter((entry) => entry.roleId !== role.id);

    if (settings.staffRoles.length === before) {
      await interaction.editReply(
        editPayload(errorPanel('없는 직책입니다', `<@&${role.id}> 는 등록되어 있지 않습니다.`)),
      );
      return;
    }

    try {
      await writeSettings(interaction.client, settings);
    } catch (error) {
      await interaction.editReply(editPayload(storageErrorPanel(error)));
      return;
    }

    await interaction.editReply(
      editPayload(successPanel('지웠습니다', `<@&${role.id}> 를 명단에서 뺐습니다.`)),
    );
    return;
  }

  // 추가 (같은 역할을 다시 넣으면 덮어씁니다)
  const role = interaction.options.getRole('역할');
  const title = interaction.options.getString('직책').trim();
  const starCount = interaction.options.getInteger('별');

  if (title.length === 0 || title.length > 40) {
    await interaction.editReply(
      editPayload(errorPanel('직책 이름이 올바르지 않습니다', '1자에서 40자 사이로 적어 주세요.')),
    );
    return;
  }

  const existingIndex = settings.staffRoles.findIndex((entry) => entry.roleId === role.id);

  if (existingIndex === -1 && settings.staffRoles.length >= MAX_ROLES) {
    await interaction.editReply(
      editPayload(errorPanel('더 넣을 수 없습니다', `직책은 ${MAX_ROLES}개까지 등록할 수 있습니다.`)),
    );
    return;
  }

  const entry = {
    roleId: role.id,
    title,
    stars: starCount,
    addedAt: existingIndex === -1 ? Date.now() : settings.staffRoles[existingIndex].addedAt,
  };

  if (existingIndex === -1) settings.staffRoles.push(entry);
  else settings.staffRoles[existingIndex] = entry;

  try {
    await writeSettings(interaction.client, settings);
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  await interaction.editReply(
    editPayload(
      successPanel(
        existingIndex === -1 ? '등록했습니다' : '고쳤습니다',
        `[${stars(starCount)}] ${title} - <@&${role.id}>`,
      ),
    ),
  );
}

function storageErrorPanel(error) {
  if (error instanceof StorageError) {
    return errorPanel('보관 채널을 쓸 수 없습니다', error.message);
  }
  log.error('직원 명단 처리 오류', error?.stack ?? error);
  return errorPanel('오류가 발생했습니다', '잠시 후 다시 시도해 주세요.');
}
