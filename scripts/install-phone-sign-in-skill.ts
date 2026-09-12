import {readFileSync,existsSync,mkdirSync,writeFileSync,lstatSync,readlinkSync,symlinkSync} from 'node:fs';
import {join,resolve,dirname} from 'node:path';
import {homedir} from 'node:os';
const repo=resolve(process.argv[2] || join(import.meta.dir,'..'));
if(!existsSync(join(repo,'src/cli.ts'))) throw Error('Choose an LFG repository.');
const canonical=join(homedir(),'.claude/skills/request-phone-sign-in');
const codex=join(homedir(),'.codex/skills/request-phone-sign-in');
const file=join(canonical,'SKILL.md');
const marker='<!-- Managed by LFG phone-sign-in skill installer. -->';
if(existsSync(file) && !readFileSync(file,'utf8').includes(marker)) throw Error('Existing skill is not managed by this installer. Inspect it before replacing it.');
try {
 const stat=lstatSync(codex);
 if(!stat.isSymbolicLink() || resolve(dirname(codex),readlinkSync(codex))!==canonical) throw Error('Existing Codex skill points elsewhere. Inspect it before replacing it.');
} catch(e:any) { if(e.code!=='ENOENT') throw e; }
let text=readFileSync(join(import.meta.dir,'../integrations/phone-sign-in/SKILL.md'),'utf8');
text=text.replaceAll('__LFG_CLI__',join(repo,'src/cli.ts')).replaceAll('__LFG_REPO__',repo);
mkdirSync(canonical,{recursive:true});writeFileSync(file,text+'\n'+marker+'\n');
mkdirSync(dirname(codex),{recursive:true});if(!existsSync(codex)) symlinkSync(canonical,codex);
console.log('Installed request-phone-sign-in for Claude and Codex.');
