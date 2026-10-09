package net.local.vizioremote;
import java.io.*;
import java.util.Base64;
import java.nio.charset.StandardCharsets;
/** Credentials travel on stdin, not command-line arguments. */
public final class TransportCli {
 private static String decode(String s){return new String(Base64.getDecoder().decode(s),StandardCharsets.UTF_8);}
 private static String encode(String s){return Base64.getEncoder().encodeToString(s.getBytes(StandardCharsets.UTF_8));}
 public static void main(String[] args){
  try {
   BufferedReader r=new BufferedReader(new InputStreamReader(System.in,StandardCharsets.UTF_8));String[] fields=new String[8];
   for(int i=0;i<fields.length;i++){String line=r.readLine();if(line==null)throw new IOException("Incomplete input");fields[i]=decode(line);}
   String result=TvTransport.request(fields[0],Integer.parseInt(fields[1]),fields[2],fields[3],Boolean.parseBoolean(fields[4]),fields[5],fields[6],fields[7].isEmpty()?null:fields[7]);
   System.out.println("{\"kind\":\"ok\",\"data\":\""+encode(result)+"\"}");
  }catch(TvTransport.CertificateApproval e){System.out.println("{\"kind\":\"trust\",\"data\":\""+encode(e.fingerprint)+"\"}");}
  catch(Exception e){System.out.println("{\"kind\":\"error\",\"data\":\""+encode(e.getClass().getSimpleName()+": "+e.getMessage())+"\"}");System.exit(1);}
 }
}
