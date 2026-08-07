import {
  Client,
  Events,
  GatewayIntentBits,
  InteractionContextType,
  Partials,
  PermissionsBitField,
  REST,
  Routes,
  SlashCommandBuilder,
} from 'discord.js';

import { config, getMissingOptionalIds, getSharedCategoryTypes, validateConfig } from './config.js';
import { log } from './log.js';
import { editPayload, errorPanel, neutralPanel, payload, successPanel } from './components.js';

import {
  TICKET_IDS,
  deployTicketPanel,
  handleTicketCloseCancel,
  handleTicketCloseConfirm,
  handleTicketCloseRequest,
  handleTicketCreate,
  isTicketCustomId,
} from './tickets.js';

import { handleTermsCommand } from './terms.js';
import { handleStaffListCommand, handleStaffSetupCommand } from './staff.js';
import { handlePartnershipCommand } from './partnership.js';
import { REVIEW_IDS, handleReviewPick, handleReviewSubmit } from './reviews.js';
import {
  PRODUCT_IDS,
  handleProductAutocomplete,
  handleProductGet,
  handleProductSendCommand,
  handleProductSetupCommand,
  isProductCustomId,
} from './products.js';

const MANAGE_GUILD = PermissionsBitField.Flags.ManageGuild;

const COMMANDS = [
  new SlashCommandBuilder()
    .setName('티켓패널')
    .setDescription('문의 패널을 다시 게시합니다.')
    .setDefaultMemberPermissions(MANAGE_GUILD)
    .setContexts(InteractionContextType.Guild),

  new SlashCommandBuilder()
    .setName('이용약관')
    .setDescription('이 채널에 이용약관을 올립니다.')
    .setDefaultMemberPermissions(MANAGE_GUILD)
    .setContexts(InteractionContextType.Guild),

  new SlashCommandBuilder()
    .setName('직원명단')
    .setDescription('이 채널에 직원 명단을 올립니다.')
    .setDefaultMemberPermissions(MANAGE_GUILD)
    .setContexts(InteractionContextType.Guild),

  new SlashCommandBuilder()
    .setName('직원명단설정')
    .setDescription('직원 명단에 쓸 역할과 직책을 설정합니다.')
    .setDefaultMemberPermissions(MANAGE_GUILD)
    .setContexts(InteractionContextType.Guild)
    .addSubcommand((sub) =>
      sub
        .setName('추가')
        .setDescription('역할을 직책으로 등록합니다. 같은 역할을 다시 넣으면 덮어씁니다.')
        .addRoleOption((option) =>
          option.setName('역할').setDescription('직책에 해당하는 역할').setRequired(true),
        )
        .addStringOption((option) =>
          option
            .setName('직책')
            .setDescription('명단에 표시할 직책 이름')
            .setRequired(true)
            .setMaxLength(40),
        )
        .addIntegerOption((option) =>
          option
            .setName('별')
            .setDescription('별 개수')
            .setRequired(true)
            .setMinValue(1)
            .setMaxValue(5),
        ),
    )
    .addSubcommand((sub) =>
      sub
        .setName('삭제')
        .setDescription('등록한 직책을 뺍니다.')
        .addRoleOption((option) =>
          option.setName('역할').setDescription('뺄 역할').setRequired(true),
        ),
    )
    .addSubcommand((sub) => sub.setName('목록').setDescription('등록된 직책을 봅니다.')),

  new SlashCommandBuilder()
    .setName('파트너쉽')
    .setDescription('이 채널에 파트너 안내를 올립니다.')
    .setDefaultMemberPermissions(MANAGE_GUILD)
    .setContexts(InteractionContextType.Guild)
    .addStringOption((option) =>
      option.setName('서버링크').setDescription('들어갈 서버 주소').setRequired(true),
    )
    .addStringOption((option) =>
      option.setName('제목').setDescription('안내 제목').setRequired(true).setMaxLength(100),
    )
    .addStringOption((option) =>
      option.setName('소개글').setDescription('소개 내용').setRequired(true).setMaxLength(1500),
    )
    .addBooleanOption((option) =>
      option.setName('모두멘션').setDescription('모두에게 알릴지 여부').setRequired(false),
    )
    .addAttachmentOption((option) =>
      option.setName('사진').setDescription('안내에 넣을 사진').setRequired(false),
    ),

  new SlashCommandBuilder()
    .setName('제품설정')
    .setDescription('보낼 제품을 등록하고 관리합니다.')
    .setDefaultMemberPermissions(MANAGE_GUILD)
    .setContexts(InteractionContextType.Guild)
    .addSubcommand((sub) =>
      sub
        .setName('등록')
        .setDescription('zip 파일을 제품으로 등록합니다.')
        .addStringOption((option) =>
          option.setName('이름').setDescription('제품 이름').setRequired(true).setMaxLength(60),
        )
        .addAttachmentOption((option) =>
          option.setName('파일').setDescription('zip 파일').setRequired(true),
        )
        .addStringOption((option) =>
          option.setName('설명').setDescription('제품 설명').setRequired(false).setMaxLength(500),
        ),
    )
    .addSubcommand((sub) =>
      sub
        .setName('삭제')
        .setDescription('등록한 제품을 지웁니다.')
        .addStringOption((option) =>
          option.setName('제품').setDescription('지울 제품').setRequired(true).setAutocomplete(true),
        ),
    )
    .addSubcommand((sub) => sub.setName('목록').setDescription('등록된 제품을 봅니다.')),

  new SlashCommandBuilder()
    .setName('제품전송')
    .setDescription('등록된 제품을 특정 유저에게 보냅니다.')
    .setDefaultMemberPermissions(MANAGE_GUILD)
    .setContexts(InteractionContextType.Guild)
    .addStringOption((option) =>
      option.setName('제품').setDescription('보낼 제품').setRequired(true).setAutocomplete(true),
    )
    .addUserOption((option) =>
      option.setName('유저').setDescription('받을 사람').setRequired(true),
    ),
].map((command) => command.toJSON());

