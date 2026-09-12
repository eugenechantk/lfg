import { readSignInToken } from '../browser-sign-in.ts';
const help = `Usage:
  lfg browser-sign-in sessions
  lfg browser-sign-in targets
  lfg browser-sign-in request --session <session-id> --target <browser-id> --url <https-url> [--no-wait]
  lfg browser-sign-in status <request-id>
  lfg browser-sign-in wait <request-id>
  lfg browser-sign-in cancel <request-id>

Use the exact browser the agent already controls. request waits for the iPhone by default.
LFG_BROWSER_SIGN_IN_URL may point to a different local test host. No cookies or passwords are printed.`;
export async function cmdBrowserSignIn(args: string[]) {
  const [command, ...rest] = args;
  if (!command || ['help','--help','-h'].includes(command)) { console.log(help); return; }
  const base = new URL(process.env.LFG_BROWSER_SIGN_IN_URL || 'http://127.0.0.1:8766');
  if (!['127.0.0.1','localhost','[::1]'].includes(base.hostname) || !['http:','https:'].includes(base.protocol) || base.username || base.password)
    throw Error('Agent sign-in requests must use a local LFG host.');
  async function api(path: string, body?: unknown) {
    const token = readSignInToken();
    const response = await fetch(new URL(path.startsWith('/api/') ? path : '/api/browser-sign-in/'+path,base), {
      method:body===undefined?'GET':'POST', redirect:'error', signal:AbortSignal.timeout(10_000),
      headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},
      body:body===undefined?undefined:JSON.stringify(body)
    });
    if (!response.ok) throw Error(response.status===404?'Sign-in request is unavailable. The host may have restarted.':'Sign-in command failed. Check the session, browser, and local connection token.');
    return response.json() as Promise<any>;
  }
  async function wait(id: string) {
    const deadline=Date.now()+16*60_000;
    while (Date.now()<deadline) {
      const r=await api('requests/'+id);
      if (!['waiting','delivering'].includes(r.state)) { console.log(JSON.stringify(r)); return; }
      await Bun.sleep(1500);
    }
    throw Error('Stopped waiting. Check request status before retrying; no cookie transfer was replayed.');
  }
  if (command==='sessions') {
    const data=await api('/api/sessions');
    console.log(JSON.stringify({sessions:(data.sessions||[]).map((s:any)=>({sessionId:s.sessionId,title:s.title,cwd:s.cwd,agent:s.agent,tmuxTarget:s.tmuxTarget}))}));return;
  }
  if (command==='targets') { console.log(JSON.stringify(await api('targets'))); return; }
  if (command==='request') {
    const opts:Record<string,string>={};let noWait=false;
    for(let i=0;i<rest.length;i++) {
      const arg=rest[i]!;
      if(arg==='--no-wait') {noWait=true;continue;}
      if(!['--session','--target','--url'].includes(arg) || !rest[i+1]) throw Error(help);
      opts[arg.slice(2)]=rest[++i]!;
    }
    if(!opts.session || !opts.target || !opts.url) throw Error(help);
    const r=await api('requests',{sessionId:opts.session,targetId:opts.target,url:opts.url});
    console.log(JSON.stringify({event:'phone-sign-in-requested',...r}));
    if(!noWait) await wait(r.id);
    return;
  }
  const id=rest[0];
  if(!id || !/^[a-f0-9-]{36}$/i.test(id)) throw Error(help);
  if(command==='wait') return wait(id);
  if(command==='status') {console.log(JSON.stringify(await api('requests/'+id)));return;}
  if(command==='cancel') {console.log(JSON.stringify(await api('requests/'+id+'/cancel',{})));return;}
  throw Error(help);
}
