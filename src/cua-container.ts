import { readFile, realpath, stat } from 'node:fs/promises';
import { randomBytes } from 'node:crypto';
import type { CuaTools } from './cua-mcp';

export type ProMount = { source:string; target:string; readOnly:boolean };
export type CuaProfile = { image:string; mounts:ProMount[]; codexAuthSource?:string; codexModel?:string };
export type ContainerSpace = { id:string; containerName:string; guestCodexAuth:boolean; sharedPaths:{path:string;readOnly:boolean}[] };
type Run = (args:string[],options?:{env?:Record<string,string>;input?:string})=>Promise<string>;

export function validateProfile(value:any):CuaProfile {
 if(!value||typeof value.image!=='string'||!/^[a-zA-Z0-9][a-zA-Z0-9_./:@-]*$/.test(value.image))throw Error('Set a valid Cua image in the host profile');
 if(!Array.isArray(value.mounts))throw Error('Set mounts to an array in the host profile');
 const targets=new Set<string>();
 for(const m of value.mounts){
  if(typeof m.source!=='string'||!m.source.startsWith('/')||m.source.includes(',')||typeof m.target!=='string'||!/^\/pro\/[a-zA-Z0-9_-]+$/.test(m.target)||typeof m.readOnly!=='boolean'||targets.has(m.target))throw Error('Each shared folder needs an absolute source, a unique /pro/name target, and explicit readOnly');
  targets.add(m.target);
 }
 if(value.codexAuthSource!==undefined&&(typeof value.codexAuthSource!=='string'||!value.codexAuthSource.startsWith('/')))throw Error('Codex auth source must be an absolute host path');
 if(value.codexModel!==undefined&&(typeof value.codexModel!=='string'||!value.codexModel.trim()))throw Error('Set a valid Codex model');
 return {image:value.image,mounts:value.mounts,codexAuthSource:value.codexAuthSource,codexModel:value.codexModel};
}

export class CuaContainers {
 constructor(readonly profile:CuaProfile,private cua:CuaTools,private run:Run=async(args,options={})=>{
  const executable=process.env.LFG_DOCKER_BIN||Bun.which('docker')||'/Applications/Docker.app/Contents/Resources/bin/docker';
  const child=Bun.spawn([executable,...args],{stdin:options.input===undefined?'ignore':'pipe',stdout:'pipe',stderr:'pipe',env:{...process.env,...options.env}});
  if(options.input!==undefined){(child.stdin as any).write(options.input);(child.stdin as any).end();}
  const [output,error,code]=await Promise.all([new Response(child.stdout).text(),new Response(child.stderr).text(),child.exited]);
  if(code!==0)throw Error('Docker operation failed: '+error.slice(0,500));return output;
 }){}
 async create(name:string):Promise<ContainerSpace>{
  const args=['run','--detach','--name',name,'--label','ai.lfg.managed=true','--publish','127.0.0.1::3211','--env','CUA_ENV_TOKEN'];
  for(const mount of this.profile.mounts){
   const source=await realpath(mount.source);
   if(source.includes(','))throw Error('Shared folder paths cannot contain commas');
   if(!(await stat(source)).isDirectory())throw Error('Shared source must be a folder');
   args.push('--mount',`type=bind,source=${source},target=${mount.target}${mount.readOnly?',readonly':''}`);
  }
  // Validate and read credentials before creating a container; never bake them
  // into layers, pass them in command arguments, or return them to the app.
  let auth=this.profile.codexAuthSource?await readFile(this.profile.codexAuthSource,'utf8'):undefined;
  if(auth){const value=JSON.parse(auth);if(!value.tokens&&!value.OPENAI_API_KEY)throw Error('Codex sign-in is unavailable on this host');
   // A test Space can use the current access token without competing with
   // the host for refresh-token rotation. Durable login is per Space.
   if(value.tokens)value.tokens.refresh_token='';auth=JSON.stringify(value);}
  const token=randomBytes(32).toString('hex');
  await this.run([...args,this.profile.image],{env:{CUA_ENV_TOKEN:token}});
  if(auth)await this.run(['exec','-i','--user','cua',name,'sh','-c','umask 077; mkdir -p /home/cua/.codex; cat > /home/cua/.codex/auth.json'],{input:auth});
  const info=JSON.parse(await this.run(['inspect',name]))[0];
  const port=info.NetworkSettings?.Ports?.['3211/tcp']?.find((p:any)=>p.HostIp==='127.0.0.1')?.HostPort;
  if(!/^\d+$/.test(port))throw Error('Docker did not expose the Space on loopback');
  let result:any,last:unknown;
  for(let attempt=0;attempt<40;attempt++){
   try{result=await this.cua.call('add_space',{url:`http://127.0.0.1:${port}`,token,name});break;}
   catch(error){last=error;await Bun.sleep(500);}
  }
  const space=result?.result??result;
  if(!space?.id)throw Error('Space did not become ready. Its container was retained for inspection. '+String(last instanceof Error?last.message:'').replaceAll(token,'[redacted]'));
  return {id:space.id,containerName:name,guestCodexAuth:!!auth,sharedPaths:this.profile.mounts.map(m=>({path:m.target,readOnly:m.readOnly}))};
 }
 async state(name:string):Promise<string>{
  const data=JSON.parse(await this.run(['inspect',name]))[0].State;
  return data.Paused?'suspended':data.Running?'running':'stopped';
 }
 async power(name:string,action:'start'|'stop'){
  const state=await this.state(name);
  if(action==='stop'&&state==='running')await this.run(['pause',name]);
  if(action==='start'&&state==='suspended')await this.run(['unpause',name]);
  if(action==='start'&&state==='stopped')await this.run(['start',name]);
 }
}

export async function loadCuaContainers(cua:CuaTools):Promise<CuaContainers|undefined>{
 const path=process.env.LFG_CUA_PROFILE;if(!path)return;
 return new CuaContainers(validateProfile(JSON.parse(await readFile(path,'utf8'))),cua);
}
