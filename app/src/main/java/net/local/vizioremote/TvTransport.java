package net.local.vizioremote;

import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Locale;
import org.bouncycastle.tls.*;
import org.bouncycastle.tls.crypto.impl.bc.BcTlsCrypto;

/** TLS compatibility is scoped to this one private-network TV connection. */
public final class TvTransport {
    public static final class CertificateApproval extends IOException {
        public final String fingerprint;
        CertificateApproval(String fingerprint) { super("Approve the TV certificate first"); this.fingerprint=fingerprint; }
    }
    public static boolean privateAddress(String host) {
        String[] p=host.split("\\.", -1);
        if(p.length!=4) return false;
        int[] n=new int[4];
        for(int i=0;i<4;i++) { if(!p[i].matches("[0-9]{1,3}"))return false; n[i]=Integer.parseInt(p[i]); if(n[i]>255)return false; }
        return n[0]==10 || n[0]==192&&n[1]==168 || n[0]==172&&n[1]>=16&&n[1]<=31 || n[0]==169&&n[1]==254;
    }
    public static String fingerprint(byte[] certificate) throws IOException {
        try {
            byte[] hash=MessageDigest.getInstance("SHA-256").digest(certificate);
            StringBuilder b=new StringBuilder(); for(byte v:hash)b.append(String.format(Locale.ROOT,"%02X",v&255)); return b.toString();
        } catch(Exception e) {throw new IOException(e);}
    }
    public static String request(String host,int port,String token,String pin,boolean legacy,String method,String path,String body) throws IOException {
        return exchange(host,port,token,pin,legacy,method,path,body,false);
    }
    // Package-private loopback allowance exists only for JVM integration tests.
    static String exchange(String host,int port,String token,String pin,boolean legacy,String method,String path,String body,boolean test) throws IOException {
        if(!privateAddress(host)&&!(test&&host.equals("127.0.0.1")))throw new IOException("Enter a private IPv4 address for your TV");
        if(port<1||port>65535)throw new IOException("Invalid port");
        if(!method.equals("GET")&&!method.equals("PUT"))throw new IOException("Unsupported method");
        if(!path.matches("/[a-zA-Z0-9_/-]+")||path.contains(".."))throw new IOException("Invalid API path");
        if(token!=null&&!token.matches("[a-zA-Z0-9]*"))throw new IOException("Invalid token format");
        final String[] observed={null};
        try(Socket socket=new Socket()) {
            socket.connect(new InetSocketAddress(host,port),5000); socket.setSoTimeout(15000);
            TlsClientProtocol tls=new TlsClientProtocol(socket.getInputStream(),socket.getOutputStream());
            DefaultTlsClient client=new DefaultTlsClient(new BcTlsCrypto(new java.security.SecureRandom())) {
                protected ProtocolVersion[] getSupportedVersions() {
                    return legacy?new ProtocolVersion[]{ProtocolVersion.TLSv12,ProtocolVersion.TLSv11,ProtocolVersion.TLSv10}:new ProtocolVersion[]{ProtocolVersion.TLSv12};
                }
                protected int[] getSupportedCipherSuites() {
                    return legacy?new int[]{CipherSuite.TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,CipherSuite.TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA,CipherSuite.TLS_RSA_WITH_AES_128_CBC_SHA}:new int[]{CipherSuite.TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,CipherSuite.TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384};
                }
                public void notifySecureRenegotiation(boolean secure) throws IOException {
                    if(!secure&&!legacy)throw new IOException("TV needs legacy TLS compatibility");
                    // Initial connection to an old TV only; renegotiation remains disabled.
                }
                public TlsAuthentication getAuthentication() {
                    return new TlsAuthentication() {
                        public void notifyServerCertificate(TlsServerCertificate cert) throws IOException {
                            observed[0]=fingerprint(cert.getCertificate().getCertificateAt(0).getEncoded());
                            if(pin==null||pin.isEmpty())throw new CertificateApproval(observed[0]);
                            if(!pin.equals(observed[0]))throw new IOException("TV certificate changed. Connection rejected. Review it in Connection settings.");
                        }
                        public TlsCredentials getClientCredentials(CertificateRequest request) {return null;}
                    };
                }
            };
            try {tls.connect(client);} catch(IOException e) {
                if(observed[0]!=null&&(pin==null||pin.isEmpty()))throw new CertificateApproval(observed[0]);
                throw e;
            }
            byte[] data=(body==null?"":body).getBytes(StandardCharsets.UTF_8);
            String headers=method+" "+path+" HTTP/1.1\r\nHost: "+host+":"+port+"\r\nConnection: close\r\nAccept: application/json\r\nContent-Type: application/json\r\n"+
                (token==null||token.isEmpty()?"":"AUTH: "+token+"\r\n")+"Content-Length: "+data.length+"\r\n\r\n";
            OutputStream out=tls.getOutputStream(); out.write(headers.getBytes(StandardCharsets.US_ASCII)); out.write(data); out.flush();
            InputStream in=tls.getInputStream(); String status=line(in);
            if(!status.matches("HTTP/1\\.[01] 200(?: .*)?"))throw new IOException("TV HTTP response: "+status);
            int length=-1; boolean chunked=false;
            for(int i=0;;i++) {
                if(i>100)throw new IOException("Too many headers"); String h=line(in); if(h.isEmpty())break;
                String lower=h.toLowerCase(Locale.ROOT);
                if(lower.startsWith("content-length:")) {try{length=Integer.parseInt(h.substring(h.indexOf(':')+1).trim());}catch(NumberFormatException e){throw new IOException("Invalid Content-Length");}}
                if(lower.startsWith("transfer-encoding:")&&lower.contains("chunked"))chunked=true;
            }
            ByteArrayOutputStream result=new ByteArrayOutputStream();
            if(chunked) {
                for(;;) {String h=line(in).split(";",2)[0]; int size; try{size=Integer.parseInt(h.trim(),16);}catch(Exception e){throw new IOException("Invalid chunk");} if(size==0)break; copy(in,result,size); if(!line(in).isEmpty())throw new IOException("Invalid chunk terminator");}
            } else if(length>=0)copy(in,result,length);
            else {int c; while((c=in.read())!=-1) {if(result.size()>=2_000_000)throw new IOException("Response too large"); result.write(c);}}
            // Socket close terminates this single-request connection.
            return result.toString("UTF-8");
        }
    }
    private static String line(InputStream in) throws IOException {
        ByteArrayOutputStream b=new ByteArrayOutputStream(); int c;
        while((c=in.read())!=-1) {if(c=='\n')break; if(b.size()>8192)throw new IOException("Header too large"); if(c!='\r')b.write(c);}
        if(c==-1&&b.size()==0)throw new EOFException("TV closed the connection"); return b.toString("US-ASCII");
    }
    private static void copy(InputStream in,ByteArrayOutputStream out,int n) throws IOException {
        if(n<0||n>2_000_000-out.size())throw new IOException("Response too large"); byte[] buf=new byte[8192];
        while(n>0) {int read=in.read(buf,0,Math.min(n,buf.length)); if(read<0)throw new EOFException("Incomplete response"); out.write(buf,0,read); n-=read;}
    }
}
