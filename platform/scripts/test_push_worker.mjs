import vm from 'node:vm';
import fs from 'node:fs';
import assert from 'node:assert/strict';
const script=fs.readFileSync(new URL('../client/web/firebase-messaging-sw.js', import.meta.url),'utf8');
const id='11111111-2222-3333-4444-555555555555';
for (const existing of [false,true]) {
  let handler, navigated, opened, focused=false, stopped=false, waiting;
  const self={location:{origin:'https://members.example.org'},addEventListener:(name,fn)=>{handler=fn;},clients:{
    matchAll:async()=>existing?[{url:'https://members.example.org/profile',navigate:async(url)=>{navigated=url;return {focus:async()=>{focused=true;}};}},{url:'https://evil.example/'}]:[],
    openWindow:async(url)=>{opened=url;}
  }};
  vm.runInNewContext(script,{self,URL,importScripts:()=>{},encodeURIComponent});
  handler({notification:{data:{FCM_MSG:{data:{notification_id:id},fcmOptions:{link:'https://evil.example'}}},close:()=>{}},stopImmediatePropagation:()=>{stopped=true;},waitUntil:p=>{waiting=p;}});
  await waiting;assert(stopped);
  assert.equal(existing?navigated:opened,'https://members.example.org/?notification='+id);
  if(existing)assert(focused);
  stopped=false;handler({notification:{data:{FCM_MSG:{data:{notification_id:'https://evil.example'}}}},stopImmediatePropagation:()=>{stopped=true;}});assert(!stopped);
}
console.log('Web push clicks: existing tab, new tab and unsafe payload tests passed');
