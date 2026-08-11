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

import { WORK_FIELDS, config, getMissingOptionalIds, getSharedCategoryTypes, validateConfig } from './config.js';
import { log } from './log.js';
import { formatBusinessHours, formatKst, isBusinessHours } from './time.js';
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

import { handleRepairTermsCommand, handleTermsCommand } from './terms.js';
import {
  handleNoticeAddCommand,
  handleNoticeAutocomplete,
  handleNoticeRemoveCommand,
  handleTicketNoticeCommand,
} from './notice.js';
import { canUseCommand, deniedReason, hidesByDefault } from './permissions.js';
import { HELP_CHOICES, handleConfigCheckCommand, handleHelpCommand } from './help.js';
import {
  RECRUIT_CHOICES,
  RECRUIT_IDS,
  handleRecruitApply,
  handleRecruitCommand,
  handleRecruitSubmit,
  isRecruitCustomId,
} from './recruit.js';
import {
  PAYMENT_IDS,
  handlePaymentConfirm,
  handlePaymentFail,
  handlePaymentRequestCommand,
  handlePaymentSent,
  isPaymentCustomId,
} from './payments.js';
import { handleMemberJoin, prepareWelcomeImage } from './welcome.js';
import {
  handleInviteCodeCommand,
  handleInviteCreate,
  handleInviteDelete,
  handleInviteRankCommand,
  handleInviteRepairCommand,
  logInviteJoin,
  primeInvites,
  syncGuild,
} from './invites.js';
import { handleStaffListCommand, handleStaffSetupCommand, startStaffBoardRefresh } from './staff.js';
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
import {
  ASSIGN_IDS,
  checkOverdue,
  handleAdjustAccept,
  handleAdjustForm,
  handleAdjustReject,
  handleAdjustRejectForm,
  handleAdjustRequest,
  handleAssignAccept,
  handleAssignAcceptForm,
  handleAssignCommand,
  handleAssignCreate,
  handleAssignPick,
  handleRepairAutocomplete,
  handleRepairCommand,
  handleRepairCreate,
  handleRepairPick,
  handleAssignReject,
  handleAssignRejectForm,
  handleCancel,
  handleCancelForm,
  handleComplete,
  handleCompleteForm,
  handleExtend,
  handleFieldListCommand,
  handleFieldRemoveCommand,
  handleFieldSetupCommand,
  isAssignCustomId,
  refreshWarningBoard,
} from './assignments.js';
import {
  PAYROLL_IDS,
  handlePayCommand,
  handlePayDone,
  handlePayForm,
  handlePayStart,
  handlePayStatusCommand,
  isPayrollCustomId,
} from './payroll.js';

const MANAGE_GUILD = PermissionsBitField.Flags.ManageGuild;

/**
 * 목록에서 숨길 명령만 서버 관리 권한을 걸어 둡니다.
 * COMMAND_ROLES 로 역할을 정한 명령은 모두에게 보이고, 실제 판정은 봇이 합니다.
 */
function applyDefaultPermissions(commands) {
  for (const command of commands) {
    command.setDefaultMemberPermissions(hidesByDefault(command.name) ? MANAGE_GUILD : null);
  }
  return commands;
}

// 분야는 목록에서 고르게 합니다. config.js 의 WORK_FIELDS 를 고치면 목록도 바뀝니다.
const FIELD_CHOICES = WORK_FIELDS.map((field) => ({ name: field, value: field }));

