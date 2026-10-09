#!/usr/bin/env python3
"""Exercise the Linux script's actual functions against an isolated TLS 1.0 TV."""
import pathlib, subprocess, tempfile, socket, ssl, threading, json, os
root=pathlib.Path(__file__).resolve().parents[1]
script=(root/'linux/vizio-tui.sh').read_text()
functions=script[script.index('ui() {'):script.index('[[ -n $token ]] || connect')]
requests=[]
with tempfile.TemporaryDirectory() as directory:
 d=pathlib.Path(directory)
 contexts=[]
 for number in (1,2):
  cert=d/f'cert{number}.pem'; key=d/f'key{number}.pem'
  subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(key),'-out',str(cert),'-days','1','-subj','/CN=TestTV'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
  ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
  ctx.minimum_version=ctx.maximum_version=ssl.TLSVersion.TLSv1
  ctx.set_ciphers('AES128-SHA:@SECLEVEL=0');ctx.load_cert_chain(cert,key);contexts.append(ctx)
 # Renewed certificate with the same key must retain trust.
 cert=d/'renewed.pem'
 subprocess.run(['openssl','req','-x509','-new','-key',str(d/'key1.pem'),'-out',str(cert),'-days','1','-subj','/CN=RenewedTestTV'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);ctx.minimum_version=ctx.maximum_version=ssl.TLSVersion.TLSv1
 ctx.set_ciphers('AES128-SHA:@SECLEVEL=0');ctx.load_cert_chain(cert,d/'key1.pem');contexts.append(ctx)
 context=[contexts[0]]
 listener=socket.socket();listener.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1);listener.bind(('127.0.0.1',9000));listener.listen();listener.settimeout(.2)
 stopped=threading.Event()
 def serve():
  while not stopped.is_set():
   try:raw,_=listener.accept()
   except socket.timeout:continue
   except OSError:return
   raw.settimeout(3)
   try:
    with context[0].wrap_socket(raw,server_side=True) as conn:
     data=b''
     while b'\r\n\r\n' not in data:
      part=conn.recv(4096)
      if not part:break
      data+=part
     if data:
      requests.append(data)
      payload=b'{"STATUS":{"RESULT":"SUCCESS"}}'
      conn.sendall(b'HTTP/1.1 200 OK\r\nContent-Length: '+str(len(payload)).encode()+b'\r\nConnection: close\r\n\r\n'+payload)
   except (OSError,ssl.SSLError):raw.close()
 thread=threading.Thread(target=serve,daemon=True);thread.start()
 cnf=d/'openssl.cnf';cnf.write_text(script.split('cat > "$work/openssl.cnf" <<\'EOF\'\n',1)[1].split('\nEOF',1)[0])
 harness=d/'harness.sh'
 harness.write_text('set -uo pipefail\numask 077\nwork='+str(d)+'\nconfig_dir='+str(d/'config')+'\ntrust_file=$config_dir/trusted-keys.json\nhost=127.0.0.1\nport=9000\ntoken=TESTTOKEN\n'+functions+'\nui() { if [[ $1 == --yesno ]]; then printf "TRUST_PROMPT\\n" >&2; [[ ${APPROVE:-yes} == yes ]]; else printf "%s\\n" "$*" >&2; fi; }\napi GET test\n')
 def invoke(approval='yes'):
  return subprocess.run(['bash',str(harness)],capture_output=True,text=True,timeout=25,env={**os.environ,'APPROVE':approval})
 try:
  result=invoke('no');assert result.returncode!=0 and not requests and not (d/'config/trusted-keys.json').exists(),result
  result=invoke();assert result.returncode==0 and json.loads(result.stdout)['STATUS']['RESULT']=='SUCCESS' and 'TRUST_PROMPT' in result.stderr,result
  trust=d/'config/trusted-keys.json';saved=trust.read_bytes();assert (trust.stat().st_mode&0o777)==0o600
  assert requests and b'AUTH: TESTTOKEN' in requests[-1]
  result=invoke();assert result.returncode==0 and 'TRUST_PROMPT' not in result.stderr and trust.read_bytes()==saved,result
  context[0]=contexts[2]
  result=invoke();assert result.returncode==0 and 'TRUST_PROMPT' not in result.stderr and trust.read_bytes()==saved,result
  before=len(requests);context[0]=contexts[1]
  result=invoke();assert result.returncode!=0 and len(requests)==before and trust.read_bytes()==saved and 'TRUST_PROMPT' not in result.stderr,result
  context[0]=contexts[0];trust.write_text('not json')
  result=invoke();assert result.returncode!=0 and len(requests)==before and 'Invalid trust file' in result.stderr,result
  print('PASS: declined trust sends no HTTP/token; first-use approval; pin saved mode 600; restart reuses pin; renewed certificate with same key accepted; changed key blocks HTTP/token without replacing pin; corrupt trust file fails closed')
 finally:
  stopped.set();listener.close();thread.join(4)
