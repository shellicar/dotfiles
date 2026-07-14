#!/usr/bin/env node

// Sync the repo's VS Code settings into this machine's live settings.json.
//
// The settings themselves are not platform-specific — only *where* they live
// is. VS Code's per-platform keys (terminal.integrated.defaultProfile.osx /
// .linux / .windows) are separate setting IDs; each host reads only its own and
// ignores the rest, so a single source file serves every machine. The only
// OS-awareness this tool needs is the destination path.
//
// The merge preserves machine-local keys: anything already in the live file but
// absent from the repo source is left untouched. Dry-run is the default and
// doubles as a drift view; --apply writes, backing up the live file first.

import { execFileSync } from 'node:child_process';
import { copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { homedir, userInfo } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const SOURCE = join(HERE, 'settings.json');
const GET_OS = join(HERE, '..', 'get-os.sh');

const c = {
  reset: '\x1b[0m',
  bold: '\x1b[1m',
  dim: '\x1b[2m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
};

function printHelp() {
  console.log(`Usage: sync.mjs [--apply]

Merge the repo VS Code settings into this machine's live settings.json,
preserving machine-local keys.

  (no args)        dry-run: show the per-key diff against the live file
  --apply          write the changes (a timestamped backup is made first)
  -h, --help       show this help`);
}

function parseArgs(argv) {
  let apply = false;
  for (const arg of argv) {
    switch (arg) {
      case '--apply':
        apply = true;
        break;
      case '-h':
      case '--help':
        printHelp();
        process.exit(0);
        break;
      default:
        console.error(`Unknown option: ${arg}`);
        console.error('Use -h for help');
        process.exit(1);
    }
  }
  return { apply };
}

function detectOs() {
  return execFileSync(GET_OS).toString().trim();
}

function targetPath(os) {
  const user = userInfo().username;
  switch (os) {
    case 'macos':
      return join(homedir(), 'Library', 'Application Support', 'Code', 'User', 'settings.json');
    case 'windows-bash':
      return `/c/Users/${user}/AppData/Roaming/Code/User/settings.json`;
    case 'wsl':
      return `/mnt/c/Users/${user}/AppData/Roaming/Code/User/settings.json`;
    default:
      console.error(`${c.red}Unsupported OS for VS Code settings sync: ${os}${c.reset}`);
      console.error('Supported: macos, windows-bash, wsl (native Linux is not synced).');
      process.exit(1);
  }
}

function readJson(path) {
  try {
    return JSON.parse(readFileSync(path, 'utf8'));
  } catch (error) {
    console.error(`${c.red}Failed to parse ${path}: ${error.message}${c.reset}`);
    console.error('The live settings file must be valid JSON (comments are not supported).');
    process.exit(1);
  }
}

function sortKeys(value) {
  if (Array.isArray(value)) {
    return value.map(sortKeys);
  }
  if (value && typeof value === 'object') {
    const out = {};
    for (const key of Object.keys(value).sort()) {
      out[key] = sortKeys(value[key]);
    }
    return out;
  }
  return value;
}

function deepMerge(target, source) {
  const result = { ...target };
  for (const key of Object.keys(source)) {
    const sv = source[key];
    if (sv && typeof sv === 'object' && !Array.isArray(sv)) {
      result[key] = deepMerge(target[key] ?? {}, sv);
    } else {
      result[key] = sv;
    }
  }
  return result;
}

// Flatten to dotted leaf paths so the diff is per-key, not per-object.
function flatten(obj, prefix = '', out = {}) {
  for (const key of Object.keys(obj)) {
    const path = prefix ? `${prefix}.${key}` : key;
    const value = obj[key];
    if (value && typeof value === 'object' && !Array.isArray(value)) {
      flatten(value, path, out);
    } else {
      out[path] = JSON.stringify(sortKeys(value));
    }
  }
  return out;
}

function canonical(obj) {
  return `${JSON.stringify(sortKeys(obj), null, 2)}\n`;
}

function main() {
  const { apply } = parseArgs(process.argv.slice(2));
  const os = detectOs();
  const target = targetPath(os);
  const source = readJson(SOURCE);
  const live = existsSync(target) ? readJson(target) : {};
  const merged = deepMerge(live, source);

  const flatLive = flatten(live);
  const flatSource = flatten(source);
  const flatMerged = flatten(merged);

  const added = [];
  const changed = [];
  for (const path of Object.keys(flatMerged).sort()) {
    if (flatLive[path] === undefined) {
      added.push(`${c.green}+ ${path} = ${flatMerged[path]}${c.reset}`);
    } else if (flatLive[path] !== flatMerged[path]) {
      changed.push(`${c.yellow}~ ${path}: ${flatLive[path]} -> ${flatMerged[path]}${c.reset}`);
    }
  }
  const preserved = Object.keys(flatLive).filter((path) => flatSource[path] === undefined);

  console.log(`${c.bold}VS Code settings sync${c.reset}`);
  console.log(`  os:     ${os}`);
  console.log(`  source: ${SOURCE}`);
  console.log(`  target: ${target}${existsSync(target) ? '' : `${c.dim} (does not exist yet)${c.reset}`}`);
  console.log('');

  if (added.length === 0 && changed.length === 0) {
    console.log(`${c.green}Already in sync — no changes.${c.reset}`);
    console.log(`${c.dim}${preserved.length} machine-local key(s) preserved.${c.reset}`);
    return;
  }

  for (const line of added) console.log(line);
  for (const line of changed) console.log(line);
  console.log('');
  console.log(`${c.dim}${preserved.length} machine-local key(s) left untouched.${c.reset}`);
  console.log('');

  if (!apply) {
    console.log(`${c.dim}[dry run] pass --apply to write these changes.${c.reset}`);
    return;
  }

  const dir = dirname(target);
  mkdirSync(dir, { recursive: true });
  if (existsSync(target)) {
    const stamp = new Date().toISOString().replace(/[:.]/g, '-');
    const backup = `${target}.backup.${stamp}`;
    copyFileSync(target, backup);
    console.log(`${c.bold}Backup:${c.reset} ${backup}`);
  }
  writeFileSync(target, canonical(merged));
  console.log(`${c.green}Written: ${target}${c.reset}`);
}

main();
