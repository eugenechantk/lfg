import {test,expect} from 'bun:test';
import {CuaContainers,validateProfile} from './cua-container';
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

test('power operations are idempotent and preserve the container',async()=>{
 let paused=false;const commands:string[][]=[];
 const containers=new CuaContainers({image:'test',mounts:[]},{call:async()=>({})},async(args)=>{commands.push(args);if(args[0]==='inspect')return JSON.stringify([{State:{Paused:paused,Running:true}}]);if(args[0]==='pause')paused=true;if(args[0]==='unpause')paused=false;return '';});
 await containers.power('test','stop');await containers.power('test','stop');
 expect(commands.filter(c=>c[0]==='pause')).toHaveLength(1);
 expect(await containers.state('test')).toBe('suspended');
 await containers.power('test','start');expect(await containers.state('test')).toBe('running');
});
