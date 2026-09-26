import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.URL;
import java.security.cert.X509Certificate;
import javax.net.ssl.HttpsURLConnection;

/**
 * 和 JavaTlsTest 一样，但**只用 Java 8 有的 API** —— 因为 1.8.9 用的
 * 那个 JRE（官方启动器的 jre-legacy）就是 Java 8，而 Java 9+ 的
 * InputStream.readAllBytes() 在它上面根本编译不过。
 *
 * 用法: java JavaTlsTest8 <url> [apiKey]
 */
public class JavaTlsTest8 {
    public static void main(String[] args) throws Exception {
        String url = args[0];
        String key = args.length > 1 ? args[1] : "";

        HttpsURLConnection c = (HttpsURLConnection) new URL(url).openConnection();
        if (!key.isEmpty()) c.setRequestProperty("API-Key", key);
        c.setConnectTimeout(15000);
        c.setReadTimeout(25000);

        int code = c.getResponseCode();
        System.out.println("HTTP " + code);
        System.out.println("Java " + System.getProperty("java.version"));

        try {
            java.security.cert.Certificate[] chain = c.getServerCertificates();
            if (chain.length > 0) {
                X509Certificate leaf = (X509Certificate) chain[0];
                System.out.println("服务端证书 subject : " + leaf.getSubjectX500Principal());
                System.out.println("服务端证书 issuer  : " + leaf.getIssuerX500Principal());
            }
        } catch (Exception e) {
            System.out.println("(读证书信息失败: " + e.getMessage() + ")");
        }

        InputStream is = code < 400 ? c.getInputStream() : c.getErrorStream();
        String body = "";
        if (is != null) {
            ByteArrayOutputStream bos = new ByteArrayOutputStream();
            byte[] buf = new byte[4096];
            int n;
            while ((n = is.read(buf)) > 0) bos.write(buf, 0, n);
            body = new String(bos.toByteArray(), "UTF-8");
        }
        System.out.println("BODY " + body.substring(0, Math.min(180, body.length())));
    }
}
