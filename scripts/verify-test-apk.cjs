#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');
const PACKAGE = 'com.example.verdict.test';
const CERTIFICATE = 'a0f0813a621fdf1f65e2780f3ef8ace1421f849b3aa2e0ce61571c02b2c45378';

function assessApk(badging, certificates) {
  const failures = [];
  const pkg = /^package: name='([^']+)' versionCode='(\d+)' versionName='([^']*)'/m.exec(badging);
  const digests = [...certificates.matchAll(/^Signer #\d+ certificate SHA-256 digest: ([\da-f:]+)\s*$/gim)]
    .map(match => match[1].replaceAll(':', '').toLowerCase());
  const versionCode = pkg ? Number(pkg[2]) : null;
  if (pkg?.[1] !== PACKAGE) failures.push('Expected test package com.example.verdict.test.');
  if (!Number.isSafeInteger(versionCode) || versionCode <= 4004) failures.push('Update versionCode must exceed installed APK 4004.');
  if (digests.length !== 1 || digests[0] !== CERTIFICATE) failures.push('Expected the single original APK 4004 signing certificate.');
  return { ok: failures.length === 0, package: pkg?.[1] ?? null, versionCode,
    versionName: pkg?.[3] ?? null, certificateSha256: digests, failures };
}

function verifyApk(apk, buildTools, run = execFileSync) {
  // Read one snapshot for hashing, then reject replacement while SDK tools inspect it.
  const before = fs.readFileSync(apk);
  const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
  const sha256 = digest(before);
  const options = { encoding: 'utf8', maxBuffer: 8 * 1024 * 1024, timeout: 120000, stdio: ['ignore', 'pipe', 'pipe'] };
  const certificates = run(path.join(buildTools, 'apksigner'), ['verify', '--verbose', '--print-certs', apk], options);
  const badging = run(path.join(buildTools, 'aapt'), ['dump', 'badging', apk], options);
  const report = assessApk(badging, certificates);
  if (digest(fs.readFileSync(apk)) !== sha256) {
    report.failures.push('APK changed during verification.');
    report.ok = false;
  }
  return { ...report, bytes: before.length, sha256,
    unchecked: ['Installed device identity and data preservation', 'Backend compatibility', 'Physical-device and iOS acceptance'] };
}
module.exports = { assessApk, verifyApk };
if (require.main === module) {
  try {
    if (process.argv.length !== 4) throw new Error('Usage: node scripts/verify-test-apk.cjs APK_PATH ANDROID_BUILD_TOOLS_DIR');
    const report = verifyApk(path.resolve(process.argv[2]), path.resolve(process.argv[3]));
    process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
    process.exitCode = report.ok ? 0 : 1;
  } catch {
    // SDK diagnostics can include machine-specific information; fail closed without dumping them.
    process.stderr.write('APK verification could not complete. Check arguments, APK, Java and Android build tools. No release approved.\n');
    process.exitCode = 1;
  }
}