const client = new Client({
  intents: [
    GatewayIntentBits.Guilds,
    // 직원 명단에서 역할별 인원을 세는 데 필요합니다.
    GatewayIntentBits.GuildMembers,
    GatewayIntentBits.GuildMessages,
    GatewayIntentBits.MessageContent,
    // 후기와 제품 받기 버튼이 DM 에서 눌립니다.
    GatewayIntentBits.DirectMessages,
  ],
  // DM 으로 온 상호작용을 받으려면 채널 partial 이 필요합니다.
  partials: [Partials.Channel],
});

// --- 슬래시 명령 등록 ---

async function registerCommands() {
  const rest = new REST({ version: '10' }).setToken(config.token);

  for (const guild of client.guilds.cache.values()) {
    try {
      await rest.put(Routes.applicationGuildCommands(client.user.id, guild.id), { body: COMMANDS });
      log.info(`슬래시 명령을 등록했습니다: ${guild.name} (${guild.id})`);
    } catch (error) {
      log.error(`슬래시 명령 등록 실패: ${guild.name} (${guild.id})`, error?.message ?? error);
    }
  }
}

// --- 준비 완료 ---

client.once(Events.ClientReady, async () => {
  log.info(`로그인 완료: ${client.user.tag} (${client.user.id})`);
  log.info(`참여 중인 서버: ${client.guilds.cache.size}개`);

  await registerCommands();

  for (const type of getSharedCategoryTypes()) {
    log.warn(
      `${type.label} 카테고리 ID 를 아직 넣지 않아 통합 문의 카테고리를 같이 씁니다. ` +
        `.env 의 TICKET_CATEGORY_${type.value.toUpperCase()} 에 카테고리 ID 를 넣어 주세요.`,
    );
  }

  for (const [name, label] of getMissingOptionalIds()) {
    log.warn(`${label}(${name})이 설정되지 않았습니다. 관련 기능이 동작하지 않습니다.`);
  }

  // 봇이 실행될 때마다 문의 패널을 자동으로 게시합니다.
  await deployTicketPanel(client);

  log.info('봇 준비가 끝났습니다.');
});

client.on(Events.GuildCreate, async (guild) => {
  log.info(`새 서버에 참여했습니다: ${guild.name} (${guild.id})`);
  await registerCommands();
});

// --- 상호작용 처리 ---

