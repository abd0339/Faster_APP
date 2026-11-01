package com.faster.backend.config;

import com.faster.backend.security.StompChannelInterceptor;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Configuration;
import org.springframework.messaging.simp.config.MessageBrokerRegistry;
import org.springframework.messaging.simp.config.ChannelRegistration;
import org.springframework.web.socket.config.annotation.*;

/**
 * WebSocket / STOMP configuration.
 *
 * FIXES:
 *  - (HIGH) The STOMP CONNECT (and its protocol alias STOMP) frame is now
 *    authenticated with the same JWT as the REST API, including the
 *    token-blacklist and isBlocked re-checks JwtAuthFilter does on every
 *    REST request. Every SUBSCRIBE is also authorized against its
 *    destination (own driver/merchant topic, or a party to the order;
 *    /topic/admin/** is admin-only). See StompChannelInterceptor for the
 *    full rationale — this used to only gate CONNECT and only checked
 *    authentication, never authorization, which left real holes (anonymous
 *    STOMP-frame connections, and any authenticated user reading any other
 *    user's or admin's topics).
 *
 *  - (MEDIUM) setAllowedOriginPatterns("*") is replaced with the configured
 *    front-end origins.
 *
 * Client must send the token as a STOMP header on CONNECT:
 *    connectHeaders: { "Authorization": "Bearer <jwt>" }
 */
@Configuration
@EnableWebSocketMessageBroker
@RequiredArgsConstructor
public class WebSocketConfig implements WebSocketMessageBrokerConfigurer {

    private final StompChannelInterceptor stompChannelInterceptor;

    @org.springframework.beans.factory.annotation.Value(
            "${app.cors.allowed-origins:http://localhost:*}")
    private String allowedOrigins;

    @Override
    public void registerStompEndpoints(StompEndpointRegistry registry) {
        String[] origins = allowedOrigins.split(",");
        for (int i = 0; i < origins.length; i++) origins[i] = origins[i].trim();

        registry.addEndpoint("/ws")
                .setAllowedOriginPatterns(origins)
                .withSockJS();
    }

    @Override
    public void configureMessageBroker(MessageBrokerRegistry registry) {
        registry.enableSimpleBroker("/topic", "/queue");
        registry.setApplicationDestinationPrefixes("/app");
    }

    @Override
    public void configureClientInboundChannel(ChannelRegistration registration) {
        registration.interceptors(stompChannelInterceptor);
    }
}