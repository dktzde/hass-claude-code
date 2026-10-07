#!/usr/bin/env node
/**
 * Build-time script: creates the keyword (FTS5) SQLite database from docs.
 * Run during Docker build.
 *
 * Usage: DOCS_DB_PATH=/path/to/db.db DOCS_PATH=/path/to/docs node --import tsx src/build-index.ts
 */
import { existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { initDb } from './db.js';
import { indexDocSet } from './indexer.js';

const DOCS_PATH = process.env.DOCS_PATH || '/opt/docs';

async function main() {
  console.error('Build-time indexing: creating keyword database...');
  initDb();

  const docSets = [
    { name: 'hass-developer', path: resolve(DOCS_PATH, 'hass-developer') },
    { name: 'hass-user', path: resolve(DOCS_PATH, 'hass-user') },
  ];

  for (const docSet of docSets) {
    if (!existsSync(docSet.path)) {
      console.error(`Skipping ${docSet.name}: path not found at ${docSet.path}`);
      continue;
    }
    await indexDocSet(docSet.path, docSet.name);
  }

  console.error('Build-time indexing complete.');
}

main().catch((err) => {
  console.error('Build-time indexing failed:', err);
  process.exit(1);
});
