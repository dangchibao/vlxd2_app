import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../',import.meta.url));
if(!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST)throw Error('Both localhost emulators are required');
const rules=spawnSync(process.execPath,['--test','security/rules.test.mjs'],{cwd:root,stdio:'inherit'});
if(rules.status!==0)process.exit(rules.status??1);
// All command arguments below are constants owned by this repository.
const dart=spawnSync(process.platform==='win32'?'flutter.bat':'flutter',['test','--dart-define=BAYHAI_EMULATOR_TESTS=true','test/emulator_rest_test.dart'],{cwd:root,stdio:'inherit',shell:process.platform==='win32'});
process.exit(dart.status??1);
