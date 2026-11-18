import json,os,time,urllib.request,urllib.error
url='https://api.github.com/repos/'+os.environ['GITHUB_REPOSITORY']+'/contents/.github/deploy-key-ready.json?ref=main'
for _ in range(120):
 req=urllib.request.Request(url,headers={'Authorization':'Bearer '+os.environ['GITHUB_TOKEN'],'Accept':'application/vnd.github.raw+json','User-Agent':'QazaqMetal-authorized-key-deploy','Cache-Control':'no-cache'})
 try:
  with urllib.request.urlopen(req,timeout=20) as response:ready=json.load(response)
  if str(ready.get('run_id'))==os.environ['GITHUB_RUN_ID']:
   print('Owner confirmed public key installation. Continuing deployment.');break
 except urllib.error.HTTPError as error:
  if error.code!=404:raise
 time.sleep(10)
else:raise SystemExit('Timed out waiting for public key installation; server was not modified.')
