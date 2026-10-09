#!/usr/bin/env python3
import pathlib,subprocess,ssl,socket,threading,tempfile,hashlib,os
root=pathlib.Path(__file__).resolve().parents[1]
java=str(pathlib.Path(os.environ['JAVA_HOME'])/'bin/java')
javac=str(pathlib.Path(os.environ['JAVA_HOME'])/'bin/javac')
cp=str(root/'app/libs/*')+':'+str(root/'tests/classes')
(root/'tests/classes').mkdir(exist_ok=True)
subprocess.run([javac,'-cp',str(root/'app/libs/*'),'-d',str(root/'tests/classes'),str(root/'app/src/main/java/net/local/vizioremote/TvTransport.java'),str(root/'app/src/main/java/net/local/vizioremote/SettingPolicy.java'),str(root/'tests/TransportCheck.java')],check=True)
assert subprocess.check_output([java,'-cp',cp,'net.local.vizioremote.TransportCheck','policy'],text=True).strip()=='POLICY_OK'
with tempfile.TemporaryDirectory() as tmp:
 cert=pathlib.Path(tmp)/'cert.pem';key=pathlib.Path(tmp)/'key.pem'
 subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(key),'-out',str(cert),'-days','1','-subj','/CN=TestTV'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 der=ssl.PEM_cert_to_DER_cert(cert.read_text());pin=hashlib.sha256(der).hexdigest().upper()
 def request(saved,legacy=True,chunk=False):
  ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);ctx.minimum_version=ssl.TLSVersion.TLSv1;ctx.maximum_version=ssl.TLSVersion.TLSv1;ctx.set_ciphers('AES128-SHA:@SECLEVEL=0');ctx.load_cert_chain(cert,key)
  listener=socket.socket();listener.bind(('127.0.0.1',0));listener.listen();port=listener.getsockname()[1];seen=[]
  def server():
   try:
    raw,_=listener.accept();raw.settimeout(10)
    with ctx.wrap_socket(raw,server_side=True) as conn:
     data=b''
     while b'\r\n\r\n' not in data:data+=conn.recv(4096)
     head,body=data.split(b'\r\n\r\n',1)
     count=int(next(x.split(b':',1)[1] for x in head.split(b'\r\n') if x.lower().startswith(b'content-length:')))
     while len(body)<count:body+=conn.recv(4096)
     assert b'AUTH: ABC123' in head and body==b'{"name":"T\xc3\xa9l\xc3\xa9"}'
     seen.append(True)
     payload=b'{"STATUS":{"RESULT":"SUCCESS"}}'
     wire=(b'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n'+format(len(payload),'x').encode()+b'\r\n'+payload+b'\r\n0\r\n\r\n') if chunk else b'HTTP/1.1 200 OK\r\nContent-Length: '+str(len(payload)).encode()+b'\r\n\r\n'+payload
     conn.sendall(wire)
   except (ssl.SSLError,OSError):pass
   finally:listener.close()
  thread=threading.Thread(target=server);thread.start()
  proc=subprocess.run([java,'-cp',cp,'net.local.vizioremote.TransportCheck',str(port),saved,str(legacy).lower()],capture_output=True,text=True,timeout=20);thread.join(12)
  return proc,seen
 p,seen=request('');assert p.returncode==0 and p.stdout.strip()=='APPROVAL:'+pin and not seen
 p,seen=request(pin);assert p.returncode==0 and 'SUCCESS' in p.stdout and seen
 p,seen=request(pin,chunk=True);assert p.returncode==0 and 'SUCCESS' in p.stdout and seen
 p,seen=request('0'*64);assert p.returncode!=0 and not seen
 p,seen=request(pin,legacy=False);assert p.returncode!=0 and not seen
print('PASS: private-address/type policy; certificate approval; TLS 1.0 authenticated UTF-8 PUT; chunked response; changed-certificate rejection; modern-only rejection of TLS 1.0')