const COMMANDS = applyDefaultPermissions([
  new SlashCommandBuilder()
    .setName('도움말')
    .setDescription('쓸 수 있는 명령을 봅니다.')
    .setContexts(InteractionContextType.Guild)
    .addStringOption((option) =>
      option
        .setName('분류')
        .setDescription('보고 싶은 분류 (비우면 전부)')
        .setRequired(false)
        .addChoices(...HELP_CHOICES),
    ),

  new SlashCommandBuilder()
    .setName('설정확인')
    .setDescription('아직 안 채운 설정과 그래서 안 되는 기능을 봅니다.')
    .setContexts(InteractionContextType.Guild),

  new SlashCommandBuilder()
    .setName('티켓패널')
    .setDescription('문의 패널을 다시 게시합니다.')
    .setContexts(InteractionContextType.Guild),

  new SlashCommandBuilder()
    .setName('초대코드')
    .setDescription('내 초대 코드를 만들고, 그 코드로 들어온 사람 수를 봅니다.')
    .setContexts(InteractionContextType.Guild),

  new SlashCommandBuilder()
    .setName('초대랭킹')
    .setDescription('초대로 들어온 사람이 많은 순서로 봅니다.')
    .setContexts(InteractionContextType.Guild)
    .addIntegerOption((option) =>
      option
        .setName('인원')
        .setDescription('보여 줄 인원 (기본 10명)')
        .setMinValue(1)
        .setMaxValue(25)
        .setRequired(false),
    ),

  new SlashCommandBuilder()
    .setName('초대복구')
    .setDescription('나갔다 다시 들어와 부풀려진 초대 수를 되돌립니다.')
    .setContexts(InteractionContextType.Guild)
    .addSubcommand((sub) =>
      sub.setName('자동').setDescription('초대 기록 채널을 다시 읽어 사람마다 한 번씩만 셉니다.'),
    )
    .addSubcommand((sub) =>
      sub
        .setName('수동')
        .setDescription('코드 하나의 수를 직접 정합니다.')
        .addStringOption((option) =>
          option.setName('코드').setDescription('초대 코드').setRequired(true).setMaxLength(30),
        )
        .addIntegerOption((option) =>
          option.setName('인원').setDescription('맞는 인원').setRequired(true).setMinValue(0),
        ),
    ),

  new SlashCommandBuilder()
    .setName('문의안내')
    .setDescription('문의 안내를 올립니다.')
    .setContexts(InteractionContextType.Guild)
    .addChannelOption((option) =>
      option.setName('채널').setDescription('올릴 채널 (비우면 이 채널)').setRequired(false),
    ),

  new SlashCommandBuilder()
    .setName('문의안내추가')
    .setDescription('문의 안내에 문단을 하나 더합니다.')
    .setContexts(InteractionContextType.Guild)
    .addStringOption((option) =>
      option
        .setName('내용')
        .setDescription('더할 문단. 줄을 바꾸려면 \\n 을 넣으세요.')
        .setRequired(true)
        .setMaxLength(900),
    ),

  new SlashCommandBuilder()
    .setName('문의안내삭제')
    .setDescription('더했던 문단을 뺍니다.')
    .setContexts(InteractionContextType.Guild)
    .addStringOption((option) =>
      option.setName('문단').setDescription('뺄 문단').setRequired(true).setAutocomplete(true),
    ),

  new SlashCommandBuilder()
    .setName('이용약관')
    .setDescription('이 채널에 이용약관을 올립니다.')
    .setContexts(InteractionContextType.Guild),

  new SlashCommandBuilder()
    .setName('수리약관')
    .setDescription('이 채널에 A/S 이용약관을 올립니다.')
    .setContexts(InteractionContextType.Guild),

  new SlashCommandBuilder()
    .setName('채용공고')
    .setDescription('고른 팀의 채용 공고를 이 채널에 올립니다.')
    .setContexts(InteractionContextType.Guild)
    .addStringOption((option) =>
      option.setName('팀').setDescription('모집할 팀').setRequired(true).addChoices(...RECRUIT_CHOICES),
    )
    .addIntegerOption((option) =>
      option.setName('인원').setDescription('모집 인원').setRequired(true).setMinValue(1).setMaxValue(99),
    )
    .addStringOption((option) =>
      option
        .setName('접수기간')
        .setDescription('예: 7일, 48시간, 2026-08-20 23:59')
        .setRequired(true)
        .setMaxLength(40),
    )
    .addBooleanOption((option) =>
      option.setName('모두멘션').setDescription('모두에게 알릴지 여부').setRequired(false),
    ),

  new SlashCommandBuilder()
    .setName('직원명단')
    .setDescription('이 채널에 직원 명단을 올립니다.')
    .setContexts(InteractionContextType.Guild),

  new SlashCommandBuilder()
    .setName('직원명단설정')
    .setDescription('직원 명단에 쓸 역할과 직책을 설정합니다.')
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
    .setContexts(InteractionContextType.Guild)
    .addStringOption((option) =>
      option.setName('제품').setDescription('보낼 제품').setRequired(true).setAutocomplete(true),
    )
    .addUserOption((option) =>
      option.setName('유저').setDescription('받을 사람').setRequired(true),
    ),

  new SlashCommandBuilder()
    .setName('분야설정')
    .setDescription('직원을 분야에 등록하고 관리합니다.')
    .setContexts(InteractionContextType.Guild)
    .addSubcommand((sub) =>
      sub
        .setName('등록')
        .setDescription('직원을 분야에 넣습니다. 같은 사람을 다시 넣으면 덮어씁니다.')
        .addUserOption((option) => option.setName('유저').setDescription('직원').setRequired(true))
        .addStringOption((option) =>
          option.setName('분야').setDescription('분야').setRequired(true).addChoices(...FIELD_CHOICES),
        )
        .addStringOption((option) =>
          option.setName('별명').setDescription('목록에 표시할 별명').setRequired(true).setMaxLength(30),
        ),
    )
    .addSubcommand((sub) =>
      sub
        .setName('삭제')
        .setDescription('직원을 분야에서 뺍니다.')
        .addUserOption((option) => option.setName('유저').setDescription('직원').setRequired(true))
        .addStringOption((option) =>
          option.setName('분야').setDescription('분야').setRequired(true).addChoices(...FIELD_CHOICES),
        ),
    )
    .addSubcommand((sub) => sub.setName('목록').setDescription('분야별 직원을 봅니다.')),

  new SlashCommandBuilder()
    .setName('배당')
    .setDescription('분야를 골라 업무를 배당합니다.')
    .setContexts(InteractionContextType.Guild)
    .addStringOption((option) =>
      option.setName('분야').setDescription('배당할 분야').setRequired(true).addChoices(...FIELD_CHOICES),
    ),

  new SlashCommandBuilder()
    .setName('수리')
    .setDescription('배당한 프로젝트의 수리를 맡깁니다.')
    .setContexts(InteractionContextType.Guild)
    .addStringOption((option) =>
      option
        .setName('프로젝트')
        .setDescription('배당한 프로젝트')
        .setRequired(true)
        .setAutocomplete(true),
    )
    .addStringOption((option) =>
      option.setName('분야').setDescription('맡길 분야').setRequired(true).addChoices(...FIELD_CHOICES),
    ),

  new SlashCommandBuilder()
    .setName('급여지급')
    .setDescription('직원에게 급여 안내를 보냅니다.')
    .setContexts(InteractionContextType.Guild)
    .addStringOption((option) =>
      option.setName('급여').setDescription('예: 100,000원').setRequired(true).setMaxLength(40),
    )
    .addUserOption((option) => option.setName('직원').setDescription('받을 직원').setRequired(true)),

  new SlashCommandBuilder()
    .setName('송금요청')
    .setDescription('계좌를 DM 으로 보내고 입금을 확인합니다.')
    .setContexts(InteractionContextType.Guild)
    .addUserOption((option) => option.setName('유저').setDescription('보낼 사람').setRequired(true))
    .addStringOption((option) =>
      option.setName('얼마').setDescription('예: 100,000원').setRequired(true).setMaxLength(40),
    )
    .addStringOption((option) =>
      option
        .setName('기한')
        .setDescription('예: 3일, 48시간, 2026-08-10 18:00')
        .setRequired(true)
        .setMaxLength(40),
    )
    .addStringOption((option) =>
      option.setName('내용').setDescription('무엇에 대한 송금인지').setRequired(false).setMaxLength(200),
    ),

  new SlashCommandBuilder()
    .setName('지급상태')
    .setDescription('지금까지 지급된 급여를 봅니다.')
    .setContexts(InteractionContextType.Guild)
    .addUserOption((option) =>
      option.setName('직원').setDescription('볼 직원 (비우면 본인)').setRequired(false),
    ),
]).map((command) => command.toJSON());

