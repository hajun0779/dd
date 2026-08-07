import { config } from '../config.js';
import { log } from '../util/log.js';
import { formatKst, formatKstTime, formatDuration } from '../util/time.js';

const PLACEHOLDER_START = '\u0000B';
const PLACEHOLDER_END = '\u0000';

// --- 기본 도우미 ---

export function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, (char) => {
    switch (char) {
      case '&': return '&amp;';
      case '<': return '&lt;';
      case '>': return '&gt;';
      case '"': return '&quot;';
      default: return '&#39;';
    }
  });
}

function formatBytes(bytes) {
  const value = Number(bytes);
  if (!Number.isFinite(value) || value < 0) return '알 수 없음';
  if (value < 1024) return `${value} B`;
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KB`;
  return `${(value / (1024 * 1024)).toFixed(2)} MB`;
}

function colorToHex(color) {
  const value = Number(color);
  if (!Number.isFinite(value) || value <= 0) return '#4f5660';
  return `#${value.toString(16).padStart(6, '0')}`;
}

// --- 첨부 파일을 HTML 안에 직접 포함시키기 ---

/**
 * 디스코드 첨부파일 링크는 일정 시간이 지나면 만료됩니다.
 * 기록을 나중에 열어도 이미지와 영상이 보이도록 파일을 HTML 안에 직접 넣습니다.
 */
class MediaInliner {
  constructor({ perFileMaxBytes, totalMaxBytes }) {
    this.perFileMaxBytes = perFileMaxBytes;
    this.totalMaxBytes = totalMaxBytes;
    this.used = 0;
    this.cache = new Map();
    this.skipped = 0;
    this.failed = 0;
  }

  get remaining() {
    return Math.max(0, this.totalMaxBytes - this.used);
  }

  /** 성공하면 data URI 를, 실패하면 null 을 반환합니다. */
  async inline(url, { declaredSize = null, declaredType = null, maxBytes = null } = {}) {
    if (!url) return null;
    if (this.cache.has(url)) return this.cache.get(url);

    const limit = Math.min(maxBytes ?? this.perFileMaxBytes, this.perFileMaxBytes);

    if (declaredSize !== null && declaredSize > limit) {
      this.skipped += 1;
      this.cache.set(url, null);
      return null;
    }

    if (this.remaining <= 0) {
      this.skipped += 1;
      this.cache.set(url, null);
      return null;
    }

    try {
      const response = await fetch(url, { signal: AbortSignal.timeout(20_000) });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);

      const buffer = Buffer.from(await response.arrayBuffer());
      if (buffer.byteLength > limit) {
        this.skipped += 1;
        this.cache.set(url, null);
        return null;
      }

      const contentType =
        declaredType || response.headers.get('content-type')?.split(';')[0] || 'application/octet-stream';
      const base64 = buffer.toString('base64');

      if (base64.length > this.remaining) {
        this.skipped += 1;
        this.cache.set(url, null);
        return null;
      }

      this.used += base64.length;
      const dataUri = `data:${contentType};base64,${base64}`;
      this.cache.set(url, dataUri);
      return dataUri;
    } catch (error) {
      log.debug(`첨부파일을 내려받지 못했습니다: ${url}`, error?.message ?? error);
      this.failed += 1;
      this.cache.set(url, null);
      return null;
    }
  }
}

// --- 메시지 본문 렌더링 ---

function buildMentionContext(guild, messages) {
  const users = new Map();
  const roles = new Map();
  const channels = new Map();

  for (const [id, role] of guild.roles.cache) roles.set(id, role.name);
  for (const [id, channel] of guild.channels.cache) channels.set(id, channel.name);

  for (const message of messages) {
    if (message.author) {
      users.set(message.author.id, message.member?.displayName ?? message.author.username);
    }
    for (const [id, user] of message.mentions?.users ?? []) {
      if (!users.has(id)) users.set(id, user.username);
    }
    for (const [id, role] of message.mentions?.roles ?? []) {
      if (!roles.has(id)) roles.set(id, role.name);
    }
    for (const [id, channel] of message.mentions?.channels ?? []) {
      if (!channels.has(id)) channels.set(id, channel.name ?? id);
    }
  }

  return { users, roles, channels };
}

/**
 * 디스코드 메시지 본문을 HTML 로 변환합니다.
 * 코드블록과 링크는 자리표시자로 먼저 빼두어 서식 처리에 망가지지 않게 합니다.
 */
