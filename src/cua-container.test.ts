import {test,expect} from 'bun:test';
import {CuaContainers,CuaContainerRuntime,validateProfile} from './cua-container';
import {mkdtemp,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

test('host profile validates explicit folder permissions and guest paths',()=>{
 expect(validateProfile({image:'lfg-cua-codex:1',mounts:[]}).image).toBe('lfg-cua-codex:1');
 for(const mounts of [[{source:'/tmp',target:'/home/cua',readOnly:false}],[{source:'/tmp',target:'/pro/data'}],[{source:'/tmp,secret',target:'/pro/data',readOnly:false}],[{source:'/tmp',target:'/pro/data',readOnly:true},{source:'/tmp',target:'/pro/data',readOnly:false}]])expect(()=>validateProfile({image:'safe',mounts})).toThrow();
});

test('provisioning binds loopback and keeps runtime credentials out of arguments and replies',async()=>{
 const root=await mkdtemp(join(tmpdir(),'lfg-profile-'));
 const auth=join(root,'auth.json');await writeFile(auth,JSON.stringify({auth_mode:'chatgpt',tokens:{access_token:'private-access',refresh_token:'host-refresh'}}));
 const calls:any[]=[];const commands:any[]=[];
 const containers=new CuaContainers({image:'lfg-cua-codex:1',mounts:[{source:root,target:'/pro/data',readOnly:true}],codexAuthSource:auth},{call:async(name,args)=>{calls.push({name,args});return {id:'direct:127.0.0.1:1234'};}},async(args,options)=>{
  commands.push({args,options});return args[0]==='inspect'?JSON.stringify([{NetworkSettings:{Ports:{'3211/tcp':[{HostIp:'127.0.0.1',HostPort:'1234'}]}}}]):'container-id';
 });
 const result=await containers.create('lfg-message-test');
 expect(commands[0].args).toContain('127.0.0.1::3211');
 expect(commands[0].args.join(' ')).toContain(',readonly');
 expect(commands[0].args.join(' ')).not.toContain(commands[0].options.env.CUA_ENV_TOKEN);
 expect(JSON.stringify(commands.map(c=>c.args))).not.toContain('private-access');
 expect(commands[1].options.input).toContain('private-access');
 expect(commands[1].options.input).not.toContain('host-refresh');
 expect(JSON.stringify(result)).not.toContain('private-access');
 expect(JSON.stringify(result)).not.toContain(root);
 expect(calls[0].args.token).toHaveLength(64);
});

test('power operations stop rather than pause, are idempotent and preserve the container',async()=>{
 let running=true;const commands:string[][]=[];
 const containers=new CuaContainerRuntime(async(args)=>{commands.push(args);if(args[0]==='inspect')return JSON.stringify([{State:{Paused:false,Running:running}}]);if(args[0]==='stop')running=false;if(args[0]==='start')running=true;return '';});
 await containers.power('test','stop');await containers.power('test','stop');
 expect(commands.filter(c=>c[0]==='stop')).toEqual([['stop','--time','10','test']]);
 expect(commands.some(c=>['pause','rm'].includes(c[0]))).toBe(false);
 expect(await containers.state('test')).toBe('stopped');
 await containers.power('test','start');expect(await containers.state('test')).toBe('running');
});

test('legacy paused containers stop without resuming agent execution',async()=>{
 let paused=true,running=true;const commands:string[][]=[];
 const runtime=new CuaContainerRuntime(async(args)=>{commands.push(args);if(args[0]==='inspect')return JSON.stringify([{State:{Paused:paused,Running:running}}]);if(args[0]==='kill'){paused=false;running=false;}return '';});
 await runtime.power('old','stop');
 expect(commands.some(c=>['unpause','pause','rm'].includes(c[0]))).toBe(false);
 expect(commands.filter(c=>c[0]==='kill')).toEqual([['kill','old']]);
});

test('an unconfirmed stop never reports success',async()=>{
 const runtime=new CuaContainerRuntime(async(args)=>args[0]==='inspect'?JSON.stringify([{State:{Paused:false,Running:true}}]):'');
 await expect(runtime.power('busy','stop')).rejects.toThrow('did not confirm');
});

test('failed provisioning stops the new container and retains its disk',async()=>{
 const root=await mkdtemp(join(tmpdir(),'lfg-setup-')),auth=join(root,'auth.json');
 await writeFile(auth,JSON.stringify({OPENAI_API_KEY:'test-only'}));
 let running=true;const commands:string[][]=[];
 const containers=new CuaContainers({image:'test',mounts:[],codexAuthSource:auth},{call:async()=>({})},async(args)=>{
  commands.push(args);if(args[0]==='exec')throw Error('auth setup failed');
  if(args[0]==='inspect')return JSON.stringify([{State:{Running:running,Paused:false}}]);
  if(args[0]==='stop')running=false;return 'new-container';
 });
 await expect(containers.create('lfg-message-setup')).rejects.toThrow('auth setup failed');
 expect(commands.some(c=>c[0]==='stop')).toBe(true);expect(commands.some(c=>c[0]==='rm')).toBe(false);
});

test('a restarted profile re-registers its changed loopback port without exposing credentials',async()=>{
 let running=false,port='1234';const registrations:any[]=[],commands:string[][]=[];
 const containers=new CuaContainers({image:'test',mounts:[]},{call:async(name,args)=>{registrations.push({name,args});return {id:'direct:127.0.0.1:'+port};}},async(args)=>{
  commands.push(args);if(args[0]==='start'){running=true;port='5678';}
  if(args[0]==='inspect')return JSON.stringify([{State:{Running:running,Paused:false},Config:{Env:['CUA_ENV_TOKEN=private-token']},NetworkSettings:{Ports:{'3211/tcp':[{HostIp:'127.0.0.1',HostPort:port}]}}}]);return '';
 });
 const id=await containers.resume('lfg-message-restart');
 expect(id).toBe('direct:127.0.0.1:5678');expect(id).not.toContain('private-token');
 expect(registrations[0].args.url).toBe('http://127.0.0.1:5678');expect(registrations[0].args.token).toBe('private-token');
 expect(JSON.stringify(commands)).not.toContain('private-token');
});

test('failed reconnection stops only the container started by this operation',async()=>{
 for(const wasRunning of [false,true]){
  let running=wasRunning;const commands:string[][]=[];
  const containers=new CuaContainers({image:'test',mounts:[]},{call:async()=>({})},async(args)=>{
   commands.push(args);if(args[0]==='start')running=true;if(args[0]==='stop')running=false;
   if(args[0]==='inspect')return JSON.stringify([{State:{Running:running,Paused:false},Config:{Env:[]},NetworkSettings:{Ports:{}}}]);return '';
  });
  await expect(containers.resume('lfg-message-restart')).rejects.toThrow('loopback');
  expect(commands.some(c=>c[0]==='stop')).toBe(!wasRunning);
 }
});
