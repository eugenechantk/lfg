export type JobDecision={notify:boolean;message:string;stop:boolean};
export function jobResultInstructions(runID:string){
 return `This is a scheduled execution, not a request to create another schedule. Follow the saved job instructions using available tools. The host owns recurrence. Report the actual result. Notify only when the instructions ask for attention; an unchanged condition normally needs no alert. Do not treat a failed check as an unchanged condition. Never claim success without evidence. Finish with exactly one unquoted block: <lfg_job_result>{"run_id":"${runID}","notify":true,"message":"A concise notification message, or empty when notify is false","stop":false}</lfg_job_result>. Set stop=true only when the instructions say this job is finished. Do not put the block in a code fence. All three fields notify, message and stop are required.`;
}
export function parseJobResult(text:string,runID:string):{report:string;decision:JobDecision}{
 const matches=[...text.matchAll(/<lfg_job_result>([\s\S]*?)<\/lfg_job_result>/g)];
 if(matches.length!==1)throw Error('The job did not report one verified notification decision.');
 const m=matches[0]!,prefix=text.slice(0,m.index),suffix=text.slice(m.index!+m[0].length);
 let fence:string|undefined;
 for(const line of prefix.split('\n')){const mark=line.match(/^ {0,3}(`{3,}|~{3,})/)?.[1];if(mark){if(!fence)fence=mark;else if(mark[0]===fence[0]&&mark.length>=fence.length)fence=undefined;}}
 if(suffix.replace(/\s*<oai-mem-citation>[\s\S]*?<\/oai-mem-citation>\s*$/,'').trim()||fence||!prefix.endsWith('\n'))throw Error('The job result must finish the response outside an example.');
 let d:any;try{d=JSON.parse(m[1]!);}catch{throw Error('The job returned an invalid result.');}
 if(d.run_id!==runID||typeof d.notify!=='boolean'||typeof d.stop!=='boolean'||typeof d.message!=='string'||d.message.length>1000||(d.notify&&!d.message.trim()))throw Error('The job returned an invalid notification decision.');
 const report=prefix.trim();if(!report)throw Error('The job returned no report.');
 return {report,decision:{notify:d.notify,message:d.message.trim(),stop:d.stop}};
}
