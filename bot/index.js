import {
  Client,
  Events,
  GatewayIntentBits,
  InteractionContextType,
  MessageFlags,
  PermissionsBitField,
  REST,
  Routes,
  SlashCommandBuilder,
} from 'discord.js';

import { config, validateConfig } from './config.js';
import { store } from './store.js';
import { log } from './log.js';
import { errorEmbed, ephemeral, successEmbed } from './embeds.js';

import {
  VERIFY_IDS,
  deployVerifyPanel,
  handleVerifyCheck,
  handleVerifyModalSubmit,
  handleVerifyReissue,
  isVerificationCustomId,
  openVerifyModal,
} from './verification.js';

import {
  TICKET_IDS,
  deployTicketPanel,
  handleTicketCloseCancel,
  handleTicketCloseConfirm,
  handleTicketCloseRequest,
  handleTicketCreate,
  isTicketCustomId,
} from './tickets.js';

const COMMANDS = [
  new SlashCommandBuilder()
    .setName('인증')
    .setDescription('로블록스 계정을 서버 계정과 연동합니다.')
    .setContexts(InteractionContextType.Guild),
  new SlashCommandBuilder()
    .setName('인증패널')
    .setDescription('인증 패널을 다시 게시합니다.')
    .setDefaultMemberPermissions(PermissionsBitField.Flags.ManageGuild)
    .setContexts(InteractionContextType.Guild),
  new SlashCommandBuilder()
    .setName('티켓패널')
    .setDescription('티켓 패널을 다시 게시합니다.')
    .setDefaultMemberPermissions(PermissionsBitField.Flags.ManageGuild)
    .setContexts(InteractionContextType.Guild),
].map((command) => command.toJSON());

const client = new Client({
  intents: [
    GatewayIntentBits.Guilds,
    GatewayIntentBits.GuildMembers,
    GatewayIntentBits.GuildMessages,
    GatewayIntentBits.MessageContent,
  ],
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

  const pruned = store.prunePending();
  if (pruned > 0) log.info(`만료된 인증 대기 ${pruned}건을 정리했습니다.`);

  await registerCommands();

  // 봇이 실행될 때마다 패널을 자동으로 게시합니다.
  await deployVerifyPanel(client);
  await deployTicketPanel(client);

  log.info('봇 준비가 끝났습니다.');
});

client.on(Events.GuildCreate, async (guild) => {
  log.info(`새 서버에 참여했습니다: ${guild.name} (${guild.id})`);
  await registerCommands();
});

// 티켓 채널이 사람에 의해 직접 삭제되면 저장소에서도 지웁니다.
client.on(Events.ChannelDelete, (channel) => {
  if (store.getTicket(channel.id)) {
    store.removeTicket(channel.id);
    log.info(`삭제된 티켓 채널을 저장소에서 정리했습니다: ${channel.id}`);
  }
});

// --- 상호작용 처리 ---

client.on(Events.InteractionCreate, async (interaction) => {
  try {
    if (interaction.isChatInputCommand()) {
      await handleCommand(interaction);
      return;
    }

    if (interaction.isStringSelectMenu()) {
      if (interaction.customId === TICKET_IDS.select) {
        await handleTicketCreate(interaction);
      }
      return;
    }

    if (interaction.isModalSubmit()) {
      if (interaction.customId === VERIFY_IDS.modal) {
        await handleVerifyModalSubmit(interaction);
      }
      return;
    }

    if (interaction.isButton()) {
      await handleButton(interaction);
    }
  } catch (error) {
    log.error(`상호작용 처리 중 오류 (${interaction.customId ?? interaction.commandName ?? '알 수 없음'})`, error?.stack ?? error);
    await replyWithError(interaction);
  }
});

async function handleCommand(interaction) {
  switch (interaction.commandName) {
    case '인증':
      await openVerifyModal(interaction);
      return;

    case '인증패널': {
      await interaction.deferReply({ flags: MessageFlags.Ephemeral });
      const sent = await deployVerifyPanel(client);
      await interaction.editReply({
        embeds: [
          sent
            ? successEmbed('완료', `인증 패널을 <#${config.verifyPanelChannelId}> 채널에 다시 게시했습니다.`)
            : errorEmbed('실패', '인증 패널을 게시하지 못했습니다. 채널 ID와 봇 권한을 확인해 주세요.'),
        ],
      });
      return;
    }

    case '티켓패널': {
      await interaction.deferReply({ flags: MessageFlags.Ephemeral });
      const sent = await deployTicketPanel(client);
      await interaction.editReply({
        embeds: [
          sent
            ? successEmbed('완료', `티켓 패널을 <#${config.ticketPanelChannelId}> 채널에 다시 게시했습니다.`)
            : errorEmbed('실패', '티켓 패널을 게시하지 못했습니다. 채널 ID와 봇 권한을 확인해 주세요.'),
        ],
      });
      return;
    }

    default:
      await interaction.reply(ephemeral(errorEmbed('알 수 없는 명령', '지원하지 않는 명령입니다.')));
  }
}

async function handleButton(interaction) {
  const { customId } = interaction;

  if (isVerificationCustomId(customId)) {
    switch (customId) {
      case VERIFY_IDS.start:
        await openVerifyModal(interaction);
        return;
      case VERIFY_IDS.check:
        await handleVerifyCheck(interaction);
        return;
      case VERIFY_IDS.reissue:
        await handleVerifyReissue(interaction);
        return;
      default:
        return;
    }
  }

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
}

async function replyWithError(interaction) {
  if (!interaction.isRepliable?.()) return;

  const payload = {
    embeds: [
      errorEmbed(
        '오류가 발생했습니다',
        '요청을 처리하지 못했습니다. 잠시 후 다시 시도하거나 스태프에게 문의해 주세요.',
      ),
    ],
  };

  try {
    if (interaction.deferred || interaction.replied) {
      await interaction.followUp({ ...payload, flags: MessageFlags.Ephemeral });
    } else {
      await interaction.reply({ ...payload, flags: MessageFlags.Ephemeral });
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
    await store.save();
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

  await store.load();

  // 30분마다 만료된 인증 대기 항목을 정리합니다.
  setInterval(() => store.prunePending(), 30 * 60 * 1000).unref();

  await client.login(config.token);
}

main().catch((error) => {
  log.error('봇을 시작하지 못했습니다.', error?.stack ?? error);
  process.exit(1);
});
