import { promises as fs } from 'node:fs';
import path from 'node:path';
import { config } from './config.js';
import { log } from './log.js';

const DEFAULT_DATA = {
  // 티켓 번호 카운터: { general: 0, bug: 0, partner: 0 }
  counters: {},
  // 열려 있는 티켓: { [channelId]: { channelId, guildId, type, ownerId, number, name, createdAt } }
  tickets: {},
  // 인증 완료된 사용자: { [`${guildId}:${userId}`]: { robloxId, robloxName, verifiedAt } }
  verified: {},
  // 인증 진행 중인 사용자: { [`${guildId}:${userId}`]: { code, robloxId, robloxName, issuedAt, expiresAt } }
  pending: {},
  // 봇이 게시한 패널 메시지: { verify: { channelId, messageId }, ticket: { ... } }
  panels: {},
};

class Store {
  constructor(filePath) {
    this.filePath = path.resolve(filePath);
    this.data = structuredClone(DEFAULT_DATA);
    this.writeChain = Promise.resolve();
    this.dirty = false;
  }

  async load() {
    try {
      const raw = await fs.readFile(this.filePath, 'utf8');
      const parsed = JSON.parse(raw);
      this.data = { ...structuredClone(DEFAULT_DATA), ...parsed };
      for (const key of Object.keys(DEFAULT_DATA)) {
        if (typeof this.data[key] !== 'object' || this.data[key] === null) {
          this.data[key] = structuredClone(DEFAULT_DATA[key]);
        }
      }
      log.info(`저장소를 불러왔습니다: ${this.filePath}`);
    } catch (error) {
      if (error.code === 'ENOENT') {
        log.info(`저장소 파일이 없어 새로 생성합니다: ${this.filePath}`);
        await this.save();
      } else {
        log.error('저장소를 불러오지 못했습니다. 기본값으로 시작합니다.', error);
      }
    }
    return this.data;
  }

  /** 동시 쓰기로 파일이 깨지지 않도록 직렬화해서 저장합니다. */
  save() {
    this.writeChain = this.writeChain.then(() => this.#writeNow()).catch((error) => {
      log.error('저장소 저장에 실패했습니다.', error);
    });
    return this.writeChain;
  }

  async #writeNow() {
    const dir = path.dirname(this.filePath);
    await fs.mkdir(dir, { recursive: true });
    const tmp = `${this.filePath}.tmp`;
    await fs.writeFile(tmp, JSON.stringify(this.data, null, 2), 'utf8');
    await fs.rename(tmp, this.filePath);
  }

  // --- 티켓 번호 ---

  nextTicketNumber(guildId, typeValue) {
    const key = `${guildId}:${typeValue}`;
    const current = Number.isInteger(this.data.counters[key]) ? this.data.counters[key] : 0;
    const next = current + 1;
    this.data.counters[key] = next;
    this.save();
    return next;
  }

  // --- 티켓 ---

  addTicket(ticket) {
    this.data.tickets[ticket.channelId] = ticket;
    this.save();
  }

  getTicket(channelId) {
    return this.data.tickets[channelId] ?? null;
  }

  removeTicket(channelId) {
    delete this.data.tickets[channelId];
    this.save();
  }

  findOpenTicket(guildId, ownerId, typeValue) {
    return (
      Object.values(this.data.tickets).find(
        (ticket) =>
          ticket.guildId === guildId && ticket.ownerId === ownerId && ticket.type === typeValue,
      ) ?? null
    );
  }

  // --- 인증 ---

  #memberKey(guildId, userId) {
    return `${guildId}:${userId}`;
  }

  setPending(guildId, userId, payload) {
    this.data.pending[this.#memberKey(guildId, userId)] = payload;
    this.save();
  }

  getPending(guildId, userId) {
    return this.data.pending[this.#memberKey(guildId, userId)] ?? null;
  }

  clearPending(guildId, userId) {
    delete this.data.pending[this.#memberKey(guildId, userId)];
    this.save();
  }

  setVerified(guildId, userId, payload) {
    this.data.verified[this.#memberKey(guildId, userId)] = payload;
    this.save();
  }

  getVerified(guildId, userId) {
    return this.data.verified[this.#memberKey(guildId, userId)] ?? null;
  }

  /** 다른 디스코드 계정이 이미 같은 로블록스 계정을 연동했는지 확인합니다. */
  findVerifiedByRobloxId(guildId, robloxId) {
    const prefix = `${guildId}:`;
    for (const [key, value] of Object.entries(this.data.verified)) {
      if (!key.startsWith(prefix)) continue;
      if (String(value.robloxId) === String(robloxId)) {
        return { userId: key.slice(prefix.length), ...value };
      }
    }
    return null;
  }

  // --- 패널 ---

  setPanel(name, payload) {
    this.data.panels[name] = payload;
    this.save();
  }

  getPanel(name) {
    return this.data.panels[name] ?? null;
  }

  /** 만료된 인증 대기 항목을 정리합니다. */
  prunePending(now = Date.now()) {
    let removed = 0;
    for (const [key, value] of Object.entries(this.data.pending)) {
      if (!value?.expiresAt || value.expiresAt <= now) {
        delete this.data.pending[key];
        removed += 1;
      }
    }
    if (removed > 0) this.save();
    return removed;
  }
}

export const store = new Store(config.dataFile);
