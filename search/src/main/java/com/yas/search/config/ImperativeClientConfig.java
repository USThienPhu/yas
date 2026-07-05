package com.yas.search.config;

import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.ComponentScan;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.elasticsearch.client.ClientConfiguration;
import org.springframework.data.elasticsearch.client.elc.ElasticsearchConfiguration;
import org.springframework.data.elasticsearch.repository.config.EnableElasticsearchRepositories;

import javax.net.ssl.SSLContext;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509TrustManager;
import java.security.KeyManagementException;
import java.security.NoSuchAlgorithmException;
import java.security.cert.X509Certificate;
import java.time.Duration;
import org.apache.hc.core5.http.HttpRequest;
import org.apache.hc.core5.http.EntityDetails;
import org.apache.hc.core5.http.protocol.HttpContext;
import org.springframework.data.elasticsearch.client.elc.rest5_client.Rest5Clients;

// Configure Elasticsearch client with request interceptor for compatibility
@Configuration
@EnableElasticsearchRepositories(basePackages = "com.yas.search.repository")
@ComponentScan(basePackages = "com.yas.search.service")
@RequiredArgsConstructor
public class ImperativeClientConfig extends ElasticsearchConfiguration {

    private final ElasticsearchDataConfig elasticsearchConfig;

    @Override
    public ClientConfiguration clientConfiguration() {
        var builder = ClientConfiguration.builder()
                .connectedTo(elasticsearchConfig.getUrl()
                        .replace("https://", "")
                        .replace("http://", ""));

        ClientConfiguration.TerminalClientConfigurationBuilder terminalBuilder;
        if (elasticsearchConfig.getUrl() != null && elasticsearchConfig.getUrl().startsWith("https://")) {
            terminalBuilder = builder.usingSsl(trustAllSslContext());
        } else {
            terminalBuilder = builder;
        }

        return terminalBuilder
                .withBasicAuth(elasticsearchConfig.getUsername(), elasticsearchConfig.getPassword())
                .withConnectTimeout(Duration.ofSeconds(10))
                .withSocketTimeout(Duration.ofSeconds(30))
                .withClientConfigurer(Rest5Clients.ElasticsearchHttpClientConfigurationCallback.from(clientBuilder -> {
                    clientBuilder.addRequestInterceptorFirst((HttpRequest request, EntityDetails entity, HttpContext context) -> {
                        if (request.getMethod().equalsIgnoreCase("HEAD")) {
                            request.removeHeaders("Accept");
                            request.setHeader("Accept", "*/*");
                        }
                    });
                    return clientBuilder;
                }))
                .build();
    }

    /**
     * Creates a trust-all SSLContext to bypass certificate verification.
     * ECK generates a self-signed certificate which would otherwise fail validation.
     * NOTE: Only use this in non-production / internal cluster environments.
     */
    private SSLContext trustAllSslContext() {
        try {
            SSLContext sslContext = SSLContext.getInstance("TLS");
            sslContext.init(null, new TrustManager[]{new X509TrustManager() {
                public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; }
                public void checkClientTrusted(X509Certificate[] certs, String authType) {}
                public void checkServerTrusted(X509Certificate[] certs, String authType) {}
            }}, null);
            return sslContext;
        } catch (NoSuchAlgorithmException | KeyManagementException e) {
            throw new RuntimeException("Failed to create trust-all SSL context", e);
        }
    }
}