function renderContent(raw, ctx, collectedLinks) {
  if (raw === null || raw === undefined || String(raw).length === 0) return '';

  const parts = [];
  // 자리표시자로 쓰는 문자가 원본에 있으면 지웁니다.
  let text = String(raw).replace(/\u0000/g, '');
  if (text.length === 0) return '';

  // 1. 코드블록과 인라인 코드를 보호합니다.
  text = text.replace(/```(?:([A-Za-z0-9+#._-]*)\r?\n)?([\s\S]*?)```/g, (_match, lang, code) => {
    const index = parts.push({ kind: 'codeblock', lang: lang ?? '', code: code ?? '' }) - 1;
    return `${PLACEHOLDER_START}${index}${PLACEHOLDER_END}`;
  });
  text = text.replace(/``([^`]+)``|`([^`\n]+)`/g, (_match, a, b) => {
    const index = parts.push({ kind: 'code', code: a ?? b ?? '' }) - 1;
    return `${PLACEHOLDER_START}${index}${PLACEHOLDER_END}`;
  });

  // 2. HTML 이스케이프
  text = escapeHtml(text);

  // 3. 링크를 보호합니다. (서식 처리로 URL 이 깨지지 않도록)
  text = text.replace(/https?:\/\/[^\s<]+/g, (rawUrl) => {
    let url = rawUrl;
    let trailing = '';
    const match = url.match(/[)\]}.,!?]+$/);
    if (match) {
      trailing = match[0];
      url = url.slice(0, url.length - trailing.length);
    }
    if (url.length === 0) return rawUrl;
    if (collectedLinks) collectedLinks.add(url);
    const index = parts.push({ kind: 'link', url }) - 1;
    return `${PLACEHOLDER_START}${index}${PLACEHOLDER_END}${trailing}`;
  });

  // 4. 마크다운 서식
  text = text.replace(/\|\|([\s\S]+?)\|\|/g, '<span class="spoiler">$1</span>');
  text = text.replace(/\*\*\*([\s\S]+?)\*\*\*/g, '<strong><em>$1</em></strong>');
  text = text.replace(/\*\*([\s\S]+?)\*\*/g, '<strong>$1</strong>');
  text = text.replace(/__([\s\S]+?)__/g, '<u>$1</u>');
  text = text.replace(/~~([\s\S]+?)~~/g, '<s>$1</s>');
  text = text.replace(/(^|[^*\w])\*([^*\n]+)\*/g, '$1<em>$2</em>');
  text = text.replace(/(^|[^_\w])_([^_\n]+)_/g, '$1<em>$2</em>');

  // 5. 멘션, 커스텀 이모지, 타임스탬프
  text = text.replace(/&lt;@!?(\d+)&gt;/g, (_m, id) => {
    const name = ctx.users.get(id) ?? '알 수 없는 사용자';
    return `<span class="mention">@${escapeHtml(name)}</span>`;
  });
  text = text.replace(/&lt;@&amp;(\d+)&gt;/g, (_m, id) => {
    const name = ctx.roles.get(id) ?? '알 수 없는 역할';
    return `<span class="mention">@${escapeHtml(name)}</span>`;
  });
  text = text.replace(/&lt;#(\d+)&gt;/g, (_m, id) => {
    const name = ctx.channels.get(id) ?? '알 수 없는 채널';
    return `<span class="mention">#${escapeHtml(name)}</span>`;
  });
  text = text.replace(/&lt;(a?):([A-Za-z0-9_]+):(\d+)&gt;/g, (_m, animated, name, id) => {
    const extension = animated === 'a' ? 'gif' : 'png';
    return `<img class="inline-emoji" src="https://cdn.discordapp.com/emojis/${id}.${extension}" alt="${escapeHtml(name)}" title="${escapeHtml(name)}">`;
  });
  text = text.replace(/&lt;t:(-?\d+)(?::([tTdDfFR]))?&gt;/g, (_m, seconds) => {
    const date = new Date(Number(seconds) * 1000);
    return `<span class="mention">${escapeHtml(formatKst(date))}</span>`;
  });
  text = text.replace(/@(everyone|here)\b/g, '<span class="mention">@$1</span>');

  // 6. 인용문과 줄바꿈
  const lines = text.split('\n');
  const rendered = [];
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    const quoted = line.match(/^&gt;\s?(.*)$/);
    if (quoted) {
      rendered.push(`<div class="quote">${quoted[1].length > 0 ? quoted[1] : '&nbsp;'}</div>`);
      continue;
    }
    const nextIsQuote = /^&gt;\s?/.test(lines[index + 1] ?? '');
    const isLast = index === lines.length - 1;
    rendered.push(line + (!isLast && !nextIsQuote ? '<br>' : ''));
  }
  text = rendered.join('');

  // 7. 보호해 둔 조각을 되돌립니다.
  text = text.replace(new RegExp(`${PLACEHOLDER_START}(\\d+)${PLACEHOLDER_END}`, 'g'), (_m, rawIndex) => {
    const part = parts[Number(rawIndex)];
    if (!part) return '';
    if (part.kind === 'codeblock') {
      const lang = part.lang ? ` data-lang="${escapeHtml(part.lang)}"` : '';
      return `<pre class="codeblock"${lang}><code>${escapeHtml(part.code.replace(/\n$/, ''))}</code></pre>`;
    }
    if (part.kind === 'code') {
      return `<code class="inline-code">${escapeHtml(part.code)}</code>`;
    }
    return `<a class="link" href="${part.url}" target="_blank" rel="noopener noreferrer">${part.url}</a>`;
  });

  return text;
}

