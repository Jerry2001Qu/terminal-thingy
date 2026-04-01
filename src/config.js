import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { generateCode, generateSalt } from './auth.js';

const CONFIG_DIR = path.join(os.homedir(), '.config', 'terminal-thingy');
const CONFIG_FILE = path.join(CONFIG_DIR, 'config.json');

export function loadOrCreateConfig() {
  if (fs.existsSync(CONFIG_FILE)) {
    try {
      const config = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
      if (config.deviceId && config.pin && config.salt) {
        return config;
      }
    } catch {
      // Corrupted file, regenerate
    }
  }
  return createConfig();
}

export function resetPin() {
  const config = loadOrCreateConfig();
  config.pin = generateCode();
  config.salt = generateSalt();
  saveConfig(config);
  return config;
}

function createConfig() {
  const config = {
    deviceId: crypto.randomUUID(),
    pin: generateCode(),
    salt: generateSalt(),
  };
  saveConfig(config);
  return config;
}

function saveConfig(config) {
  fs.mkdirSync(CONFIG_DIR, { recursive: true });
  fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2) + '\n');
}
