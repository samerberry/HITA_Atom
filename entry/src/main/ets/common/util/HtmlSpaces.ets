export function normalizeHtmlSpaces(raw: string): string {
  // Legacy EAS pages may omit the semicolon or escape the same entity repeatedly.
  return raw.replace(/&(?:(?:amp|#0*38|#x0*26);)*(?:nbsp|#0*160|#x0*a0)(?:;|(?![a-z0-9]))/gi, ' ')
    .replace(/\s+/g, ' ').trim();
}
