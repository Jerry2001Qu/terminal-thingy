import { describe, it, expect } from 'vitest';
import { generateCode, generateSalt, deriveKey, encrypt, decrypt, formatCode } from '../src/auth.js';

describe('generateCode', () => {
  it('returns a 6-digit numeric string', () => {
    const code = generateCode();
    expect(code).toMatch(/^\d{6}$/);
  });

  it('generates different codes on each call', () => {
    const codes = new Set(Array.from({ length: 10 }, () => generateCode()));
    expect(codes.size).toBeGreaterThan(1);
  });
});

describe('generateSalt', () => {
  it('returns a 16-byte hex string', () => {
    const salt = generateSalt();
    expect(salt).toMatch(/^[0-9a-f]{32}$/);
  });
});

describe('deriveKey', () => {
  it('returns a 32-byte buffer', () => {
    const key = deriveKey('123456', 'ab'.repeat(16));
    expect(key).toBeInstanceOf(Buffer);
    expect(key.length).toBe(32);
  });

  it('same inputs produce same key', () => {
    const salt = generateSalt();
    const k1 = deriveKey('123456', salt);
    const k2 = deriveKey('123456', salt);
    expect(k1.equals(k2)).toBe(true);
  });

  it('different codes produce different keys', () => {
    const salt = generateSalt();
    const k1 = deriveKey('123456', salt);
    const k2 = deriveKey('654321', salt);
    expect(k1.equals(k2)).toBe(false);
  });
});

describe('encrypt/decrypt', () => {
  it('round-trips a string', () => {
    const key = deriveKey('123456', generateSalt());
    const plaintext = JSON.stringify({ type: 'state', cols: 80, rows: 24 });
    const ciphertext = encrypt(plaintext, key);
    expect(ciphertext).not.toBe(plaintext);
    const decrypted = decrypt(ciphertext, key);
    expect(decrypted).toBe(plaintext);
  });

  it('different keys cannot decrypt', () => {
    const salt = generateSalt();
    const key1 = deriveKey('123456', salt);
    const key2 = deriveKey('654321', salt);
    const ciphertext = encrypt('hello', key1);
    expect(() => decrypt(ciphertext, key2)).toThrow();
  });

  it('same plaintext produces different ciphertext (random IV)', () => {
    const key = deriveKey('123456', generateSalt());
    const c1 = encrypt('hello', key);
    const c2 = encrypt('hello', key);
    expect(c1).not.toBe(c2);
  });
});

describe('formatCode', () => {
  it('formats as XXX XXX', () => {
    expect(formatCode('847291')).toBe('847 291');
  });
});
