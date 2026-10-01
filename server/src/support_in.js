// Postfix runs this for every letter to support@ (a pipe in master.cf, as the meltiew user):
//   meltiew-support unix - n n - - pipe flags=R user=meltiew
//     argv=/opt/meltiew-node/bin/node /opt/meltiew/src/support_in.js /var/lib/meltiew/support/in
// It only drops the raw letter into that folder; the running server files it (support.js).
// Exit code 75 asks Postfix to try again later.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const dir = process.argv[2] || '/var/lib/meltiew/support/in';
try {
  const chunks = [];
  for await (const c of process.stdin) chunks.push(c);
  fs.mkdirSync(dir, { recursive: true });
  const name = `${Date.now()}-${crypto.randomBytes(6).toString('hex')}`;
  // Written aside and renamed: the server never sees half a letter.
  fs.writeFileSync(path.join(dir, name + '.tmp'), Buffer.concat(chunks));
  fs.renameSync(path.join(dir, name + '.tmp'), path.join(dir, name + '.eml'));
} catch (err) {
  console.error('support_in:', err.message);
  process.exit(75);
}