client.on(Events.InteractionCreate, async (interaction) => {
  try {
    if (interaction.isAutocomplete()) {
      await handleProductAutocomplete(interaction);
      return;
    }

    if (interaction.isChatInputCommand()) {
      await handleCommand(interaction);
      return;
    }

    if (interaction.isStringSelectMenu()) {
      if (interaction.customId === TICKET_IDS.select) {
        await handleTicketCreate(interaction);
      } else if (interaction.customId.startsWith(REVIEW_IDS.pick)) {
        await handleReviewPick(interaction);
      }
      return;
    }

    if (interaction.isModalSubmit()) {
      if (interaction.customId.startsWith(REVIEW_IDS.form)) {
        await handleReviewSubmit(interaction);
      }
      return;
    }

    if (interaction.isButton()) {
      await handleButton(interaction);
    }
  } catch (error) {
    log.error(
      `상호작용 처리 중 오류 (${interaction.customId ?? interaction.commandName ?? '알 수 없음'})`,
      error?.stack ?? error,
    );
    await replyWithError(interaction);
  }
});

async function handleCommand(interaction) {
  switch (interaction.commandName) {
    case '티켓패널': {
      await replyWorking(interaction, '문의 패널을 다시 게시하고 있습니다.');
      const sent = await deployTicketPanel(client);
      await interaction.editReply(
        editPayload(
          sent
            ? successPanel('완료', `문의 패널을 <#${config.ticketPanelChannelId}> 채널에 다시 게시했습니다.`)
            : errorPanel('실패', '문의 패널을 게시하지 못했습니다. 채널 ID와 봇 권한을 확인해 주세요.'),
        ),
      );
      return;
    }

    case '이용약관':
      await handleTermsCommand(interaction);
      return;

    case '직원명단':
      await handleStaffListCommand(interaction);
      return;

    case '직원명단설정':
      await handleStaffSetupCommand(interaction);
      return;

    case '파트너쉽':
      await handlePartnershipCommand(interaction);
      return;

    case '제품설정':
      await handleProductSetupCommand(interaction);
      return;

    case '제품전송':
      await handleProductSendCommand(interaction);
      return;

    default:
      await interaction.reply(
        payload(errorPanel('알 수 없는 명령', '지원하지 않는 명령입니다.'), { ephemeral: true }),
      );
  }
}

async function handleButton(interaction) {
  const { customId } = interaction;

  if (isTicketCustomId(customId)) {
    switch (customId) {
      case TICKET_IDS.close:
        await handleTicketCloseRequest(interaction);
        return;
      case TICKET_IDS.closeConfirm:
        await handleTicketCloseConfirm(interaction);
        return;
      case TICKET_IDS.closeCancel:
        await handleTicketCloseCancel(interaction);
        return;
      default:
        return;
    }
  }

  if (isProductCustomId(customId) && customId.startsWith(PRODUCT_IDS.get)) {
    await handleProductGet(interaction);
    return;
  }
}

/** 처리에 시간이 걸리는 명령을 위해 먼저 컨테이너로 응답해 둡니다. */
async function replyWorking(interaction, description) {
  await interaction.reply(
    payload(neutralPanel('처리 중입니다', description), { ephemeral: true }),
  );
}

async function replyWithError(interaction) {
  if (!interaction.isRepliable?.()) return;

  const container = errorPanel(
    '오류가 발생했습니다',
    '요청을 처리하지 못했습니다. 잠시 후 다시 시도하거나 스태프에게 문의해 주세요.',
  );

  try {
    if (interaction.deferred || interaction.replied) {
      await interaction.followUp(payload(container, { ephemeral: true }));
    } else {
      await interaction.reply(payload(container, { ephemeral: true }));
    }
  } catch (error) {
    log.debug('오류 응답 전송 실패', error?.message ?? error);
  }
}

// --- 시작 ---

client.on(Events.Error, (error) => log.error('디스코드 클라이언트 오류', error?.message ?? error));
client.on(Events.Warn, (message) => log.warn(message));

process.on('unhandledRejection', (reason) => {
  log.error('처리되지 않은 오류', reason?.stack ?? reason);
});

async function shutdown(signal) {
  log.info(`${signal} 신호를 받아 종료합니다.`);
  try {
    await client.destroy();
  } catch (error) {
    log.error('종료 처리 중 오류', error?.message ?? error);
  }
  process.exit(0);
}

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));

async function main() {
  const problems = validateConfig();
  if (problems.length > 0) {
    for (const problem of problems) log.error(problem);
    log.error('설정을 확인한 뒤 다시 실행해 주세요. .env.example 파일을 참고하세요.');
    process.exit(1);
  }

  await client.login(config.token);
}

main().catch((error) => {
  log.error('봇을 시작하지 못했습니다.', error?.stack ?? error);
  process.exit(1);
});
