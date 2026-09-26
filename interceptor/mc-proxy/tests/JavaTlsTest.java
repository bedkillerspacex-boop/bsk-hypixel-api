import java.io.InputStream;
import java.net.URL;
import java.security.cert.X509Certificate;
import javax.net.ssl.HttpsURLConnection;

/**
 * 用 JVM 自己发一次 HTTPS 请求 —— 直接验证"Java 认不认我们的证书链"。
 *
 * 这正是之前失败的那一步:
 *   PKIX path building failed: unable to find valid certification path
 *
 * 用法: java JavaTlsTest.java <url> [apiKey]
 */
public class JavaTlsTest {
    public static void main(String[] args) throws Exception {
        String url = args[0];
        String key = args.length > 1 ? args[1] : "";

        HttpsURLConnection c = (HttpsURLConnection) new URL(url).openConnection();
        if (!key.isEmpty()) c.setRequestProperty("API-Key", key);
        c.setConnectTimeout(15000);
        c.setReadTimeout(25000);

        int code = c.getResponseCode();
        System.out.println("HTTP " + code);

        try {
            for (X509Certificate cert : c.getServerCertificates().length > 0
                    ? new X509Certificate[]{(X509Certificate) c.getServerCertificates()[0]}
                    : new X509Certificate[0]) {
                System.out.println("服务端证书 subject : " + cert.getSubjectX500Principal());
                System.out.println("服务端证书 issuer  : " + cert.getIssuerX500Principal());
            }
        } catch (Exception e) {
            System.out.println("(读证书信息失败: " + e.getMessage() + ")");
        }

        InputStream is = code < 400 ? c.getInputStream() : c.getErrorStream();
        String body = is == null ? "" : new String(is.readAllBytes(), "UTF-8");
        System.out.println("BODY " + body.substring(0, Math.min(180, body.length())));
    }
}