// --- 첨부파일 / 임베드 렌더링 ---

async function renderAttachment(attachment, inliner, collected) {
  const contentType = attachment.contentType ?? '';
  const name = escapeHtml(attachment.name ?? '파일');
  const url = escapeHtml(attachment.url ?? '');
  const size = formatBytes(attachment.size);

  collected.attachments.push({
    name: attachment.name ?? '파일',
    url: attachment.url ?? '',
    size: attachment.size ?? 0,
    contentType: contentType || '알 수 없음',
  });

  const meta = `<div class="file-meta">${name} · ${size}${
    url ? ` · <a class="link" href="${url}" target="_blank" rel="noopener noreferrer">원본 링크</a>` : ''
  }</div>`;

  if (contentType.startsWith('image/')) {
    const inlined = await inliner.inline(attachment.url, {
      declaredSize: attachment.size,
      declaredType: contentType,
    });
    const src = inlined ?? url;
    return `<div class="attachment"><a href="${src}" target="_blank" rel="noopener noreferrer"><img class="media" src="${src}" alt="${name}" loading="lazy"></a>${meta}${
      inlined ? '' : '<div class="file-note">파일을 기록에 포함하지 못했습니다. 원본 링크는 시간이 지나면 만료될 수 있습니다.</div>'
    }</div>`;
  }

  if (contentType.startsWith('video/')) {
    const inlined = await inliner.inline(attachment.url, {
      declaredSize: attachment.size,
      declaredType: contentType,
    });
    const src = inlined ?? url;
    return `<div class="attachment"><video class="media" controls preload="metadata" src="${src}"></video>${meta}${
      inlined ? '' : '<div class="file-note">파일을 기록에 포함하지 못했습니다. 원본 링크는 시간이 지나면 만료될 수 있습니다.</div>'
    }</div>`;
  }

  if (contentType.startsWith('audio/')) {
    const inlined = await inliner.inline(attachment.url, {
      declaredSize: attachment.size,
      declaredType: contentType,
    });
    const src = inlined ?? url;
    return `<div class="attachment"><audio class="audio" controls preload="metadata" src="${src}"></audio>${meta}</div>`;
  }

  return `<div class="attachment file-card">${meta}</div>`;
}

