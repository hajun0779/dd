import { config } from './config.js';
import { log } from './log.js';
import { formatKst } from './time.js';
import { editPayload, errorPanel, neutralPanel, panel, payload } from './components.js';
import { MARKERS, StorageError, addRecord, getRecord, listRecords, updateRecord } from './storage.js';

/**
 * /초대코드 로 만든 초대와, 그 초대로 들어온 사람을 기록합니다.
 *
 * 디스코드는 "이 사람이 이 초대로 들어왔다" 를 알려 주지 않습니다.
 * 그래서 서버의 초대 목록과 사용 횟수를 들고 있다가, 사람이 들어온 순간
 * 다시 읽어서 횟수가 늘어난 초대를 찾는 방식으로 알아냅니다.
 *
 * 초대 목록을 읽으려면 봇에게 서버 관리(Manage Server) 권한이 있어야 합니다.
 * 초대를 만들려면 초대 링크 만들기(Create Invite) 권한이 있어야 합니다.
 */

// 서버 ID -> Map<초대 코드, { uses, inviterId }>
const cache = new Map();
// 서버 ID -> 맞춤 주소(vanity) 사용 횟수
const vanityCache = new Map();
// 서버 ID -> Map<초대 코드, { uses, inviterId, at }>  (방금 사라진 초대)
const recentlyDeleted = new Map();
// 서버 ID -> 처리 중인 작업. 동시에 여러 명이 들어와도 순서대로 처리합니다.
const queues = new Map();
// 권한이 없다는 경고를 서버마다 한 번만 남깁니다.
const warned = new Set();

// 한도가 차서 사라진 초대를 이 시간까지는 후보로 봅니다.
const DELETED_KEEP_MS = 60_000;

function toMap(invites) {
  const map = new Map();
  for (const invite of invites.values()) {
    map.set(invite.code, { uses: invite.uses ?? 0, inviterId: invite.inviter?.id ?? null });
  }
  return map;
}

async function fetchInvites(guild) {
  try {
    return toMap(await guild.invites.fetch());
  } catch (error) {
    if (!warned.has(guild.id)) {
      warned.add(guild.id);
      log.warn(
        `${guild.name} 의 초대 목록을 읽지 못했습니다. 봇에게 서버 관리 권한을 주면 초대한 사람을 표시할 수 있습니다.`,
        error?.message ?? error,
      );
    }
    return null;
  }
}

async function fetchVanityUses(guild) {
  if (!guild.vanityURLCode) return null;
  try {
    const data = await guild.fetchVanityData();
    return data?.uses ?? null;
  } catch {
    return null;
  }
}

/** 한 서버의 초대 목록을 읽어 둡니다. */
export async function syncGuild(guild) {
  const map = await fetchInvites(guild);
  if (map) cache.set(guild.id, map);

  const vanity = await fetchVanityUses(guild);
  if (vanity !== null) vanityCache.set(guild.id, vanity);

  return map;
}

/** 봇이 켜질 때 모든 서버의 초대 목록을 읽어 둡니다. */
export async function primeInvites(client) {
  for (const guild of client.guilds.cache.values()) {
    const map = await syncGuild(guild);
    if (map) log.info(`초대 목록을 읽었습니다: ${guild.name} (${map.size}개)`);
  }
}

export function handleInviteCreate(invite) {
  const guildId = invite.guild?.id;
  if (!guildId) return;

  const map = cache.get(guildId);
  if (!map) return;

  map.set(invite.code, { uses: invite.uses ?? 0, inviterId: invite.inviter?.id ?? null });
}

export function handleInviteDelete(invite) {
  const guildId = invite.guild?.id;
  if (!guildId) return;

  const map = cache.get(guildId);
  const known = map?.get(invite.code);
  map?.delete(invite.code);

  // 한도가 차서 사라진 초대일 수 있습니다. 잠깐 들고 있다가 후보로 씁니다.
  if (!known) return;
  if (!recentlyDeleted.has(guildId)) recentlyDeleted.set(guildId, new Map());
  recentlyDeleted.get(guildId).set(invite.code, { ...known, at: Date.now() });
}

function takeRecentlyDeleted(guildId) {
  const map = recentlyDeleted.get(guildId);
  if (!map) return [];

  const now = Date.now();
  const alive = [];
  for (const [code, info] of map) {
    if (now - info.at > DELETED_KEEP_MS) map.delete(code);
    else alive.push({ code, uses: info.uses, inviterId: info.inviterId });
  }
  return alive;
}

/** 서버마다 한 번에 하나씩만 처리합니다. 동시에 들어오면 섞여서 잘못 세게 됩니다. */
function runQueued(guildId, task) {
  const previous = queues.get(guildId) ?? Promise.resolve();
  const next = previous.then(task, task);
  queues.set(
    guildId,
    next.then(
      () => {},
      () => {},
    ),
  );
  return next;
}

