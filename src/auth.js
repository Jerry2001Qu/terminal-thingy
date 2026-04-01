import crypto from 'node:crypto';

export function generateCode() {
  const num = crypto.randomInt(0, 1000000);
  return num.toString().padStart(6, '0');
}

export function generateSalt() {
  return crypto.randomBytes(16).toString('hex');
}

export function deriveKey(code, salt) {
  const derived = crypto.hkdfSync('sha256', code, Buffer.from(salt, 'hex'), 'terminal-thingy', 32);
  return Buffer.from(derived);
}

export function encrypt(plaintext, key) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const encrypted = Buffer.concat([
    cipher.update(plaintext, 'utf8'),
    cipher.final(),
  ]);
  const authTag = cipher.getAuthTag();
  // Format: base64(iv + authTag + ciphertext)
  return Buffer.concat([iv, authTag, encrypted]).toString('base64');
}

export function decrypt(ciphertext, key) {
  const buf = Buffer.from(ciphertext, 'base64');
  const iv = buf.subarray(0, 12);
  const authTag = buf.subarray(12, 28);
  const encrypted = buf.subarray(28);
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(authTag);
  return decipher.update(encrypted, null, 'utf8') + decipher.final('utf8');
}

export function formatCode(code) {
  return `${code.slice(0, 3)} ${code.slice(3)}`;
}
