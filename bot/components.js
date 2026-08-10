import {
  ActionRowBuilder,
  ContainerBuilder,
  MediaGalleryBuilder,
  MediaGalleryItemBuilder,
  MessageFlags,
  SectionBuilder,
  SeparatorBuilder,
  SeparatorSpacingSize,
  TextDisplayBuilder,
  ThumbnailBuilder,
} from 'discord.js';

import { config } from './config.js';

/**
 * 이 봇의 모든 메시지는 Components V2 컨테이너로 만듭니다.
 * 클래식 임베드는 버튼을 안에 넣을 수 없고 항상 임베드 바깥 아래에 붙지만,
 * 컨테이너는 제목, 본문, 구분선, 이미지, 버튼, 꼬리말을 전부 한 상자 안에 담습니다.
 */

export function text(content) {
  return new TextDisplayBuilder().setContent(String(content));
}

/** 선이 있는 구분선 */
export function divider(large = false) {
  return new SeparatorBuilder()
    .setDivider(true)
    .setSpacing(large ? SeparatorSpacingSize.Large : SeparatorSpacingSize.Small);
}

/** 선 없이 간격만 띄우기 */
export function spacer(large = false) {
  return new SeparatorBuilder()
    .setDivider(false)
    .setSpacing(large ? SeparatorSpacingSize.Large : SeparatorSpacingSize.Small);
}

/**
 * 컨테이너 하나를 만듭니다.
 *
 * @param {object} options
 * @param {number} [options.color]        왼쪽 세로 강조선 색
 * @param {string} [options.title]        제목
 * @param {string} [options.description]  본문
 * @param {string} [options.thumbnail]    본문 오른쪽에 붙는 작은 이미지 URL
 * @param {Array<{name: string, value: string}>} [options.fields] 항목 목록
 * @param {string} [options.image]        본문 아래에 크게 들어가는 이미지 URL
 * @param {Array<import('discord.js').ButtonBuilder|import('discord.js').StringSelectMenuBuilder>} [options.buttons]
 *        컨테이너 안에 들어가는 버튼과 드롭다운
 * @param {string} [options.footer]       맨 아래 작은 글씨
 */
export function panel({
  color = config.colors.primary,
  title = null,
  description = null,
  thumbnail = null,
  fields = [],
  image = null,
  buttons = [],
  footer = null,
} = {}) {
  const container = new ContainerBuilder().setAccentColor(color);

  // 맨 위에 구분선이 먼저 나오지 않도록, 내용이 하나라도 들어간 뒤부터만 선을 긋습니다.
  let hasContent = false;
  const separate = () => {
    if (hasContent) container.addSeparatorComponents(divider());
  };

  const headParts = [];
  if (title) headParts.push(`## ${title}`);
  if (description) headParts.push(description);

  if (headParts.length > 0) {
    const head = headParts.join('\n');
    if (thumbnail) {
      // 썸네일을 본문 오른쪽에 붙이려면 섹션으로 감싸야 합니다.
      container.addSectionComponents(
        new SectionBuilder()
          .addTextDisplayComponents(text(head))
          .setThumbnailAccessory(new ThumbnailBuilder().setURL(thumbnail)),
      );
    } else {
      container.addTextDisplayComponents(text(head));
    }
    hasContent = true;
  }

  for (const field of fields) {
    if (!field) continue;
    separate();
    // 이름을 비우면 굵은 제목 없이 문단만 들어갑니다.
    container.addTextDisplayComponents(
      text(field.name ? `**${field.name}**\n${field.value}` : String(field.value)),
    );
    hasContent = true;
  }

  if (image) {
    separate();
    container.addMediaGalleryComponents(
      new MediaGalleryBuilder().addItems(new MediaGalleryItemBuilder().setURL(image)),
    );
    hasContent = true;
  }

  const rows = toActionRows(buttons);
  if (rows.length > 0) {
    separate();
    for (const row of rows) container.addActionRowComponents(row);
    hasContent = true;
  }

  // 꼬리말과 저작권 문구는 항상 맨 아래에 작은 글씨로 붙습니다.
  // -# 은 디스코드의 작은 글씨(subtext) 문법입니다.
  const footerLines = [];
  if (footer) footerLines.push(`-# ${footer}`);
  if (config.copyrightText) footerLines.push(`-# ${config.copyrightText}`);

  if (footerLines.length > 0) {
    separate();
    container.addTextDisplayComponents(text(footerLines.join('\n')));
    hasContent = true;
  }

  if (!hasContent) {
    // 컨테이너는 최소 한 개의 구성 요소가 있어야 합니다.
    container.addTextDisplayComponents(text('-# 표시할 내용이 없습니다.'));
  }

  return container;
}

/**
 * 버튼과 드롭다운을 액션 로우로 묶습니다.
 * 드롭다운은 한 줄에 하나만 들어갈 수 있고, 버튼은 한 줄에 다섯 개까지 들어갑니다.
 */
function toActionRows(components) {
  const rows = [];
  let current = null;

  for (const component of components) {
    if (!component) continue;

    if (isSelectMenu(component)) {
      current = null;
      rows.push(new ActionRowBuilder().addComponents(component));
      continue;
    }

    if (current === null || current.components.length >= 5) {
      current = new ActionRowBuilder();
      rows.push(current);
    }
    current.addComponents(component);
  }

  return rows;
}

function isSelectMenu(component) {
  const type = component?.data?.type;
  // 3: 문자열 선택, 5-8: 사용자/역할/멘션/채널 선택
  return type === 3 || (type >= 5 && type <= 8);
}

const V2 = MessageFlags.IsComponentsV2;

/** 컨테이너를 새 메시지로 보낼 때 쓰는 페이로드 */
export function payload(container, { ephemeral = false } = {}) {
  return {
    components: [container],
    flags: ephemeral ? V2 | MessageFlags.Ephemeral : V2,
  };
}

/**
 * 이미 보낸 메시지를 고칠 때 쓰는 페이로드.
 * 원래 메시지에 붙은 임시(ephemeral) 여부는 그대로 유지되므로 다시 넣지 않습니다.
 */
export function editPayload(container) {
  return { components: [container], flags: V2 };
}

// --- 자주 쓰는 색상별 단축 함수 ---

export function infoPanel(title, description, extra = {}) {
  return panel({ color: config.colors.primary, title, description, ...extra });
}

export function successPanel(title, description, extra = {}) {
  return panel({ color: config.colors.success, title, description, ...extra });
}

export function errorPanel(title, description, extra = {}) {
  return panel({ color: config.colors.danger, title, description, ...extra });
}

export function warningPanel(title, description, extra = {}) {
  return panel({ color: config.colors.warning, title, description, ...extra });
}

export function neutralPanel(title, description, extra = {}) {
  return panel({ color: config.colors.neutral, title, description, ...extra });
}