/**
 * 방금 들어온 사람이 어떤 초대로 왔는지 알아냅니다.
 *
 * 돌려주는 값의 kind
 *   invite   초대를 찾음 (code, inviterId, uses)
 *   vanity   서버 맞춤 주소로 들어옴
 *   bot      봇이 추가됨 (초대 링크를 쓰지 않습니다)
 *   unknown  알아내지 못함
 */
export function resolveInviter(member) {
  const guild = member.guild;
  if (!guild) return Promise.resolve({ kind: 'unknown' });

  return runQueued(guild.id, async () => {
    const before = cache.get(guild.id);
    const beforeVanity = vanityCache.get(guild.id);

    const after = await fetchInvites(guild);
    const afterVanity = await fetchVanityUses(guild);

    if (after) cache.set(guild.id, after);
    if (afterVanity !== null) vanityCache.set(guild.id, afterVanity);

    // 봇은 초대 링크가 아니라 OAuth 로 추가되므로 횟수가 늘지 않습니다.
    if (member.user?.bot) return { kind: 'bot' };

    if (!after) return { kind: 'unknown', reason: 'permission' };
    if (!before) return { kind: 'unknown', reason: 'baseline' };

    // 1) 사용 횟수가 늘어난 초대
    const grown = [];
    for (const [code, info] of after) {
      const previous = before.get(code);
      if (!previous) {
        // 우리가 모르는 사이에 만들어진 초대. 이미 쓰였다면 후보입니다.
        if (info.uses > 0) grown.push({ code, ...info });
        continue;
      }
      if (info.uses > previous.uses) grown.push({ code, ...info });
    }

    if (grown.length === 1) return { kind: 'invite', ...grown[0] };
    if (grown.length > 1) return { kind: 'unknown', reason: 'multiple' };

    // 2) 한도가 차서 사라진 초대
    const gone = new Map();
    for (const [code, info] of before) {
      if (!after.has(code)) gone.set(code, { code, ...info });
    }
    for (const info of takeRecentlyDeleted(guild.id)) {
      if (!after.has(info.code)) gone.set(info.code, info);
    }

    if (gone.size === 1) {
      const [only] = gone.values();
      return { kind: 'invite', ...only, uses: (only.uses ?? 0) + 1, closed: true };
    }

    // 3) 서버 맞춤 주소
    if (beforeVanity !== undefined && afterVanity !== null && afterVanity > beforeVanity) {
      return { kind: 'vanity', code: guild.vanityURLCode, uses: afterVanity };
    }

    return { kind: 'unknown' };
  });
}

// ---------------------------------------------------------------------------
//  /초대코드
// ---------------------------------------------------------------------------

function storageErrorPanel(error) {
  if (error instanceof StorageError) {
    return errorPanel('보관 채널을 쓸 수 없습니다', error.message);
  }
  log.error('초대 코드 처리 오류', error?.stack ?? error);
  return errorPanel('오류가 발생했습니다', '잠시 후 다시 시도해 주세요.');
}

/** 초대를 만들 채널을 고릅니다. */
async function resolveInviteChannel(interaction) {
  const candidates = [config.inviteChannelId, config.welcomeChannelId];

  for (const id of candidates) {
    if (!id) continue;
    const channel = await interaction.client.channels.fetch(id).catch(() => null);
    if (channel?.guildId === interaction.guildId && typeof channel.createInvite === 'function') {
      return channel;
    }
  }

  // 설정된 채널이 없으면 명령을 쓴 채널에 만듭니다.
  return typeof interaction.channel?.createInvite === 'function' ? interaction.channel : null;
}

/** 이 사람이 이 서버에서 만들어 둔 초대 기록을 모두 가져옵니다. */
async function listOwnerRecords(client, guildId, ownerId) {
  const records = await listRecords(client, MARKERS.inviteCode);
  return records.filter((record) => record.guildId === guildId && record.ownerId === ownerId);
}

function totalJoins(records) {
  return records.reduce((sum, record) => sum + (record.count ?? 0), 0);
}

