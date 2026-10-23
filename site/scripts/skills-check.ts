/**
 * Checks that installed agent skills match the dependency versions in the repo.
 * Warns (exit 1 with --strict, else exit 0) when:
 *  - a mapped dep's installed major version differs from skills.versions.json checkedMajor
 *  - a mapped skill is missing from .claude/skills/
 *  - a dep in the map is no longer installed anywhere in the workspace
 *  - a skill's files no longer match its skills-lock.json computedHash
 * Always exits 1 when `pnpm why` cannot run, since versions are then unknown.
 */
import { execSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..');
const skillsDir = path.join(root, '.claude/skills');
const strict = process.argv.includes('--strict');

type Entry = {
  checkedMajor: number;
  skills: Array<string>;
  source: string | null;
};

const map = JSON.parse(readFileSync(path.join(root, 'skills.versions.json'), 'utf8')) as {
  deps: Record<string, Entry>;
};

const lock = JSON.parse(readFileSync(path.join(root, 'skills-lock.json'), 'utf8')) as {
  skills: Record<string, { computedHash: string; source: string }>;
};

const installedVersions = (deps: Array<string>): Map<string, string> => {
  let out: string;
  try {
    out = execSync(`pnpm why -r --json ${deps.join(' ')}`, {
      cwd: root,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  } catch (error) {
    const { message, stderr, stdout } = error as {
      message: string;
      stderr?: string;
      stdout?: string;
    };
    process.stderr.write(
      `skills-check: 'pnpm why' failed, so installed versions are unknown. Is pnpm on PATH and the workspace installed?\n${(stderr || stdout || message).trim()}\n`,
    );
    process.exit(1);
  }
  const versions = new Map<string, string>();
  for (const entry of JSON.parse(out) as Array<{ name: string; version?: string }>) {
    if (entry.version != null && !versions.has(entry.name)) {
      versions.set(entry.name, entry.version);
    }
  }
  return versions;
};

// Same algorithm as the skills CLI's computeSkillFolderHash, which writes computedHash:
// sha256 over each file's relative path then contents, sorted by path, skipping .git and node_modules.
const skillFolderHash = (dir: string): string => {
  const files: Array<{ content: Buffer; relativePath: string }> = [];
  const collect = (current: string) => {
    for (const entry of readdirSync(current, { withFileTypes: true })) {
      const fullPath = path.join(current, entry.name);
      if (entry.isDirectory()) {
        if (entry.name !== '.git' && entry.name !== 'node_modules') {
          collect(fullPath);
        }
      } else if (entry.isFile()) {
        files.push({
          content: readFileSync(fullPath),
          relativePath: path.relative(dir, fullPath).split(path.sep).join('/'),
        });
      }
    }
  };
  collect(dir);
  files.sort((a, b) => a.relativePath.localeCompare(b.relativePath));
  const hash = createHash('sha256');
  for (const file of files) {
    hash.update(file.relativePath);
    hash.update(file.content);
  }
  return hash.digest('hex');
};

let warnings = 0;
const warn = (message: string) => {
  warnings += 1;
  process.stderr.write(`skills-check: ${message}\n`);
};

const versions = installedVersions(Object.keys(map.deps));

for (const [dep, entry] of Object.entries(map.deps)) {
  const version = versions.get(dep);
  if (version == null) {
    warn(
      `'${dep}' is mapped in skills.versions.json but not installed — remove it or reinstall the dep.`,
    );
    continue;
  }
  const major = Number(version.split('.')[0]);
  if (entry.source == null) {
    continue;
  }
  if (major !== entry.checkedMajor) {
    warn(
      `'${dep}' is at v${version} but skills were last checked against major ${entry.checkedMajor} — run 'npx skills update', re-verify, and bump checkedMajor.`,
    );
  }
  for (const skill of entry.skills) {
    if (!existsSync(path.join(skillsDir, skill))) {
      warn(
        `skill '${skill}' for '${dep}' missing from .claude/skills — run 'npx skills add ${entry.source}'.`,
      );
    }
  }
}

for (const [skill, { computedHash, source }] of Object.entries(lock.skills)) {
  const dir = path.join(skillsDir, skill);
  if (!existsSync(dir)) {
    warn(
      `skill '${skill}' is in skills-lock.json but missing from .claude/skills: run 'npx skills add ${source} --skill ${skill}'.`,
    );
    continue;
  }
  const hash = skillFolderHash(dir);
  if (hash !== computedHash) {
    warn(
      `skill '${skill}' does not match its skills-lock.json computedHash (files hash to ${hash}): reinstall with 'npx skills add ${source} --skill ${skill}', or record the new hash if the edit is intended.`,
    );
  }
}

if (warnings === 0) {
  process.stdout.write(
    'skills-check: all mapped skills present, majors match, and skills-lock.json hashes match.\n',
  );
} else if (strict) {
  process.exit(1);
}