function renderEmbed(embed) {
  const rows = [];
  const color = colorToHex(embed.color);

  if (embed.author?.name) {
    const name = escapeHtml(embed.author.name);
    rows.push(
      `<div class="embed-author">${
        embed.author.url ? `<a class="link" href="${escapeHtml(embed.author.url)}" target="_blank" rel="noopener noreferrer">${name}</a>` : name
      }</div>`,
    );
  }

  if (embed.title) {
    const title = escapeHtml(embed.title);
    rows.push(
      `<div class="embed-title">${
        embed.url ? `<a class="link" href="${escapeHtml(embed.url)}" target="_blank" rel="noopener noreferrer">${title}</a>` : title
      }</div>`,
    );
  }

  if (embed.description) {
    rows.push(`<div class="embed-description">${escapeHtml(embed.description).replace(/\n/g, '<br>')}</div>`);
  }

  if (Array.isArray(embed.fields) && embed.fields.length > 0) {
    const fields = embed.fields
      .map(
        (field) =>
          `<div class="embed-field${field.inline ? ' inline' : ''}"><div class="embed-field-name">${escapeHtml(
            field.name,
          )}</div><div class="embed-field-value">${escapeHtml(field.value).replace(/\n/g, '<br>')}</div></div>`,
      )
      .join('');
    rows.push(`<div class="embed-fields">${fields}</div>`);
  }

  if (embed.image?.url) {
    rows.push(
      `<div class="embed-image"><img class="media" src="${escapeHtml(embed.image.url)}" alt="" loading="lazy"></div>`,
    );
  }

  if (embed.thumbnail?.url) {
    rows.push(
      `<div class="embed-thumbnail"><img src="${escapeHtml(embed.thumbnail.url)}" alt="" loading="lazy"></div>`,
    );
  }

  if (embed.footer?.text) {
    rows.push(`<div class="embed-footer">${escapeHtml(embed.footer.text)}</div>`);
  }

  if (rows.length === 0) return '';
  return `<div class="embed" style="border-left-color:${color}">${rows.join('')}</div>`;
}

function renderSticker(sticker) {
  const url = `https://media.discordapp.net/stickers/${sticker.id}.png`;
  return `<div class="attachment"><img class="sticker" src="${url}" alt="${escapeHtml(sticker.name ?? '스티커')}" loading="lazy"><div class="file-meta">스티커: ${escapeHtml(
    sticker.name ?? '알 수 없음',
  )}</div></div>`;
}

// --- 메시지 수집 ---

export async function fetchAllMessages(channel, max = config.transcript.maxMessages) {
  const collected = [];
  let before;
  let truncated = false;

  while (collected.length < max) {
    const batch = await channel.messages.fetch({ limit: 100, ...(before ? { before } : {}) });
    if (batch.size === 0) break;

    const ordered = [...batch.values()];
    collected.push(...ordered);
    before = ordered[ordered.length - 1].id;

    if (batch.size < 100) break;
    if (collected.length >= max) {
      truncated = true;
      break;
    }
  }

  collected.sort((a, b) => a.createdTimestamp - b.createdTimestamp);
  const messages = collected.length > max ? collected.slice(collected.length - max) : collected;
  return { messages, truncated: truncated || collected.length > max };
}

// --- 전체 HTML 생성 ---

