package com.faster.backend.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.messaging.simp.config.MessageBrokerRegistry;
import org.springframework.web.socket.config.annotation.EnableWebSocketMessageBroker;
import org.springframework.web.socket.config.annotation.StompEndpointRegistry;
import org.springframework.web.socket.config.annotation.WebSocketMessageBrokerConfigurer;

@Configuration
@EnableWebSocketMessageBroker
public class WebSocketConfig
        implements WebSocketMessageBrokerConfigurer {

    // ─── WebSocket connection endpoint ────────────────
    // Flutter connects to: ws://localhost:8080/ws
    @Override
    public void registerStompEndpoints(
            StompEndpointRegistry registry) {

        registry.addEndpoint("/ws")
                .setAllowedOriginPatterns("*")
                .withSockJS();
    }

    // ─── Message routing ──────────────────────────────
    @Override
    public void configureMessageBroker(
            MessageBrokerRegistry registry) {

        // ─── Server sends TO clients on /topic ───────
        // e.g. /topic/order/123 → customer tracking
        // e.g. /topic/driver/456 → driver gets new order
        registry.enableSimpleBroker(
            "/topic", "/queue");

        // ─── Client sends TO server on /app ──────────
        // e.g. /app/location → driver sends GPS
        registry.setApplicationDestinationPrefixes("/app");
    }
}