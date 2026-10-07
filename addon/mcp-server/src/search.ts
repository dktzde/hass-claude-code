import { getDb } from './db.js';
import type { SearchResult } from './types.js';

/**
 * Full-text search over the docs. The query is first used as FTS5 syntax, so
 * phrases like "options flow" work. Queries FTS5 cannot parse, such as
 * identifiers with dots or dashes (light.turn_on, config-flow), are split into
 * words instead: all words must match, or failing that, any of them.
 */
export async function keywordSearch(query: string, limit = 10, docSet?: string): Promise<SearchResult[]> {
  try {
    return runMatch(query, limit, docSet);
  } catch (e: any) {
    if (e?.code !== 'SQLITE_ERROR') throw e;
  }

  const words = query.match(/[\p{L}\p{N}_]+/gu) ?? [];
  if (words.length === 0) return [];
  const quoted = words.map(w => `"${w}"`);

  const allWords = runMatch(quoted.join(' AND '), limit, docSet);
  if (allWords.length > 0 || words.length === 1) return allWords;
  return runMatch(quoted.join(' OR '), limit, docSet);
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
