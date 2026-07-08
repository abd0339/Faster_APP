package com.faster.backend.config;

import com.faster.backend.security.JwtUtil;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Configuration;
import org.springframework.messaging.Message;
import org.springframework.messaging.MessageChannel;
import org.springframework.messaging.simp.config.MessageBrokerRegistry;
import org.springframework.messaging.simp.stomp.StompCommand;
import org.springframework.messaging.simp.stomp.StompHeaderAccessor;
import org.springframework.messaging.support.ChannelInterceptor;
import org.springframework.messaging.support.MessageHeaderAccessor;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.web.socket.config.annotation.*;

import java.util.List;

/**
 * WebSocket / STOMP configuration.
 *
 * FIXES:
 *  - (HIGH) The STOMP CONNECT frame is now authenticated with the same JWT as
 *    the REST API. Previously the socket endpoint was in the permitAll list and
 *    there was NO channel interceptor, so:
 *      * the driver.location handler received a null/empty Authentication and
 *        silently dropped every GPS update (functional bug), and
 *      * any anonymous client could open a socket and subscribe to /topic/**,
 *        reading other users' order-status and driver notifications.
 *    The interceptor sets the authenticated principal so @MessageMapping methods
 *    receive a real Authentication and downstream authorization works.
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

    private final JwtUtil jwtUtil;

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
        registration.interceptors(new ChannelInterceptor() {
            @Override
            public Message<?> preSend(Message<?> message, MessageChannel channel) {
                StompHeaderAccessor accessor = MessageHeaderAccessor
                        .getAccessor(message, StompHeaderAccessor.class);

                if (accessor != null && StompCommand.CONNECT.equals(accessor.getCommand())) {
                    String bearer = accessor.getFirstNativeHeader("Authorization");
                    if (bearer != null && bearer.startsWith("Bearer ")) {
                        String token = bearer.substring(7);
                        if (jwtUtil.validateToken(token)) {
                            String email = jwtUtil.getEmailFromToken(token);
                            String role = jwtUtil.getRoleFromToken(token);
                            var auth = new UsernamePasswordAuthenticationToken(
                                    email, null,
                                    List.of(new SimpleGrantedAuthority("ROLE_" + role)));
                            accessor.setUser(auth);
                        } else {
                            throw new IllegalArgumentException("Invalid or missing WS token");
                        }
                    } else {
                        throw new IllegalArgumentException("Missing Authorization header on CONNECT");
                    }
                }
                return message;
            }
        });
    }
}