const client = new Client({
  intents: [
    GatewayIntentBits.Guilds,
    // 직원 명단에서 역할별 인원을 세는 데 필요합니다.
    GatewayIntentBits.GuildMembers,
    GatewayIntentBits.GuildMessages,
    GatewayIntentBits.MessageContent,
    // /초대코드 로 만든 초대가 언제 생기고 사라지는지 따라가는 데 필요합니다.
    GatewayIntentBits.GuildInvites,
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

  // 기간이 지난 배당을 주기적으로 확인합니다.
  const runCheck = () => {
    checkOverdue(client).catch((error) => log.error('기간 확인 실패', error?.message ?? error));
  };
  runCheck();
  setInterval(runCheck, 10 * 60_000).unref();

  await refreshWarningBoard(client).catch(() => {});

  // 직원 명단 채널을 주기적으로 갱신합니다.
  startStaffBoardRefresh(client);

  // 초대 사용 횟수를 미리 읽어 둡니다. 이게 있어야 누구 초대로 들어왔는지 알 수 있습니다.
  await primeInvites(client).catch((error) =>
    log.warn('초대 목록을 읽지 못했습니다.', error?.message ?? error),
  );

  // 환영 그림을 미리 받아 둡니다. 주소가 만료돼도 계속 쓸 수 있도록 파일로 들고 있습니다.
  await prepareWelcomeImage(client).catch((error) =>
    log.warn('환영 그림 준비 실패', error?.message ?? error),
  );

  log.info(`지금 한국 시간: ${formatKst(Date.now())} / 문의 시간: ${formatBusinessHours()} (${isBusinessHours() ? '지금 문의 시간 안' : '지금 문의 시간 밖'})`);
  log.info('봇 준비가 끝났습니다.');
});

client.on(Events.GuildCreate, async (guild) => {
  log.info(`새 서버에 참여했습니다: ${guild.name} (${guild.id})`);
  await registerCommands();
  await syncGuild(guild).catch(() => {});
});

// --- 서버에 들어온 사람 맞이하기 ---

client.on(Events.GuildMemberAdd, async (member) => {
  // 초대 확인이 먼저입니다. 늦으면 다른 사람이 들어와 횟수가 섞입니다.
  try {
    await logInviteJoin(member);
  } catch (error) {
    log.error('초대 기록 처리 중 오류', error?.stack ?? error);
  }

  try {
    await handleMemberJoin(member);
  } catch (error) {
    log.error('환영 메시지 처리 중 오류', error?.stack ?? error);
  }
});

// --- 초대 목록 따라가기 ---

client.on(Events.InviteCreate, (invite) => handleInviteCreate(invite));
client.on(Events.InviteDelete, (invite) => handleInviteDelete(invite));

// --- 상호작용 처리 ---

client.on(Events.InteractionCreate, async (interaction) => {
  try {
    if (interaction.isAutocomplete()) {
      if (interaction.commandName === '수리') await handleRepairAutocomplete(interaction);
      else if (interaction.commandName === '문의안내삭제') await handleNoticeAutocomplete(interaction);
      else await handleProductAutocomplete(interaction);
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
      } else if (interaction.customId === ASSIGN_IDS.pick) {
        await handleAssignPick(interaction);
      } else if (idIs(interaction.customId, ASSIGN_IDS.repairPick)) {
        await handleRepairPick(interaction);
      }
      return;
    }

    if (interaction.isModalSubmit()) {
      await handleModal(interaction);
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
  if (!canUseCommand(interaction.member, interaction.commandName)) {
    await interaction.reply(
      payload(errorPanel('권한이 없습니다', deniedReason(interaction.commandName)), { ephemeral: true }),
    );
    return;
  }

  switch (interaction.commandName) {
    case '도움말':
      await handleHelpCommand(interaction);
      return;

    case '설정확인':
      await handleConfigCheckCommand(interaction);
      return;

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

    case '초대코드':
      await handleInviteCodeCommand(interaction);
      return;

    case '초대랭킹':
      await handleInviteRankCommand(interaction);
      return;

    case '초대복구':
      await handleInviteRepairCommand(interaction);
      return;

    case '문의안내':
      await handleTicketNoticeCommand(interaction);
      return;

    case '문의안내추가':
      await handleNoticeAddCommand(interaction);
      return;

    case '문의안내삭제':
      await handleNoticeRemoveCommand(interaction);
      return;

    case '이용약관':
      await handleTermsCommand(interaction);
      return;

    case '수리약관':
      await handleRepairTermsCommand(interaction);
      return;

    case '채용공고':
      await handleRecruitCommand(interaction);
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

    case '분야설정': {
      const sub = interaction.options.getSubcommand();
      if (sub === '등록') await handleFieldSetupCommand(interaction);
      else if (sub === '삭제') await handleFieldRemoveCommand(interaction);
      else await handleFieldListCommand(interaction);
      return;
    }

    case '배당':
      await handleAssignCommand(interaction);
      return;

    case '수리':
      await handleRepairCommand(interaction);
      return;

    case '급여지급':
      await handlePayCommand(interaction);
      return;

    case '송금요청':
      await handlePaymentRequestCommand(interaction);
      return;

    case '지급상태':
      await handlePayStatusCommand(interaction);
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

  if (isAssignCustomId(customId)) {
    if (idIs(customId, ASSIGN_IDS.accept)) await handleAssignAccept(interaction);
    else if (idIs(customId, ASSIGN_IDS.reject)) await handleAssignReject(interaction);
    else if (idIs(customId, ASSIGN_IDS.adjustAccept)) await handleAdjustAccept(interaction);
    else if (idIs(customId, ASSIGN_IDS.adjustReject)) await handleAdjustReject(interaction);
    else if (idIs(customId, ASSIGN_IDS.adjust)) await handleAdjustRequest(interaction);
    else if (idIs(customId, ASSIGN_IDS.extend)) await handleExtend(interaction);
    else if (idIs(customId, ASSIGN_IDS.complete)) await handleComplete(interaction);
    else if (idIs(customId, ASSIGN_IDS.cancel)) await handleCancel(interaction);
    return;
  }

  if (isPayrollCustomId(customId)) {
    if (idIs(customId, PAYROLL_IDS.start)) await handlePayStart(interaction);
    else if (idIs(customId, PAYROLL_IDS.done)) await handlePayDone(interaction);
    return;
  }

  if (isRecruitCustomId(customId)) {
    if (idIs(customId, RECRUIT_IDS.apply)) await handleRecruitApply(interaction);
    return;
  }

  if (isPaymentCustomId(customId)) {
    if (idIs(customId, PAYMENT_IDS.sent)) await handlePaymentSent(interaction);
    else if (idIs(customId, PAYMENT_IDS.ok)) await handlePaymentConfirm(interaction);
    else if (idIs(customId, PAYMENT_IDS.no)) await handlePaymentFail(interaction);
  }
}

async function handleModal(interaction) {
  const { customId } = interaction;

  if (idIs(customId, REVIEW_IDS.form)) {
    await handleReviewSubmit(interaction);
    return;
  }

  if (isRecruitCustomId(customId) && idIs(customId, RECRUIT_IDS.form)) {
    await handleRecruitSubmit(interaction);
    return;
  }

  if (isAssignCustomId(customId)) {
    if (idIs(customId, ASSIGN_IDS.newForm)) await handleAssignCreate(interaction);
    else if (idIs(customId, ASSIGN_IDS.repairForm)) await handleRepairCreate(interaction);
    else if (idIs(customId, ASSIGN_IDS.acceptForm)) await handleAssignAcceptForm(interaction);
    else if (idIs(customId, ASSIGN_IDS.rejectForm)) await handleAssignRejectForm(interaction);
    else if (idIs(customId, ASSIGN_IDS.adjustRejectForm)) await handleAdjustRejectForm(interaction);
    else if (idIs(customId, ASSIGN_IDS.adjustForm)) await handleAdjustForm(interaction);
    else if (idIs(customId, ASSIGN_IDS.completeForm)) await handleCompleteForm(interaction);
    else if (idIs(customId, ASSIGN_IDS.cancelForm)) await handleCancelForm(interaction);
    return;
  }

  if (isPayrollCustomId(customId) && idIs(customId, PAYROLL_IDS.form)) {
    await handlePayForm(interaction);
  }
}

/**
 * 상호작용 ID 가 그 종류인지 확인합니다.
 * 콜론 경계까지 봐야 assign:adjust 와 assign:adjustok 이 섞이지 않습니다.
 */
function idIs(customId, prefix) {
  return customId === prefix || customId.startsWith(`${prefix}:`);
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
