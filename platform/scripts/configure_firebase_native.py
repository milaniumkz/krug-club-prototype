"""Generate native Firebase boot resources from public client metadata (no private keys)."""
import json,plistlib
from pathlib import Path
from xml.sax.saxutils import escape

def configure(client: Path, role='member'):
    path=client/'firebase.client.json'
    if not path.exists():return
    config=json.loads(path.read_text())[role];d=config['android'];i=config['ios']
    values={'google_app_id':d['appId'],'gcm_defaultSenderId':d['messagingSenderId'],'google_api_key':d['apiKey'],'project_id':d['projectId'],'google_storage_bucket':d['storageBucket']}
    xml=client/'android/app/src/main/res/values/firebase.xml';xml.parent.mkdir(parents=True,exist_ok=True)
    xml.write_text('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'+''.join('  <string name="'+k+'" translatable="false">'+escape(v)+'</string>\n' for k,v in values.items())+'</resources>\n')
    plist={'API_KEY':i['apiKey'],'GOOGLE_APP_ID':i['appId'],'GCM_SENDER_ID':i['messagingSenderId'],'PROJECT_ID':i['projectId'],'STORAGE_BUCKET':i['storageBucket'],'BUNDLE_ID':i['iosBundleId'],'PLIST_VERSION':'1','IS_GCM_ENABLED':True,'IS_ANALYTICS_ENABLED':False}
    with (client/'ios/Runner/GoogleService-Info.plist').open('wb') as f:plistlib.dump(plist,f)

if __name__=='__main__':configure(Path(__file__).resolve().parents[1]/'client')
