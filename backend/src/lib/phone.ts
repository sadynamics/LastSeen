import { parsePhoneNumberFromString, type CountryCode } from 'libphonenumber-js';
import { BadRequestError } from './errors.js';

export interface ParsedNumber {
  e164: string;
  countryCode: CountryCode | null;
  /** WhatsApp JID, e.g. `905551234567@s.whatsapp.net`. */
  jid: string;
}

/**
 * Validate + normalize a user-supplied phone number into E.164 + WhatsApp JID.
 */
export function normalizePhone(input: string, defaultCountry?: CountryCode): ParsedNumber {
  const parsed = parsePhoneNumberFromString(input, defaultCountry);
  if (!parsed || !parsed.isValid()) {
    throw new BadRequestError('Invalid phone number', { input });
  }
  const e164 = parsed.number;
  return {
    e164,
    countryCode: parsed.country ?? null,
    jid: `${e164.replace(/^\+/, '')}@s.whatsapp.net`,
  };
}

export function jidFromE164(e164: string): string {
  return `${e164.replace(/^\+/, '')}@s.whatsapp.net`;
}

export function e164FromJid(jid: string): string {
  const num = jid.split('@')[0]?.split(':')[0] ?? '';
  return `+${num}`;
}
