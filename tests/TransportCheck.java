package net.local.vizioremote;
public class TransportCheck {
 public static void main(String[] a)throws Exception {
  if(a[0].equals("policy")) {
   if(!TvTransport.privateAddress("192.168.1.221")||TvTransport.privateAddress("8.8.8.8")||TvTransport.privateAddress("192.168.1.999")||SettingPolicy.editable("T_ACTION_V1")||!SettingPolicy.editable("T_LIST_V1")||SettingPolicy.pathPart("../reset"))throw new AssertionError();
   System.out.println("POLICY_OK");return;
  }
  try {System.out.println(TvTransport.exchange("127.0.0.1",Integer.parseInt(a[0]),"ABC123",a[1],Boolean.parseBoolean(a[2]),"PUT","/test","{\"name\":\"Télé\"}",true));}
  catch(TvTransport.CertificateApproval e){System.out.println("APPROVAL:"+e.fingerprint);}
 }
}
