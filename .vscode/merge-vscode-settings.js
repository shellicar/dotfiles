#!/usr/bin/env node

const fs = require('node:fs');

function parseJsonFile(filePath) {
  if (!fs.existsSync(filePath)) {
    return {};
  }
  const buffer = fs.readFileSync(filePath);
  let text = buffer.toString('utf8');
  text = text.replace(/\\n/g, '\\\\n');
  text = text.replace(/\\b/g, '\\\\\\b');
  return JSON.parse(text);
}

function stringifyJson(obj) {
  return JSON.stringify(obj, null, 2);
}

function deepMerge(target, source) {
  const result = { ...target };
  for (const key in source) {
    if (source[key] && typeof source[key] === 'object' && !Array.isArray(source[key])) {
      result[key] = deepMerge(target[key] ?? {}, source[key]);
    } else {
      result[key] = source[key];
    }
  }
  return result;
}

function main() {
  if (process.argv.length !== 4) {
    console.error('Usage: merge-vscode-settings.js <central-file> <target-file>');
    process.exit(1);
  }

  const centralFile = process.argv[2];
  const targetFile = process.argv[3];

  try {
    const central = parseJsonFile(centralFile);
    const target = parseJsonFile(targetFile);
    const merged = deepMerge(target, central);
    console.log(stringifyJson(merged));
  } catch (error) {
    console.error('Error merging settings:', error.message);
    process.exit(1);
  }
}

main();
