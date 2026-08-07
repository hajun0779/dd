import { promises as fs } from 'node:fs';
import path from 'node:path';
import { config } from './config.js';
import { log } from './log.js';

const DEFAULT_DATA = {
  // 티켓 번호 카운터: { "<서버ID>:<종류>": 3 }
  counters: {},
  // 열려 있는 티켓: { [channelId]: { channelId, guildId, type, ownerId, number, name, createdAt } }
  tickets: {},
  // 봇이 게시한 패널 메시지: { ticket: { channelId, messageId } }
  panels: {},
};

class Store {
  constructor(filePath) {
    this.filePath = path.resolve(filePath);
    this.data = structuredClone(DEFAULT_DATA);
    this.writeChain = Promise.resolve();
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

  // --- 패널 ---

  setPanel(name, payload) {
    this.data.panels[name] = payload;
    this.save();
  }

  getPanel(name) {
    return this.data.panels[name] ?? null;
  }
}

export const store = new Store(config.dataFile);
