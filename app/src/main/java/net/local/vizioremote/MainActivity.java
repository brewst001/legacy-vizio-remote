package net.local.vizioremote;

import android.app.*;
import android.os.Bundle;
import android.content.*;
import android.graphics.Color;
import android.text.InputType;
import android.view.*;
import android.widget.*;
import org.json.*;
import java.util.*;
import java.util.concurrent.*;

public class MainActivity extends Activity {
    private LinearLayout content;
    private TextView heading,status;
    private ProgressBar progress;
    private final ExecutorService executor=Executors.newSingleThreadExecutor();
    private boolean busy=false,destroyed=false;
    private String host,token="",certificate,path="",pageTitle="Remote";
    private int port;
    private boolean legacy;
    private JSONObject last;
    private final ArrayDeque<String[]> history=new ArrayDeque<>();
    private android.content.SharedPreferences prefs;
    interface Task {JSONObject call() throws Exception;}
    interface Done {void call(JSONObject result) throws Exception;}
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        prefs=getSharedPreferences("connection",0);
        host=prefs.getString("host","192.168.1.221"); port=prefs.getInt("port",9000);
        legacy=prefs.getBoolean("legacy",true); certificate=prefs.getString("certificate","");
        try{token=TokenVault.load(this);}catch(Exception e){token="";}
        getWindow().setStatusBarColor(Color.rgb(18,22,29)); getWindow().setNavigationBarColor(Color.rgb(18,22,29));
        LinearLayout root=new LinearLayout(this); root.setOrientation(1); root.setPadding(dp(18),dp(12),dp(18),dp(12)); root.setBackgroundColor(Color.rgb(18,22,29));
        TextView brand=text("LOCAL TV",14); brand.setTextColor(Color.rgb(115,212,194)); root.addView(brand);
        heading=text("Remote",28); root.addView(heading);
        status=text(host+":"+port,13); root.addView(status);
        progress=new ProgressBar(this,null,android.R.attr.progressBarStyleHorizontal); progress.setIndeterminate(true); progress.setVisibility(View.GONE); root.addView(progress,new LinearLayout.LayoutParams(-1,dp(4)));
        LinearLayout nav=new LinearLayout(this);
        Button remote=button("Remote",v->{history.clear();path="";showRemote();});
        Button settings=button("Settings",v->{history.clear();path="";showCategories();});
        Button connection=button("Connection",v->connection());
        nav.addView(remote,new LinearLayout.LayoutParams(0,-2,1));nav.addView(settings,new LinearLayout.LayoutParams(0,-2,1));nav.addView(connection,new LinearLayout.LayoutParams(0,-2,1));root.addView(nav);
        ScrollView scroll=new ScrollView(this);content=new LinearLayout(this);content.setOrientation(1);scroll.addView(content);root.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));root.setOnApplyWindowInsetsListener((v,insets)->{root.setPadding(dp(18),dp(12)+insets.getSystemWindowInsetTop(),dp(18),dp(12)+insets.getSystemWindowInsetBottom());return insets;});setContentView(root);
        showRemote();
        if(token.isEmpty())new AlertDialog.Builder(this).setTitle("Connect to your TV").setMessage("Enter the TV IP address and an existing token, or pair using the PIN shown on your TV. This app is independent of Vizio.").setPositiveButton("Connection",(d,w)->connection()).setNegativeButton("Later",null).show();
    }
    private int dp(int n){return (int)(n*getResources().getDisplayMetrics().density);}
    private TextView text(String s,int size){TextView t=new TextView(this);t.setText(s);t.setTextSize(size);t.setTextColor(Color.rgb(231,237,243));t.setPadding(0,dp(7),0,dp(7));return t;}
    private Button button(String name,View.OnClickListener listener){Button b=new Button(this);b.setText(name);b.setAllCaps(false);b.setOnClickListener(v->{if(busy){Toast.makeText(this,"Wait for the current request",0).show();return;}listener.onClick(v);});return b;}
    private void add(String label,View.OnClickListener listener){content.addView(button(label,listener));}
    private void title(String name){pageTitle=name;heading.setText(name);status.setText(host+":"+port+(token.isEmpty()?" · not paired":" · token saved"));content.removeAllViews();}
    private void info(String text){new AlertDialog.Builder(this).setTitle("Local TV").setMessage(text).setPositiveButton("OK",null).show();}
    private JSONObject req(String method,String endpoint,JSONObject body) throws Exception {
        JSONObject r=new JSONObject(TvTransport.request(host,port,token,certificate,legacy,method,endpoint,body==null?null:body.toString()));
        String result=r.optJSONObject("STATUS")==null?"":r.getJSONObject("STATUS").optString("RESULT");
        if(!result.equalsIgnoreCase("SUCCESS"))throw new Exception("TV response: "+result+"\n"+r.optJSONObject("STATUS"));return r;
    }
    private void run(Task task,Done done) {
        if(busy||destroyed)return;busy=true;progress.setVisibility(View.VISIBLE);
        executor.submit(()->{try {
            JSONObject r=task.call();runOnUiThread(()->{if(destroyed)return;busy=false;progress.setVisibility(View.GONE);try{done.call(r);}catch(Exception e){info(e.getMessage());}});
        }catch(Exception e){runOnUiThread(()->{if(destroyed)return;busy=false;progress.setVisibility(View.GONE);
            TvTransport.CertificateApproval approval=null;for(Throwable c=e;c!=null;c=c.getCause())if(c instanceof TvTransport.CertificateApproval)approval=(TvTransport.CertificateApproval)c;
            if(approval!=null){final String fp=approval.fingerprint;new AlertDialog.Builder(this).setTitle("Trust this TV certificate?")
                .setMessage("First connection to "+host+". Confirm this is your TV on your local network. The app will reject a different certificate on future connections.\n\nSHA-256:\n"+fp)
                .setPositiveButton("Trust TV",(d,w)->{certificate=fp;prefs.edit().putString("certificate",fp).apply();run(task,done);}).setNegativeButton("Cancel",null).show();
            }else info(e.getClass().getSimpleName()+": "+e.getMessage());});}});
    }
    private void showRemote(){title("Remote");content.addView(text("Controls for your local TV",16));
        add("Volume +",v->key(5,1));add("Volume −",v->key(5,0));add("Mute / unmute",v->key(5,4));
        add("Next input",v->key(7,1));add("Channel +",v->key(8,1));add("Channel −",v->key(8,0));
        add("Power off",v->new AlertDialog.Builder(this).setTitle("Turn TV off?").setMessage("In Eco Mode the network API may stop responding until you turn the TV on with a physical remote.").setPositiveButton("Turn off",(d,w)->key(11,0)).setNegativeButton("Cancel",null).show());
        add("Read power state",v->run(()->req("GET","/state/device/power_mode",null),r->showJson(r)));
        content.addView(text("Keep the TV powered on while browsing settings. Network power-on is not implemented in this version.",14));
    }
    private void key(int set,int code){run(()->req("PUT","/key_command/",new JSONObject().put("KEYLIST",new JSONArray().put(new JSONObject().put("CODESET",set).put("CODE",code).put("ACTION","KEYPRESS")))),r->Toast.makeText(this,"Command accepted",0).show());}
    private void showCategories(){title("Settings");String[][] cats={{"System","system"},{"Picture","picture"},{"Audio","audio"},{"Timers","timers"},{"Network","network"},{"Inputs / devices","devices"},{"Channels","channels"},{"Closed captions","closed_captions"},{"Paired devices","mobile_devices"},{"Cast","cast"}};
        for(String[] c:cats)add(c[0],v->load("/menu_native/dynamic/tv_settings/"+c[1],c[0],true));}
    private void load(String p,String name,boolean push){String oldPath=path,oldTitle=pageTitle;run(()->req("GET",p,null),r->{if(push)history.push(new String[]{oldPath,oldTitle});path=p;render(r,name);});}
    private void render(JSONObject r,String name) throws Exception {last=r;title(name);add("Refresh",v->load(path,pageTitle,false));add("Copy / view JSON",v->showJson(last));
        JSONArray items=r.optJSONArray("ITEMS");if(items==null){content.addView(text("No settings returned.",16));return;}
        for(int i=0;i<items.length();i++){JSONObject item=items.getJSONObject(i);String cname=item.optString("CNAME"),label=item.optString("NAME",cname),type=item.optString("TYPE");
            boolean enabled=item.optBoolean("ENABLED",false);String value=SettingPolicy.isMenu(type)?"Open submenu":String.valueOf(item.opt("VALUE"));
            add(label+"\n"+value+(enabled?"":" · unavailable"),v->{if(!enabled){showJson(item);return;}if(!SettingPolicy.pathPart(cname)){showJson(item);return;}
                if(SettingPolicy.isMenu(type))load(path+"/"+cname,label,true);else edit(path,item);});}
    }
    private void edit(String parent,JSONObject old){String cname=old.optString("CNAME");
        // Re-read before constructing the editor: hashes and choices can change.
        run(()->req("GET",parent,null),r->{JSONObject current=null;JSONArray arr=r.optJSONArray("ITEMS");if(arr!=null)for(int i=0;i<arr.length();i++)if(arr.getJSONObject(i).optString("CNAME").equals(cname))current=arr.getJSONObject(i);
            if(current==null)throw new Exception("Setting no longer exists");final JSONObject item=current;
            if(!item.optBoolean("ENABLED")||!SettingPolicy.editable(item.optString("TYPE"))){showJson(item);return;}
            JSONArray choices=item.optJSONArray("ELEMENTS");if(choices!=null&&choices.length()>0){String[] labels=new String[choices.length()];boolean primitive=true;
                for(int i=0;i<labels.length;i++){Object o=choices.get(i);labels[i]=String.valueOf(o);if(!(o instanceof String||o instanceof Number||o instanceof Boolean))primitive=false;}
                if(!primitive){showJson(item);return;}
                new AlertDialog.Builder(this).setTitle(item.optString("NAME")).setItems(labels,(d,w)->{try{confirm(parent,item,choices.get(w));}catch(Exception e){info(e.getMessage());}}).setNegativeButton("Cancel",null).show();
            }else if(item.optString("TYPE").startsWith("T_LIST")){showJson(item);}
            else {Object value=item.opt("VALUE");if(!(value instanceof String||value instanceof Number||value instanceof Boolean)){showJson(item);return;}
                EditText input=new EditText(this);input.setSingleLine(true);input.setText(String.valueOf(value));
                if(value instanceof Number)input.setInputType(InputType.TYPE_CLASS_NUMBER|InputType.TYPE_NUMBER_FLAG_SIGNED|InputType.TYPE_NUMBER_FLAG_DECIMAL);
                new AlertDialog.Builder(this).setTitle(item.optString("NAME")).setView(input).setPositiveButton("Review",(d,w)->{try{String s=input.getText().toString();Object next=s;
                    if(value instanceof Number){java.math.BigDecimal number=new java.math.BigDecimal(s);next=number;}else if(value instanceof Boolean){if(!s.equals("true")&&!s.equals("false"))throw new Exception("Enter true or false");next=Boolean.valueOf(s);}confirm(parent,item,next);
                }catch(Exception e){info("Invalid value: "+e.getMessage());}}).setNegativeButton("Cancel",null).show();}
        });
    }
    private void confirm(String parent,JSONObject item,Object next){new AlertDialog.Builder(this).setTitle("Change "+item.optString("NAME")+"?")
        .setMessage("Current: "+item.opt("VALUE")+"\nNew: "+next+(parent.contains("/network")?"\n\nThis may disconnect the TV.":""))
        .setPositiveButton("Apply",(d,w)->run(()->{
            JSONObject fresh=req("GET",parent,null),found=null;JSONArray a=fresh.getJSONArray("ITEMS");String cname=item.getString("CNAME");
            for(int i=0;i<a.length();i++)if(a.getJSONObject(i).optString("CNAME").equals(cname))found=a.getJSONObject(i);
            if(found==null||!found.optBoolean("ENABLED"))throw new Exception("Setting is now unavailable");
            if(!String.valueOf(found.opt("VALUE")).equals(String.valueOf(item.opt("VALUE"))))throw new Exception("Setting changed since you opened it. Refresh and retry.");
            JSONArray elements=found.optJSONArray("ELEMENTS");if(elements!=null&&elements.length()>0){boolean allowed=false;for(int i=0;i<elements.length();i++)if(elements.get(i).equals(next))allowed=true;if(!allowed)throw new Exception("Value is no longer an available choice");}
            if(!found.has("HASHVAL"))throw new Exception("TV did not supply a setting hash");
            Object min=found.opt("MINIMUM"),max=found.opt("MAXIMUM");if(next instanceof Number){double n=((Number)next).doubleValue();if(min instanceof Number&&n<((Number)min).doubleValue()||max instanceof Number&&n>((Number)max).doubleValue())throw new Exception("Value outside TV's advertised range");}
            return req("PUT",parent+"/"+cname,new JSONObject().put("REQUEST","MODIFY").put("HASHVAL",found.get("HASHVAL")).put("VALUE",next));
        },r->{Toast.makeText(this,"Setting updated",0).show();load(parent,pageTitle,false);})).setNegativeButton("Cancel",null).show();}
    private void showJson(JSONObject r){try{String json=r.toString(2);TextView view=text(json,13);view.setTextIsSelectable(true);view.setTypeface(android.graphics.Typeface.MONOSPACE);ScrollView scroll=new ScrollView(this);scroll.addView(view);
        new AlertDialog.Builder(this).setTitle("TV response").setView(scroll).setPositiveButton("Copy",(d,w)->{((android.content.ClipboardManager)getSystemService(CLIPBOARD_SERVICE)).setPrimaryClip(ClipData.newPlainText("TV response",json));Toast.makeText(this,"Copied",0).show();}).setNegativeButton("Close",null).show();}catch(Exception e){info(e.getMessage());}}
    private void connection(){LinearLayout form=new LinearLayout(this);form.setOrientation(1);form.setPadding(dp(18),0,dp(18),0);
        EditText ip=new EditText(this);ip.setSingleLine(true);ip.setHint("TV private IPv4 address");ip.setText(host);form.addView(ip);
        EditText ports=new EditText(this);ports.setInputType(InputType.TYPE_CLASS_NUMBER);ports.setHint("API port");ports.setText(String.valueOf(port));form.addView(ports);
        EditText auth=new EditText(this);auth.setSingleLine(true);auth.setHint("Token (leave empty to pair)");auth.setInputType(InputType.TYPE_CLASS_TEXT|InputType.TYPE_TEXT_VARIATION_PASSWORD);auth.setText(token);form.addView(auth);
        CheckBox compat=new CheckBox(this);compat.setText("Legacy TV TLS compatibility (E32-D1)");compat.setChecked(legacy);form.addView(compat);
        CheckBox forget=new CheckBox(this);forget.setText("Forget pinned certificate (new TV / reviewed certificate change)");form.addView(forget);
        new AlertDialog.Builder(this).setTitle("Connection").setView(form).setPositiveButton("Save",(d,w)->{try{String h=ip.getText().toString().trim(),t=auth.getText().toString().trim();int p=Integer.parseInt(ports.getText().toString());
            if(!TvTransport.privateAddress(h)||p<1||p>65535||!t.matches("[A-Za-z0-9]*"))throw new Exception("Enter a private IPv4 address, valid port and token");
            boolean changed=!h.equals(host)||p!=port;if(changed||forget.isChecked())certificate="";host=h;port=p;token=t;legacy=compat.isChecked();
            TokenVault.save(this,token);prefs.edit().putString("host",host).putInt("port",port).putBoolean("legacy",legacy).putString("certificate",certificate).apply();status.setText(host+":"+port);
            if(token.isEmpty())pair();else info("Connection saved. Use a read command to test it.");
        }catch(Exception e){info(e.getMessage());}}).setNeutralButton("Pair",(d,w)->{try{String h=ip.getText().toString().trim();int p=Integer.parseInt(ports.getText().toString());if(!TvTransport.privateAddress(h)||p<1||p>65535)throw new Exception("Invalid address or port");
            if(!h.equals(host)||p!=port||forget.isChecked())certificate="";host=h;port=p;legacy=compat.isChecked();token="";prefs.edit().putString("certificate",certificate).apply();pair();}catch(Exception e){info(e.getMessage());}}).setNegativeButton("Cancel",null).show();}
    private void pair(){String id="local-tv-"+UUID.randomUUID();run(()->req("PUT","/pairing/start",new JSONObject().put("DEVICE_ID",id).put("DEVICE_NAME","Local TV Android")),r->{JSONObject item=r.getJSONObject("ITEM");int req=item.getInt("PAIRING_REQ_TOKEN"),challenge=item.getInt("CHALLENGE_TYPE");EditText pin=new EditText(this);pin.setInputType(InputType.TYPE_CLASS_NUMBER);pin.setSingleLine(true);
        new AlertDialog.Builder(this).setTitle("Enter TV PIN").setMessage("If the setup screen hides the PIN, press Play/Pause on the remote. Enter the currently displayed four digits.").setView(pin).setPositiveButton("Pair",(d,w)->{String code=pin.getText().toString().trim();if(!code.matches("[0-9]{4}")){info("PIN must contain four digits. Start pairing again.");return;}
            run(()->req("PUT","/pairing/pair",new JSONObject().put("DEVICE_ID",id).put("CHALLENGE_TYPE",challenge).put("PAIRING_REQ_TOKEN",req).put("RESPONSE_VALUE",code)),response->{token=response.getJSONObject("ITEM").getString("AUTH_TOKEN");TokenVault.save(this,token);prefs.edit().putString("host",host).putInt("port",port).putBoolean("legacy",legacy).apply();info("Paired. Token saved securely on this phone.");showRemote();});
        }).setNegativeButton("Cancel",null).show();});}
    @Override public void onBackPressed(){if(busy)return;if(!history.isEmpty()){String[] prev=history.pop();if(prev[0].isEmpty()){path="";showCategories();}else load(prev[0],prev[1],false);}else if(!path.isEmpty()){path="";showCategories();}else{super.onBackPressed();}}
    @Override protected void onDestroy(){destroyed=true;executor.shutdownNow();super.onDestroy();}
}
