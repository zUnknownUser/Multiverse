import { readFile, mkdir, writeFile } from 'node:fs/promises';

const bundles = {
  'multiverse-7f87c': 'com.nexussoft.multiverse',
  'multiverse-staging-7f87c': 'com.nexussoft.multiverse.staging',
};
const project = process.env.GCLOUD_PROJECT;
const bundle = bundles[project];
if (!bundle) throw new Error('Select the staging or production Firebase project explicitly.');
const association = JSON.parse(await readFile(new URL('../hosting/.well-known/apple-app-site-association', import.meta.url), 'utf8'));
association.applinks.details[0].appIDs = ['5RS2AA677K.' + bundle];
const directory = new URL('../.firebase/hosting/.well-known/', import.meta.url);
await mkdir(directory, { recursive: true });
await writeFile(new URL('apple-app-site-association', directory), JSON.stringify(association, null, 2) + '\n');
console.log('Prepared auth links for ' + project);
