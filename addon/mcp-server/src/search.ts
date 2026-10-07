import { getDb } from './db.js';
import type { SearchResult } from './types.js';

export interface KeywordSearchResult {
  results: SearchResult[];
  /** Set when typos were corrected to find the results */
  correctedQuery?: string;
}

/**
 * Full-text search over the docs, in steps until something matches:
 * 1. The query as FTS5 syntax, so phrases like "options flow" work.
 * 2. Its words, all of which must match. This also covers queries FTS5 cannot
 *    parse, such as identifiers with dots or dashes (light.turn_on, config-flow).
 * 3. The same with typos corrected: words that do not occur in the docs are
 *    replaced by the closest word that does (tun_on -> turn_on).
 * 4. Any of the (corrected) words.
 */
export async function keywordSearch(query: string, limit = 10, docSet?: string): Promise<KeywordSearchResult> {
  try {
    const results = runMatch(query, limit, docSet);
    if (results.length > 0) return { results };
  } catch (e: any) {
    if (e?.code !== 'SQLITE_ERROR') throw e;
  }

  const words = query.match(/[\p{L}\p{N}_]+/gu) ?? [];
  if (words.length === 0) return { results: [] };

  const allWords = matchWords(words, 'AND', limit, docSet);
  if (allWords.length > 0) return { results: allWords };

  const corrected = words.map(correctWord);
  const changed = corrected.some((w, i) => w !== words[i]);
  const correctedQuery = changed ? corrected.join(' ') : undefined;
  if (changed) {
    const fixed = matchWords(corrected, 'AND', limit, docSet);
    if (fixed.length > 0) return { results: fixed, correctedQuery };
  }

  if (words.length === 1) return { results: [] };
  const anyWord = matchWords(corrected, 'OR', limit, docSet);
  return anyWord.length > 0 ? { results: anyWord, correctedQuery } : { results: [] };
}

function matchWords(words: string[], operator: 'AND' | 'OR', limit: number, docSet?: string): SearchResult[] {
  return runMatch(words.map(w => `"${w}"`).join(` ${operator} `), limit, docSet);
}

function runMatch(match: string, limit: number, docSet?: string): SearchResult[] {
  const db = getDb();

  let sql = `
    SELECT c.id, c.chunk_text, c.section_heading, f.file_path, f.title, fts.rank
    FROM chunks_fts fts
    JOIN chunks c ON c.id = fts.rowid
    JOIN files f ON f.id = c.file_id
    WHERE chunks_fts MATCH ?`;

  const params: Array<string | number> = [match];

  if (docSet) {
    sql += ` AND f.doc_set = ?`;
    params.push(docSet);
  }

  sql += `
    ORDER BY fts.rank
    LIMIT ?`;

  params.push(limit);

  const rows = db.prepare(sql).all(...params) as Array<{
    id: number;
    chunk_text: string;
    section_heading: string | null;
    file_path: string;
    title: string | null;
    rank: number;
  }>;

  return rows.map(row => ({
    chunk_text: row.chunk_text,
    section_heading: row.section_heading,
    file_path: row.file_path,
    title: row.title,
    score: row.rank,
  }));
}

// --- Typo correction against the words of the docs (FTS5 vocabulary) ---

let vocabulary: Map<string, number> | null = null;

/** Word -> number of chunks containing it, as the FTS5 tokenizer stored it */
function getVocabulary(): Map<string, number> {
  if (!vocabulary) {
    const rows = getDb().prepare('SELECT term, doc FROM chunks_vocab').all() as Array<{ term: string; doc: number }>;
    vocabulary = new Map(rows.map(r => [r.term, r.doc]));
  }
  return vocabulary;
}

/** Corrects each part of a word; the FTS5 tokenizer splits turn_on into turn and on */
function correctWord(word: string): string {
  return word.split('_').map(correctToken).join('_');
}

function correctToken(token: string): string {
  // Normalized like the FTS5 unicode61 tokenizer: lower case, no diacritics
  const normalized = token.toLowerCase().normalize('NFD').replace(/\p{M}/gu, '');
  const vocab = getVocabulary();
  if (normalized.length < 3 || /^\d+$/.test(normalized) || vocab.has(normalized)) return token;

  // On a tie, prefer the same first letter (typos rarely hit it), then the
  // more common word
  const maxDistance = normalized.length <= 5 ? 1 : 2;
  let best: { term: string; distance: number; sameStart: boolean; count: number } | null = null;
  for (const [term, count] of vocab) {
    if (Math.abs(term.length - normalized.length) > maxDistance) continue;
    const distance = editDistance(normalized, term, maxDistance);
    if (distance > maxDistance) continue;
    const sameStart = term[0] === normalized[0];
    if (!best || distance < best.distance ||
        (distance === best.distance && sameStart && !best.sameStart) ||
        (distance === best.distance && sameStart === best.sameStart && count > best.count)) {
      best = { term, distance, sameStart, count };
    }
  }
  return best?.term ?? token;
}

/**
 * Edit distance counting insertions, deletions, substitutions and swaps of
 * neighbouring letters. Stops early and returns max + 1 once it exceeds max.
 */
function editDistance(a: string, b: string, max: number): number {
  let prevPrev: number[] = [];
  let prev = Array.from({ length: b.length + 1 }, (_, j) => j);
  for (let i = 1; i <= a.length; i++) {
    const row = [i];
    let rowMin = i;
    for (let j = 1; j <= b.length; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      let value = Math.min(prev[j] + 1, row[j - 1] + 1, prev[j - 1] + cost);
      if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) {
        value = Math.min(value, prevPrev[j - 2] + 1);
      }
      row[j] = value;
      rowMin = Math.min(rowMin, value);
    }
    if (rowMin > max) return max + 1;
    prevPrev = prev;
    prev = row;
  }
  return prev[b.length];
}
