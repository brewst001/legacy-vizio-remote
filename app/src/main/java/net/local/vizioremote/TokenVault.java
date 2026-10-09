package net.local.vizioremote;
import android.content.Context;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import java.security.KeyStore;
import javax.crypto.*;
import javax.crypto.spec.GCMParameterSpec;

final class TokenVault {
    private static final String ALIAS="vizio_remote_token";
    private static javax.crypto.SecretKey key() throws Exception {
        KeyStore store=KeyStore.getInstance("AndroidKeyStore"); store.load(null);
        if(!store.containsAlias(ALIAS)) {
            KeyGenerator gen=KeyGenerator.getInstance("AES","AndroidKeyStore");
            gen.init(new KeyGenParameterSpec.Builder(ALIAS,KeyProperties.PURPOSE_ENCRYPT|KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build()); gen.generateKey();
        }
        return (javax.crypto.SecretKey)store.getKey(ALIAS,null);
    }
    static void save(Context c,String value) throws Exception {
        Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE,key());
        c.getSharedPreferences("connection",0).edit().putString("token_iv",Base64.encodeToString(cipher.getIV(),Base64.NO_WRAP))
            .putString("token_data",Base64.encodeToString(cipher.doFinal(value.getBytes("UTF-8")),Base64.NO_WRAP)).apply();
    }
    static String load(Context c) throws Exception {
        android.content.SharedPreferences p=c.getSharedPreferences("connection",0);
        String s=p.getString("token_data",""); if(s.isEmpty())return "";
        Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.DECRYPT_MODE,key(),new GCMParameterSpec(128,Base64.decode(p.getString("token_iv",""),Base64.NO_WRAP)));
        return new String(cipher.doFinal(Base64.decode(s,Base64.NO_WRAP)),"UTF-8");
    }
}
