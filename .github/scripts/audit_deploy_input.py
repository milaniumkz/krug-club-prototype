"""Audit secret delivery without logging its value or contacting the VPS."""
import hmac,os,re,socket,threading
import paramiko
value=os.environ.get('DEPLOY_SSH_PASSWORD','')
checks={
 'secret_present':bool(value),
 'surrounding_whitespace':value!=value.strip(),
 'line_breaks':'\n' in value or '\r' in value,
 'outer_quotes':len(value)>1 and value[0]==value[-1] and value[0] in ('"',"'"),
 'markdown_or_mailto':'mailto:' in value or '](' in value,
 'looks_like_variable_assignment':bool(re.match(r'^(?:export\s+)?(?:DEPLOY_SSH_PASSWORD|SSHPASS|password)\s*=',value)),
 'nul_character':'\0' in value,
}
for name,result in checks.items():print(name+': '+str(result),flush=True)
if not value:raise SystemExit('Repository secret is empty or unavailable')
# Verify actual Paramiko serialization with the exact secret in an in-memory local SSH server.
key=paramiko.RSAKey.generate(2048);listener=socket.socket();listener.bind(('127.0.0.1',0));listener.listen(1);matched=[]
class Server(paramiko.ServerInterface):
 def get_allowed_auths(self,username):return 'password'
 def check_auth_password(self,username,password):
  ok=username=='root' and hmac.compare_digest(password.encode(),value.encode());matched.append(ok)
  return paramiko.AUTH_SUCCESSFUL if ok else paramiko.AUTH_FAILED
server_transport=[]
def serve():
 conn,_=listener.accept();t=paramiko.Transport(conn);server_transport.append(t);t.add_server_key(key);t.start_server(server=Server());t.join(8)
thread=threading.Thread(target=serve,daemon=True);thread.start()
client=paramiko.Transport(socket.create_connection(listener.getsockname()));client.start_client(timeout=10);client.auth_password('root',value);assert client.is_authenticated() and matched==[True]
client.close()
for t in server_transport:t.close()
listener.close()
print('Exact secret bytes delivered through real SSH password protocol: PASS')
print('No production SSH login was attempted; no secret value, digest or length was printed.')
