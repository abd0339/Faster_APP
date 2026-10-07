package com.faster.backend.config;

import org.springframework.boot.web.client.RestTemplateBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestTemplate;

import java.time.Duration;

// ─────────────────────────────────────────────────────
// RestTemplateConfig
//
// Registers RestTemplate as a Spring Bean.
// Used by CommunicationService to make HTTP calls
// to Twilio and Vonage APIs without adding
// their heavy SDKs to pom.xml.
//
// Timeouts are required, not optional: a bare
// `new RestTemplate()` uses SimpleClientHttpRequestFactory
// with connectTimeout/readTimeout = 0, which means INFINITE,
// not "sensible default". Every outbound call runs on a
// Tomcat worker thread (200 by default); if Twilio or Google
// stops responding without closing the socket, that worker
// is parked forever. Enough of those and the backend stops
// answering anything — including /api/health — and needs a
// container restart to recover.
// ─────────────────────────────────────────────────────
@Configuration
public class RestTemplateConfig {

    @Bean
    public RestTemplate restTemplate(RestTemplateBuilder builder) {
        return builder
                .setConnectTimeout(Duration.ofSeconds(5))
                .setReadTimeout(Duration.ofSeconds(10))
                .build();
    }
}