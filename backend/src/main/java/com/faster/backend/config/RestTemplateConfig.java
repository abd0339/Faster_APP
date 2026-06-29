package com.faster.backend.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestTemplate;

// ─────────────────────────────────────────────────────
// RestTemplateConfig
//
// Registers RestTemplate as a Spring Bean.
// Used by CommunicationService to make HTTP calls
// to Twilio and Vonage APIs without adding
// their heavy SDKs to pom.xml.
//
// In production you can configure timeouts here:
//   connectTimeout = 5 seconds
//   readTimeout    = 10 seconds
// ─────────────────────────────────────────────────────
@Configuration
public class RestTemplateConfig {

    @Bean
    public RestTemplate restTemplate() {
        // Simple factory — add timeout config here
        // if needed in production:
        //
        // HttpComponentsClientHttpRequestFactory factory =
        //     new HttpComponentsClientHttpRequestFactory();
        // factory.setConnectTimeout(5000);
        // factory.setReadTimeout(10000);
        // return new RestTemplate(factory);

        return new RestTemplate();
    }
}