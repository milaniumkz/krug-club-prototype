import base64,hashlib,os,secrets,socket
import paramiko
password=os.environ.pop('DEPLOY_SSH_PASSWORD','')
t=paramiko.Transport(socket.create_connection(('109.235.119.144',22),timeout=15));t.get_security_options().key_types=('ssh-ed25519',);t.start_client(timeout=15)
fp='SHA256:'+base64.b64encode(hashlib.sha256(t.get_remote_server_key().asbytes()).digest()).decode().rstrip('=')
if not secrets.compare_digest(fp,'SHA256:Bt3HkaktjLmWe4tB1pOK9b8gOnHuxp+tvp1hhEDtxp8'):raise SystemExit('Host identity mismatch')
t.auth_password('root',password);password=None
print('VERIFIED SSH LOGIN: SUCCESS',flush=True)
command='''uname -a
free -h
df -h /
ps -eo pid,comm | tail -35
if command -v docker >/dev/null; then
 docker ps --format '{{.Names}} {{.Status}}'
 docker stats --no-stream --format '{{.Name}} {{.CPUPerc}} {{.MemUsage}}'
 for name in qazaqmetal-api-1 qazaqmetal-edge-1; do
  docker logs --tail 25 "$name" 2>&1 || true
 done
fi'''
ch=t.open_session();ch.exec_command(command)
print(ch.makefile('r').read().decode());print(ch.makefile_stderr('r').read().decode());print('Inspection exit:',ch.recv_exit_status());t.close()
