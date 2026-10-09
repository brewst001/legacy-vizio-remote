#!/usr/bin/env python3
"""PowerShell/Java integration test. Windows DPAPI/ACLs require Windows tests."""
import os,pathlib,tempfile,subprocess,socket,ssl,threading,json
root=pathlib.Path(__file__).resolve().parents[1]
jdk=pathlib.Path(os.environ['JAVA_HOME']);pwsh=os.environ.get('PWSH','pwsh');requests=[];value=[14]
with tempfile.TemporaryDirectory() as temporary:
 d=pathlib.Path(temporary);contexts=[]
 for n in (1,2):
  cert=d/f'cert{n}.pem';key=d/f'key{n}.pem'
  subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(key),'-out',str(cert),'-days','1','-subj','/CN=TestTV'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
  ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);ctx.minimum_version=ctx.maximum_version=ssl.TLSVersion.TLSv1;ctx.set_ciphers('AES128-SHA:@SECLEVEL=0');ctx.load_cert_chain(cert,key);contexts.append(ctx)
 listener=socket.socket();listener.bind(('127.0.0.1',0));listener.listen();listener.settimeout(.2);port=listener.getsockname()[1];context=[contexts[0]];stop=threading.Event()
 def serve():
  while not stop.is_set():
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
     if not data:continue
     head,body=data.split(b'\r\n\r\n',1);length=int(next(x.split(b':',1)[1] for x in head.split(b'\r\n') if x.lower().startswith(b'content-length:')))
     while len(body)<length:body+=conn.recv(4096)
     requests.append((head,body));method,path,_=head.split(b'\r\n',1)[0].decode().split(' ')
     response={'STATUS':{'RESULT':'SUCCESS'},'ITEMS':[{'NAME':'Volume','CNAME':'volume','TYPE':'T_VALUE_V1','ENABLED':True,'VALUE':value[0],'HASHVAL':42,'MINIMUM':0,'MAXIMUM':100}]}
     if method=='PUT':
      payload=json.loads(body);assert payload['HASHVAL']==42 and payload['REQUEST']=='MODIFY' and isinstance(payload['VALUE'],(int,float));value[0]=payload['VALUE']
     payload=json.dumps(response).encode();conn.sendall(b'HTTP/1.1 200 OK\r\nContent-Length: '+str(len(payload)).encode()+b'\r\nConnection: close\r\n\r\n'+payload)
   except (ssl.SSLError,OSError):raw.close()
 thread=threading.Thread(target=serve,daemon=True);thread.start()
 # Test-only loopback access in a temporary helper. The shipped helper retains request() private-IP checks.
 cli=(root/'powershell/src/net/local/vizioremote/TransportCli.java').read_text().replace('TvTransport.request(', 'TvTransport.exchange(').replace('null:fields[7]);','null:fields[7],true);')
 source=d/'TransportCli.java';source.write_text(cli);classes=d/'classes';classes.mkdir()
 subprocess.run([str(jdk/'bin/javac'),'--release','8','-cp',str(root/'app/libs/*'),'-d',str(classes),str(root/'app/src/main/java/net/local/vizioremote/TvTransport.java'),str(source)],check=True)
 subprocess.run([str(jdk/'bin/jar'),'cf',str(d/'test.jar'),'-C',str(classes),'.'],check=True)
 def quote(s):return "'"+str(s).replace("'","''")+"'"
 base='''$ErrorActionPreference='Stop'
. SOURCE -LibraryOnly -JavaPath JAVA
$script:TvAddress='127.0.0.1';$script:ApiPort=PORT;$script:Token='TESTTOKEN'
$script:ClassPath=CLASSPATH
$script:ConfigDir=CONFIG;$script:TrustFile=Join-Path $script:ConfigDir 'trust.json'
$answers=New-Object 'System.Collections.Generic.Queue[string]'
function Read-Host {param($Prompt) if($answers.Count -eq 0){throw "Unexpected prompt: $Prompt"};return $answers.Dequeue()}
'''.replace('SOURCE',quote(root/'powershell/vizio-tui.ps1')).replace('JAVA',quote(jdk/'bin/java')).replace('PORT',str(port)).replace('CLASSPATH',quote(str(d/'test.jar')+os.pathsep+str(root/'app/libs/*'))).replace('CONFIG',quote(d/'config'))
 def run(code):
  script=d/'case.ps1';script.write_text(base+code);return subprocess.run([pwsh,'-NoProfile','-File',str(script)],capture_output=True,text=True,timeout=40)
 try:
  p=run("$answers.Enqueue('NO');try{Invoke-Tv GET '/test';exit 2}catch{Write-Output 'DECLINED'}")
  assert p.returncode==0 and 'DECLINED' in p.stdout and not requests,p
  p=run("$answers.Enqueue('TRUST');Invoke-Tv GET '/test'|Out-Null;Invoke-Tv GET '/test'|Out-Null;$answers.Enqueue('15');$answers.Enqueue('y');Edit-Setting '/test' 'volume';Write-Output 'GOOD'")
  assert p.returncode==0 and 'GOOD' in p.stdout and value[0]==15,p
  saved=(d/'config/trust.json').read_bytes();assert b'TESTTOKEN' not in saved
  assert requests and all(b'AUTH: TESTTOKEN' in head for head,_ in requests)
  assert (d/'config/trust.json').stat().st_mode&0o777==0o600
  before=len(requests);context[0]=contexts[1]
  load="$loadedPins=Get-Content $script:TrustFile -Raw|ConvertFrom-Json;foreach($p in $loadedPins.PSObject.Properties){$script:Pins[$p.Name]=$p.Value};"
  p=run(load+"try{Invoke-Tv GET '/test';exit 2}catch{Write-Output 'BLOCKED'}")
  assert p.returncode==0 and 'BLOCKED' in p.stdout and len(requests)==before and (d/'config/trust.json').read_bytes()==saved,p
  p=run("$script:TvAddress='8.8.8.8';try{Invoke-Tv GET '/test';exit 2}catch{Write-Output 'PRIVATE_ONLY'}")
  assert p.returncode==0 and 'PRIVATE_ONLY' in p.stdout,p
  print('PASS: PowerShell parser/runtime; declined trust sends no HTTP/token; approval and pin reuse; typed numeric setting write with fresh hash; changed certificate rejected before HTTP/token; private-address restriction; trust file excludes token')
 finally:stop.set();listener.close();thread.join(4)
