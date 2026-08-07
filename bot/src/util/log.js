import { config } from '../config.js';

function stamp() {
  return new Date().toLocaleString('sv-SE', { timeZone: config.timezone, hour12: false });
}

function write(stream, level, args) {
  stream(`[${stamp()}] [${level}]`, ...args);
}

export const log = {
  info: (...args) => write(console.log, 'INFO', args),
  warn: (...args) => write(console.warn, 'WARN', args),
  error: (...args) => write(console.error, 'ERROR', args),
  debug: (...args) => {
    if (process.env.DEBUG) write(console.log, 'DEBUG', args);
  },
};