export async function handleInviteCodeCommand(interaction) {
  await interaction.reply(
    payload(neutralPanel('잠시만 기다려 주세요', '초대 코드를 확인하고 있습니다.'), {
      ephemeral: true,
    }),
  );

  const client = interaction.client;
  const guild = interaction.guild;

  let mine;
  try {
    mine = await listOwnerRecords(client, guild.id, interaction.user.id);
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  // 서버에 아직 살아 있는 초대인지 확인합니다.
  const living = await fetchInvites(guild);
  if (!living) {
    await interaction.editReply(
      editPayload(
        errorPanel(
          '초대 목록을 읽지 못했습니다',
          '봇에게 서버 관리 권한을 준 뒤 다시 시도해 주세요.',
        ),
      ),
    );
    return;
  }

  let active = mine.find((record) => living.has(record.code)) ?? null;

  if (!active) {
    const channel = await resolveInviteChannel(interaction);
    if (!channel) {
      await interaction.editReply(
        editPayload(
          errorPanel(
            '초대를 만들 채널이 없습니다',
            '.env 의 INVITE_CHANNEL_ID 에 채널을 넣거나, 초대를 만들 수 있는 채널에서 다시 써 주세요.',
          ),
        ),
      );
      return;
    }

    let invite;
    try {
      invite = await channel.createInvite({
        maxAge: 0,
        maxUses: 0,
        unique: true,
        reason: `${interaction.user.tag} 초대 코드`,
      });
    } catch (error) {
      log.warn('초대를 만들지 못했습니다.', error?.message ?? error);
      await interaction.editReply(
        editPayload(
          errorPanel(
            '초대를 만들지 못했습니다',
            `봇에게 ${channel} 에서 초대 링크 만들기 권한이 있는지 확인해 주세요.`,
          ),
        ),
      );
      return;
    }

    try {
      active = await addRecord(client, MARKERS.inviteCode, {
        id: invite.code,
        code: invite.code,
        ownerId: interaction.user.id,
        guildId: guild.id,
        channelId: channel.id,
        url: invite.url,
        createdAt: Date.now(),
        count: 0,
      });
    } catch (error) {
      await interaction.editReply(editPayload(storageErrorPanel(error)));
      return;
    }

    mine = [...mine, active];
    // 방금 만든 초대도 세어 두어야 다음 사람이 들어올 때 헷갈리지 않습니다.
    cache.get(guild.id)?.set(invite.code, { uses: 0, inviterId: client.user.id });
    log.info(`초대 코드 발급: ${invite.code} (${interaction.user.tag})`);
  }

  const url = active.url ?? `https://discord.gg/${active.code}`;

  await interaction.editReply(
    editPayload(
      panel({
        color: config.colors.primary,
        title: '내 초대 코드',
        description: url,
        fields: [
          { name: '코드', value: active.code },
          { name: '이 코드로 들어온 사람', value: `${active.count ?? 0}명` },
          ...(mine.length > 1 ? [{ name: '전체 기록', value: `${totalJoins(mine)}명` }] : []),
        ],
        footer: `${config.brandName} 초대`,
      }),
    ),
  );
}

// ---------------------------------------------------------------------------
//  /초대랭킹
// ---------------------------------------------------------------------------

const RANK_DEFAULT = 10;
const RANK_MAX = 25;

/**
 * 초대 기록을 사람별로 합쳐서 많은 순서로 늘어놓습니다.
 * 한 사람이 코드를 여러 번 발급받았어도 전부 더해서 셉니다.
 */
export function buildRanking(records, guildId = null) {
  const totals = new Map();

  for (const record of records) {
    if (!record?.ownerId) continue;
    if (guildId && record.guildId !== guildId) continue;

    const row = totals.get(record.ownerId) ?? { ownerId: record.ownerId, count: 0, codes: 0 };
    row.count += record.count ?? 0;
    row.codes += 1;
    totals.set(record.ownerId, row);
  }

  const rows = [...totals.values()]
    .filter((row) => row.count > 0)
    .sort((a, b) => b.count - a.count || a.ownerId.localeCompare(b.ownerId));

  // 같은 인원이면 같은 순위입니다.
  let rank = 0;
  let previous = null;
  rows.forEach((row, index) => {
    if (row.count !== previous) {
      rank = index + 1;
      previous = row.count;
    }
    row.rank = rank;
  });

  return rows;
}

export function formatRanking(rows, limit = RANK_DEFAULT) {
  if (rows.length === 0) return '아직 초대로 들어온 사람이 없습니다.';
  return rows
    .slice(0, limit)
    .map((row) => `${row.rank}위  <@${row.ownerId}>  ${row.count}명`)
    .join('\n');
}

export async function handleInviteRankCommand(interaction) {
  // 랭킹은 다 같이 보는 것이라 채널에 그대로 남깁니다.
  await interaction.reply(payload(neutralPanel('잠시만 기다려 주세요', '초대 기록을 세고 있습니다.')));

  let records;
  try {
    records = await listRecords(interaction.client, MARKERS.inviteCode);
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  const limit = Math.min(interaction.options?.getInteger?.('인원') ?? RANK_DEFAULT, RANK_MAX);
  const rows = buildRanking(records, interaction.guildId);
  const total = rows.reduce((sum, row) => sum + row.count, 0);

  const fields = [];

  if (rows.length > 0) {
    fields.push({ name: '전체', value: `${rows.length}명이 ${total}명을 초대했습니다` });

    // 내가 순위표 밖에 있으면 내 자리만 따로 보여 줍니다.
    const mine = rows.find((row) => row.ownerId === interaction.user.id);
    if (mine && mine.rank > limit) {
      fields.push({ name: '내 순위', value: `${mine.rank}위  <@${mine.ownerId}>  ${mine.count}명` });
    }
  }

  const container = panel({
    color: config.colors.primary,
    title: '초대 랭킹',
    description: formatRanking(rows, limit),
    fields,
    footer: `${config.brandName} 초대`,
  });

  const message = editPayload(container);
  // 순위표에 이름이 오른 사람들에게 알림이 울리지 않게 막습니다.
  message.allowedMentions = { parse: [] };

  await interaction.editReply(message);
}

// ---------------------------------------------------------------------------
//  들어왔을 때 기록 남기기
// ---------------------------------------------------------------------------

async function sendDm(client, userId, message) {
  try {
    const user = await client.users.fetch(userId);
    await user.send(message);
    return true;
  } catch (error) {
    log.debug(`초대 기록 DM 실패 (${userId})`, error?.message ?? error);
    return false;
  }
}

/**
 * 방금 들어온 사람이 /초대코드 로 만든 초대를 썼는지 보고,
 * 썼다면 그 코드를 만든 사람에게 기록을 남깁니다.
 */
export async function logInviteJoin(member) {
  const client = member.client;
  const result = await resolveInviter(member);

  if (result.kind !== 'invite' || !result.code) return null;
  if (!config.storageChannelId) return null;

  let record;
  try {
    record = await getRecord(client, MARKERS.inviteCode, result.code);
  } catch (error) {
    log.debug('초대 기록을 읽지 못했습니다.', error?.message ?? error);
    return null;
  }

  // 봇이 만든 코드가 아니면 기록하지 않습니다.
  if (!record) return null;

  const count = (record.count ?? 0) + 1;
  try {
    await updateRecord(client, MARKERS.inviteCode, result.code, { count });
  } catch (error) {
    log.debug('초대 기록을 고치지 못했습니다.', error?.message ?? error);
  }

  const container = panel({
    color: config.colors.success,
    title: '초대 기록',
    description: `<@${member.id}> 님이 회원님의 초대로 들어왔습니다.`,
    fields: [
      { name: '코드', value: result.code },
      { name: '이 코드로 들어온 사람', value: `${count}명` },
      { name: '들어온 시간', value: formatKst(Date.now()) },
    ],
    footer: `${config.brandName} 초대`,
  });

  const dm = payload(container);
  dm.allowedMentions = { parse: [] };
  await sendDm(client, record.ownerId, dm);

  if (config.inviteLogChannelId) {
    const channel = await client.channels.fetch(config.inviteLogChannelId).catch(() => null);
    if (channel?.isTextBased?.()) {
      const post = payload(
        panel({
          color: config.colors.neutral,
          title: '초대 기록',
          description: `<@${member.id}> 님이 <@${record.ownerId}> 님의 초대로 들어왔습니다.`,
          fields: [
            { name: '코드', value: result.code },
            { name: '이 코드로 들어온 사람', value: `${count}명` },
            { name: '들어온 시간', value: formatKst(Date.now()) },
          ],
          footer: `${config.brandName} 초대`,
        }),
      );
      post.allowedMentions = { parse: [] };
      await channel.send(post).catch((error) => {
        log.warn('초대 기록을 올리지 못했습니다.', error?.message ?? error);
      });
    }
  }

  log.info(`초대 기록: ${member.user?.tag ?? member.id} <- ${result.code} (${count}명)`);
  return { ...record, count, code: result.code };
}

/** 환영 메시지에 넣을 한 줄을 만듭니다. */
export function formatInviter(result) {
  if (!result) return '알 수 없음';

  switch (result.kind) {
    case 'invite': {
      const who = result.inviterId ? `<@${result.inviterId}>` : '알 수 없음';
      return result.code ? `${who} (코드 ${result.code})` : who;
    }
    case 'vanity':
      return result.code ? `서버 맞춤 주소 (${result.code})` : '서버 맞춤 주소';
    case 'bot':
      return '봇 추가';
    default:
      return '알 수 없음';
  }
}

/** 시험용입니다. 들고 있던 초대 정보를 모두 비웁니다. */
export function resetInviteCache() {
  cache.clear();
  vanityCache.clear();
  recentlyDeleted.clear();
  queues.clear();
  warned.clear();
}
