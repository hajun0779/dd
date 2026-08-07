import { AttachmentBuilder, ButtonBuilder, ButtonStyle, PermissionsBitField } from 'discord.js';

import { config } from './config.js';
import { log } from './log.js';
import { formatKst } from './time.js';
import { editPayload, errorPanel, neutralPanel, panel, payload, successPanel } from './components.js';
import { sendReviewRequest } from './reviews.js';
import {
  addProduct,
  getProduct,
  listProducts,
  makeProductId,
  removeProduct,
  StorageError,
} from './storage.js';

export const PRODUCT_IDS = {
  get: 'product:get',
};

const MAX_ZIP_BYTES = 24 * 1024 * 1024;
const ZIP_TYPES = new Set([
  'application/zip',
  'application/x-zip-compressed',
  'application/octet-stream',
  'multipart/x-zip',
]);

function formatSize(bytes) {
  const value = Number(bytes) || 0;
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KB`;
  return `${(value / (1024 * 1024)).toFixed(2)} MB`;
}

function isAllowed(member) {
  if (!member) return false;
  if (member.permissions?.has(PermissionsBitField.Flags.Administrator)) return true;
  if (!config.productRoleId) return false;
  return Boolean(member.roles?.cache?.has(config.productRoleId));
}

function deniedPanel() {
  return errorPanel(
    '권한이 없습니다',
    config.productRoleId
      ? `<@&${config.productRoleId}> 역할을 가진 사람만 쓸 수 있습니다.`
      : '제품 담당 역할이 설정되지 않았습니다. .env 의 PRODUCT_APPROVAL_ROLE_ID 를 채워 주세요.',
  );
}

function storageErrorPanel(error) {
  if (error instanceof StorageError) {
    return errorPanel('보관 채널을 쓸 수 없습니다', error.message);
  }
  log.error('제품 처리 오류', error?.stack ?? error);
  return errorPanel('오류가 발생했습니다', '잠시 후 다시 시도해 주세요.');
}

// --- 제품 설정 ---

export async function handleProductSetupCommand(interaction) {
  const sub = interaction.options.getSubcommand();

  await interaction.reply(
    payload(neutralPanel('잠시만 기다려 주세요', '제품 정보를 확인하고 있습니다.'), { ephemeral: true }),
  );

  if (!isAllowed(interaction.member)) {
    await interaction.editReply(editPayload(deniedPanel()));
    return;
  }

  if (sub === '목록') {
    let products;
    try {
      products = await listProducts(interaction.client);
    } catch (error) {
      await interaction.editReply(editPayload(storageErrorPanel(error)));
      return;
    }

    await interaction.editReply(
      editPayload(
        panel({
          color: config.colors.neutral,
          title: '등록된 제품',
          description:
            products.length === 0
              ? '아직 등록된 제품이 없습니다.'
              : products
                  .map((product) => `**${product.name}** (${formatSize(product.fileSize)})`)
                  .join('\n'),
          footer: `${config.brandName} 제품`,
        }),
      ),
    );
    return;
  }

  if (sub === '삭제') {
    const id = interaction.options.getString('제품');
    let removed = false;
    try {
      removed = await removeProduct(interaction.client, id);
    } catch (error) {
      await interaction.editReply(editPayload(storageErrorPanel(error)));
      return;
    }

    await interaction.editReply(
      editPayload(
        removed
          ? successPanel('지웠습니다', '제품을 목록에서 뺐습니다.')
          : errorPanel('찾지 못했습니다', '이미 지워졌거나 없는 제품입니다.'),
      ),
    );
    return;
  }

  // 등록
  const name = interaction.options.getString('이름').trim();
  const description = (interaction.options.getString('설명') ?? '').trim();
  const file = interaction.options.getAttachment('파일');

  if (name.length === 0 || name.length > 60) {
    await interaction.editReply(
      editPayload(errorPanel('이름이 올바르지 않습니다', '1자에서 60자 사이로 적어 주세요.')),
    );
    return;
  }

  const fileName = String(file.name ?? '');
  const looksLikeZip = fileName.toLowerCase().endsWith('.zip');
  const typeOk = ZIP_TYPES.has(String(file.contentType ?? '').split(';')[0]);

  if (!looksLikeZip || !typeOk) {
    await interaction.editReply(
      editPayload(errorPanel('zip 파일만 등록할 수 있습니다', `올린 파일: ${fileName || '알 수 없음'}`)),
    );
    return;
  }

  if (file.size > MAX_ZIP_BYTES) {
    await interaction.editReply(
      editPayload(
        errorPanel('파일이 너무 큽니다', `${formatSize(MAX_ZIP_BYTES)} 이하로 올려 주세요.`),
      ),
    );
    return;
  }

  let buffer;
  try {
    const response = await fetch(file.url, { signal: AbortSignal.timeout(60_000) });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    buffer = Buffer.from(await response.arrayBuffer());
  } catch (error) {
    log.error('제품 파일을 받아오지 못했습니다.', error?.message ?? error);
    await interaction.editReply(
      editPayload(errorPanel('파일을 불러오지 못했습니다', '잠시 후 다시 시도해 주세요.')),
    );
    return;
  }

  let product;
  try {
    product = await addProduct(interaction.client, {
      id: makeProductId(name),
      name,
      description,
      buffer,
      fileName,
      author: interaction.user.id,
    });
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  await interaction.editReply(
    editPayload(
      successPanel('등록했습니다', `**${product.name}**`, {
        fields: [
          { name: '파일', value: `${product.fileName} (${formatSize(product.fileSize)})` },
          ...(description ? [{ name: '설명', value: description }] : []),
        ],
        footer: `${config.brandName} 제품`,
      }),
    ),
  );
}

// --- 제품 전송 ---

export async function handleProductSendCommand(interaction) {
  await interaction.reply(
    payload(neutralPanel('잠시만 기다려 주세요', '제품을 보내고 있습니다.'), { ephemeral: true }),
  );

  if (!isAllowed(interaction.member)) {
    await interaction.editReply(editPayload(deniedPanel()));
    return;
  }

  const id = interaction.options.getString('제품');
  const target = interaction.options.getUser('유저');

  let product;
  try {
    product = await getProduct(interaction.client, id);
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  if (!product) {
    await interaction.editReply(
      editPayload(errorPanel('찾지 못했습니다', '등록되지 않은 제품입니다.')),
    );
    return;
  }

  const container = panel({
    color: config.colors.success,
    title: '제품이 도착했습니다',
    description: `**${product.name}**${product.description ? `\n\n${product.description}` : ''}`,
    fields: [
      { name: '파일', value: `${product.fileName} (${formatSize(product.fileSize)})` },
      { name: '보낸 시간', value: formatKst(Date.now()) },
    ],
    buttons: [
      new ButtonBuilder()
        .setCustomId(`${PRODUCT_IDS.get}:${product.id}`)
        .setLabel('제품 받기')
        .setStyle(ButtonStyle.Success),
    ],
    footer: `${config.brandName} 제품`,
  });

  try {
    const user = await interaction.client.users.fetch(target.id);
    await user.send(payload(container));
  } catch (error) {
    log.warn(`제품을 보내지 못했습니다 (${target.id}).`, error?.message ?? error);
    await interaction.editReply(
      editPayload(
        errorPanel(
          '보내지 못했습니다',
          `${target} 님이 DM 을 닫아 두었을 수 있습니다. 확인 후 다시 시도해 주세요.`,
        ),
      ),
    );
    return;
  }

  await interaction.editReply(
    editPayload(successPanel('보냈습니다', `${target} 님에게 **${product.name}** 을 보냈습니다.`)),
  );

  log.info(`제품 전송: ${product.name} -> ${target.tag ?? target.id} (${interaction.user.tag})`);
}

// --- 제품 받기 ---

export async function handleProductGet(interaction) {
  const id = interaction.customId.slice(`${PRODUCT_IDS.get}:`.length);

  await interaction.reply(
    payload(neutralPanel('잠시만 기다려 주세요', '다운로드 주소를 확인하고 있습니다.'), {
      ephemeral: true,
    }),
  );

  let product;
  try {
    // 다운로드 주소는 시간이 지나면 만료되므로 누를 때마다 새로 받아옵니다.
    product = await getProduct(interaction.client, id);
  } catch (error) {
    await interaction.editReply(editPayload(storageErrorPanel(error)));
    return;
  }

  if (!product?.fileUrl) {
    await interaction.editReply(
      editPayload(errorPanel('받을 수 없습니다', '제품이 더 이상 남아 있지 않습니다. 담당자에게 문의해 주세요.')),
    );
    return;
  }

  const container = panel({
    color: config.colors.success,
    title: product.name,
    description: '아래 버튼을 누르면 다운로드가 시작됩니다.',
    fields: [
      { name: '파일', value: `${product.fileName} (${formatSize(product.fileSize)})` },
      { name: '참고', value: '다운로드 주소는 시간이 지나면 만료됩니다. 만료되면 이 버튼을 다시 눌러 주세요.' },
    ],
    buttons: [
      new ButtonBuilder().setLabel('다운로드').setStyle(ButtonStyle.Link).setURL(product.fileUrl),
    ],
    footer: `${config.brandName} 제품`,
  });

  await interaction.editReply(editPayload(container));

  // 받은 뒤에 후기를 요청합니다.
  await sendReviewRequest(interaction.client, interaction.user.id, {
    kind: 'product',
    ref: product.id,
    subject: product.name,
  });
}

// --- 자동 완성 ---

export async function handleProductAutocomplete(interaction) {
  const focused = String(interaction.options.getFocused() ?? '').toLowerCase();

  let products = [];
  try {
    products = await listProducts(interaction.client);
  } catch {
    products = [];
  }

  const matches = products
    .filter((product) => product.name.toLowerCase().includes(focused))
    .slice(0, 25)
    .map((product) => ({ name: product.name.slice(0, 100), value: product.id }));

  await interaction.respond(matches).catch(() => {});
}

export function isProductCustomId(customId) {
  return customId.startsWith('product:');
}