export async function buildTranscriptHtml({ guild, channel, ticket, messages, truncated, closedBy, closedAt }) {
  const inliner = new MediaInliner({
    perFileMaxBytes: config.transcript.inlineMaxBytes,
    totalMaxBytes: config.transcript.inlineTotalBytes,
  });

  const ctx = buildMentionContext(guild, messages);
  const collected = { attachments: [], links: new Set() };

  const createdAt = ticket?.createdAt ?? channel.createdTimestamp;
  const participants = new Map();

  const messageBlocks = [];
  const messagesById = new Map(messages.map((message) => [message.id, message]));
  let previousAuthorId = null;
  let previousTimestamp = 0;

  for (const message of messages) {
    const author = message.author;
    const displayName = message.member?.displayName ?? author?.username ?? '알 수 없음';

    if (author) {
      const entry = participants.get(author.id) ?? { name: displayName, tag: author.tag ?? author.username, count: 0, bot: Boolean(author.bot) };
      entry.count += 1;
      entry.name = displayName;
      participants.set(author.id, entry);
    }

    const avatarSource = author?.displayAvatarURL?.({ extension: 'png', size: 64 }) ?? null;
    const avatar = avatarSource
      ? (await inliner.inline(avatarSource, { declaredType: 'image/png', maxBytes: 256 * 1024 })) ?? escapeHtml(avatarSource)
      : '';

    const grouped =
      previousAuthorId === author?.id && message.createdTimestamp - previousTimestamp < 5 * 60 * 1000;
    previousAuthorId = author?.id ?? null;
    previousTimestamp = message.createdTimestamp;

    const pieces = [];

    // 답장 대상
    if (message.reference?.messageId) {
      const referenced = messagesById.get(message.reference.messageId);
      if (referenced) {
        const refName = referenced.member?.displayName ?? referenced.author?.username ?? '알 수 없음';
        const refText = (referenced.content ?? '').replace(/\s+/g, ' ').slice(0, 120);
        pieces.push(
          `<div class="reply-ref">답장 대상: <span class="mention">@${escapeHtml(refName)}</span> ${escapeHtml(refText)}${
            (referenced.content ?? '').length > 120 ? '...' : ''
          }</div>`,
        );
      } else {
        pieces.push('<div class="reply-ref">답장 대상: 기록 범위 밖의 메시지</div>');
      }
    }

    const body = renderContent(message.content, ctx, collected.links);
    if (body) {
      pieces.push(
        `<div class="content">${body}${message.editedTimestamp ? '<span class="edited">(수정됨)</span>' : ''}</div>`,
      );
    }

    for (const attachment of message.attachments?.values?.() ?? []) {
      pieces.push(await renderAttachment(attachment, inliner, collected));
    }

    for (const sticker of message.stickers?.values?.() ?? []) {
      pieces.push(renderSticker(sticker));
    }

    for (const embed of message.embeds ?? []) {
      const rendered = renderEmbed(embed);
      if (rendered) pieces.push(rendered);
    }

    if (pieces.length === 0) {
      pieces.push('<div class="content empty">(표시할 내용이 없는 메시지)</div>');
    }

    const header = grouped
      ? ''
      : `<div class="msg-head"><span class="author">${escapeHtml(displayName)}</span>${
          author?.bot ? '<span class="badge">봇</span>' : ''
        }<span class="handle">${escapeHtml(author?.tag ?? author?.username ?? '')}</span><span class="time">${escapeHtml(
          formatKst(message.createdTimestamp),
        )}</span></div>`;

    // 묶인 메시지도 기록이므로 시각은 항상 남깁니다.
    const avatarColumn = grouped
      ? `<span class="grouped-time">${escapeHtml(formatKstTime(message.createdTimestamp))}</span>`
      : avatar
        ? `<img class="avatar" src="${avatar}" alt="">`
        : '';

    messageBlocks.push(
      `<div class="msg${grouped ? ' grouped' : ''}" id="m-${escapeHtml(message.id)}" title="${escapeHtml(
        formatKst(message.createdTimestamp),
      )}">` +
        `<div class="avatar-col">${avatarColumn}</div>` +
        `<div class="msg-body">${header}${pieces.join('')}</div>` +
        `</div>`,
    );
  }

  const closedTime = closedAt ?? Date.now();
  const duration = formatDuration(closedTime - createdAt);

  const linkList = [...collected.links];

  const summaryRows = [
    ['티켓 이름', ticket?.name ?? channel.name],
    ['티켓 종류', ticket?.typeLabel ?? '알 수 없음'],
    ['티켓 번호', ticket?.number ? String(ticket.number).padStart(4, '0') : '알 수 없음'],
    ['서버', guild.name],
    ['채널 ID', channel.id],
    ['생성자', ticket?.ownerTag ? `${ticket.ownerTag} (${ticket.ownerId})` : ticket?.ownerId ?? '알 수 없음'],
    ['만들어진 시간', formatKst(createdAt)],
    ['닫힌 시간', formatKst(closedTime)],
    ['유지 시간', duration],
    ['닫은 사람', closedBy ? `${closedBy.tag} (${closedBy.id})` : '알 수 없음'],
    ['메시지 수', `${messages.length}개${truncated ? ' (오래된 메시지는 일부 생략됨)' : ''}`],
    ['첨부파일 수', `${collected.attachments.length}개`],
    ['링크 수', `${linkList.length}개`],
  ];

  const summaryHtml = summaryRows
    .map(
      ([label, value]) =>
        `<div class="meta-row"><div class="meta-label">${escapeHtml(label)}</div><div class="meta-value">${escapeHtml(
          value,
        )}</div></div>`,
    )
    .join('');

  const participantsHtml = [...participants.entries()]
    .sort((a, b) => b[1].count - a[1].count)
    .map(
      ([id, entry]) =>
        `<li>${escapeHtml(entry.name)} <span class="dim">(${escapeHtml(entry.tag ?? '')} / ${escapeHtml(id)})</span>${
          entry.bot ? ' <span class="badge">봇</span>' : ''
        } - ${entry.count}개</li>`,
    )
    .join('');

  const attachmentsHtml =
    collected.attachments.length === 0
      ? '<li class="dim">첨부파일이 없습니다.</li>'
      : collected.attachments
          .map(
            (item) =>
              `<li>${escapeHtml(item.name)} <span class="dim">(${escapeHtml(item.contentType)} / ${escapeHtml(
                formatBytes(item.size),
              )})</span>${
                item.url
                  ? ` - <a class="link" href="${escapeHtml(item.url)}" target="_blank" rel="noopener noreferrer">원본 링크</a>`
                  : ''
              }</li>`,
          )
          .join('');

  const linksHtml =
    linkList.length === 0
      ? '<li class="dim">링크가 없습니다.</li>'
      : linkList
          .map((url) => `<li><a class="link" href="${url}" target="_blank" rel="noopener noreferrer">${url}</a></li>`)
          .join('');

  const title = `${ticket?.name ?? channel.name} 티켓 기록`;

  const html = `<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)}</title>
<style>
:root {
  color-scheme: dark;
  --bg: #1b1d21;
  --panel: #24272c;
  --panel-2: #2b2f36;
  --line: #383d45;
  --text: #e6e8ea;
  --dim: #9aa0a8;
  --accent: #5b82f5;
}
* { box-sizing: border-box; }
body {
  margin: 0;
  padding: 24px 16px 64px;
  background: var(--bg);
  color: var(--text);
  font-family: "Pretendard", "Malgun Gothic", "Apple SD Gothic Neo", "Noto Sans KR", system-ui, -apple-system, "Segoe UI", sans-serif;
  font-size: 15px;
  line-height: 1.6;
  word-break: break-word;
}
.wrap { max-width: 960px; margin: 0 auto; }
h1 { font-size: 22px; margin: 0 0 4px; }
h2 { font-size: 16px; margin: 28px 0 10px; padding-bottom: 6px; border-bottom: 1px solid var(--line); }
.subtitle { color: var(--dim); font-size: 13px; margin-bottom: 20px; }
.card { background: var(--panel); border: 1px solid var(--line); border-radius: 10px; padding: 16px 18px; }
.meta-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 4px 24px; }
.meta-row { display: flex; gap: 10px; padding: 4px 0; border-bottom: 1px solid rgba(255,255,255,0.04); }
.meta-label { flex: 0 0 110px; color: var(--dim); font-size: 13px; }
.meta-value { flex: 1; font-size: 13px; }
ul.list { margin: 0; padding-left: 20px; }
ul.list li { padding: 2px 0; font-size: 13px; }
.dim { color: var(--dim); }
.messages { margin-top: 12px; }
.msg { display: flex; gap: 12px; padding: 6px 8px; border-radius: 8px; }
.msg:hover { background: rgba(255,255,255,0.02); }
.msg.grouped { padding-top: 0; }
.avatar-col { flex: 0 0 40px; }
.avatar { width: 40px; height: 40px; border-radius: 50%; display: block; }
.grouped-time { display: block; color: var(--dim); font-size: 11px; line-height: 1.6; text-align: right; padding-right: 2px; }
.msg-body { flex: 1; min-width: 0; }
.msg-head { display: flex; align-items: baseline; flex-wrap: wrap; gap: 8px; margin-bottom: 2px; }
.author { font-weight: 600; }
.handle { color: var(--dim); font-size: 12px; }
.time { color: var(--dim); font-size: 12px; margin-left: auto; }
.badge { background: var(--accent); color: #fff; font-size: 10px; padding: 1px 5px; border-radius: 4px; }
.content { white-space: normal; }
.content.empty { color: var(--dim); font-style: italic; }
.edited { color: var(--dim); font-size: 11px; margin-left: 6px; }
.reply-ref { color: var(--dim); font-size: 12px; border-left: 2px solid var(--line); padding-left: 8px; margin-bottom: 4px; }
.mention { background: rgba(91,130,245,0.18); color: #a9c0ff; border-radius: 3px; padding: 0 3px; }
.link { color: #6aa9f5; text-decoration: none; }
.link:hover { text-decoration: underline; }
.quote { border-left: 3px solid var(--line); padding: 0 0 0 10px; margin: 2px 0; color: #cdd2d8; }
.spoiler { background: #3a3f47; color: transparent; border-radius: 3px; padding: 0 3px; }
.spoiler:hover { color: inherit; }
.inline-code { background: #14161a; border: 1px solid var(--line); border-radius: 4px; padding: 1px 5px; font-family: Consolas, "Courier New", monospace; font-size: 13px; }
.codeblock { background: #14161a; border: 1px solid var(--line); border-radius: 6px; padding: 10px 12px; overflow-x: auto; margin: 6px 0; }
.codeblock code { font-family: Consolas, "Courier New", monospace; font-size: 13px; white-space: pre; }
.inline-emoji { width: 20px; height: 20px; vertical-align: -4px; }
.attachment { margin: 6px 0; }
.media { max-width: 420px; max-height: 340px; border-radius: 8px; display: block; background: #000; }
.sticker { width: 140px; height: 140px; }
.audio { width: 340px; }
.file-card { background: var(--panel-2); border: 1px solid var(--line); border-radius: 8px; padding: 8px 12px; display: inline-block; }
.file-meta { color: var(--dim); font-size: 12px; margin-top: 4px; }
.file-note { color: #d9822b; font-size: 12px; }
.embed { background: var(--panel-2); border-left: 4px solid var(--line); border-radius: 6px; padding: 10px 14px; margin: 6px 0; max-width: 520px; }
.embed-author { font-size: 13px; font-weight: 600; margin-bottom: 4px; }
.embed-title { font-weight: 600; margin-bottom: 4px; }
.embed-description { font-size: 14px; }
.embed-fields { display: flex; flex-wrap: wrap; gap: 10px; margin-top: 8px; }
.embed-field { flex: 1 1 100%; }
.embed-field.inline { flex: 1 1 30%; }
.embed-field-name { font-size: 13px; font-weight: 600; }
.embed-field-value { font-size: 13px; color: #d3d7dc; }
.embed-image { margin-top: 8px; }
.embed-thumbnail img { width: 72px; height: 72px; border-radius: 6px; margin-top: 8px; }
.embed-footer { color: var(--dim); font-size: 12px; margin-top: 8px; }
.notice { background: rgba(217,130,43,0.12); border: 1px solid rgba(217,130,43,0.4); color: #f0b571; border-radius: 8px; padding: 10px 14px; font-size: 13px; margin-top: 12px; }
footer { color: var(--dim); font-size: 12px; margin-top: 32px; text-align: center; }
</style>
</head>
<body>
<div class="wrap">
  <h1>${escapeHtml(title)}</h1>
  <div class="subtitle">${escapeHtml(guild.name)} · ${escapeHtml(formatKst(createdAt))} 부터 ${escapeHtml(
    formatKst(closedTime),
  )} 까지</div>

  <div class="card">
    <div class="meta-grid">${summaryHtml}</div>
  </div>

  ${truncated ? '<div class="notice">메시지가 많아 오래된 일부 메시지는 기록에서 생략되었습니다.</div>' : ''}
  ${
    inliner.skipped > 0 || inliner.failed > 0
      ? `<div class="notice">용량 제한 또는 다운로드 실패로 첨부파일 ${
          inliner.skipped + inliner.failed
        }개는 기록 파일 안에 포함하지 못했습니다. 해당 항목은 원본 링크로만 남아 있으며 링크는 시간이 지나면 만료될 수 있습니다.</div>`
      : ''
  }

  <h2>참여자</h2>
  <ul class="list">${participantsHtml || '<li class="dim">참여자가 없습니다.</li>'}</ul>

  <h2>대화 내용</h2>
  <div class="messages">${messageBlocks.join('') || '<div class="dim">기록된 메시지가 없습니다.</div>'}</div>

  <h2>첨부파일 목록</h2>
  <ul class="list">${attachmentsHtml}</ul>

  <h2>링크 목록</h2>
  <ul class="list">${linksHtml}</ul>

  <footer>이 기록은 티켓이 닫힌 ${escapeHtml(formatKst(closedTime))} 에 자동으로 생성되었습니다.</footer>
</div>
</body>
</html>`;

  return {
    html,
    stats: {
      messageCount: messages.length,
      attachmentCount: collected.attachments.length,
      linkCount: linkList.length,
      participantCount: participants.size,
      truncated,
      inlineSkipped: inliner.skipped + inliner.failed,
      duration,
      createdAt,
      closedAt: closedTime,
    },
  };
}
