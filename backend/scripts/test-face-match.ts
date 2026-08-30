import fs from 'fs';
import path from 'path';
import { compareFaces } from '../src/lib/faceMatch';

async function main() {
  const dir = path.join(__dirname, '../node_modules/@vladmandic/face-api/demo');
  const sample1 = fs.readFileSync(path.join(dir, 'sample1.jpg'));
  const sample2 = fs.readFileSync(path.join(dir, 'sample2.jpg'));

  console.log('self-compare (should be ~100):', await compareFaces(sample1, sample1));
  console.log('cross-compare (should be low):', await compareFaces(sample1, sample2));
}

main().catch((err) => {
  console.error('TEST FAILED:', err);
  process.exit(1);
});
