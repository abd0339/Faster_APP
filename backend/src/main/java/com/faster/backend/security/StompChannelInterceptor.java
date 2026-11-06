package com.faster.backend.security;

import com.faster.backend.entity.Order;
import com.faster.backend.entity.User;
import com.faster.backend.exception.NotFoundException;
import com.faster.backend.repository.OrderRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.messaging.Message;
import org.springframework.messaging.MessageChannel;
import org.springframework.messaging.simp.stomp.StompCommand;
import org.springframework.messaging.simp.stomp.StompHeaderAccessor;
import org.springframework.messaging.support.ChannelInterceptor;
import org.springframework.messaging.support.MessageHeaderAccessor;
import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Component;

/**
 * STOMP channel interceptor — authenticates the session on connect and
 * authorizes every subscription by destination.
 *
 * SECURITY FIX (review 2026-11-01). The previous version only matched
 * StompCommand.CONNECT and never looked past authentication, which left
 * three real holes:
 *
 *  1. STOMP 1.1/1.2 allows a client's opening frame to be either CONNECT
 *     or its alias STOMP — matching only CONNECT let a client using the
 *     STOMP frame connect with no authentication at all.
 *  2. Nothing checked the token blacklist (logout) or re-checked the
 *     user's current isBlocked status, unlike JwtAuthFilter on the REST
 *     side — a blocked or logged-out user's still-valid JWT kept full
 *     WebSocket access for up to the token's remaining 10-day life.
 *  3. Authentication was the ONLY gate. Once connected with any valid
 *     JWT, a client could SUBSCRIBE to any destination — including
 *     another user's /topic/order/{id} or /topic/driver/{id}, or the
 *     admin-only /topic/admin/** channels.
 *
 * This version re-checks blacklist + isBlocked on every CONNECT/STOMP
 * frame (same rule as JwtAuthFilter), and authorizes every SUBSCRIBE
 * against the destination before it's allowed through.
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class StompChannelInterceptor implements ChannelInterceptor {

    // Shared with JwtAuthFilter — see JwtAuthenticationSupport's own doc
    // for why this used to be two independently-drifting copies of the
    // same blacklist/validity/blocked checks.
    private final JwtAuthenticationSupport jwtAuthenticationSupport;
    private final AuthenticatedUserResolver authenticatedUserResolver;
    private final OrderRepository orderRepository;

    @Override
    public Message<?> preSend(Message<?> message, MessageChannel channel) {
        StompHeaderAccessor accessor = MessageHeaderAccessor
                .getAccessor(message, StompHeaderAccessor.class);

        if (accessor == null) {
            return message;
        }

        StompCommand command = accessor.getCommand();

        // Fix #1 — STOMP is CONNECT's protocol-level alias (used by many
        // client libraries for version negotiation); both must be
        // authenticated the same way, or STOMP-frame clients bypass auth
        // entirely.
        if (StompCommand.CONNECT.equals(command)
                || StompCommand.STOMP.equals(command)) {
            authenticateConnect(accessor);
        } else if (StompCommand.SUBSCRIBE.equals(command)) {
            authorizeSubscribe(accessor);
        }

        return message;
    }

    private void authenticateConnect(StompHeaderAccessor accessor) {
        String bearer = accessor.getFirstNativeHeader("Authorization");
        if (bearer == null || !bearer.startsWith("Bearer ")) {
            throw new IllegalArgumentException("Missing Authorization header on CONNECT");
        }

        String token = bearer.substring(7);

        // Fix #2 — same checks JwtAuthFilter does on every REST request:
        // a revoked (logged-out) token, a deleted account, or a
        // since-blocked account must not get a live socket. Unlike
        // JwtAuthFilter, a WS CONNECT always requires authentication, so
        // a null (missing/invalid/expired token) result is itself an
        // error here.
        try {
            var auth = jwtAuthenticationSupport.authenticate(token);
            if (auth == null) {
                throw new IllegalArgumentException("Invalid or missing WS token");
            }
            accessor.setUser(auth);
        } catch (JwtAuthenticationSupport.AuthRejected e) {
            throw new IllegalArgumentException(e.getMessage());
        }
    }

    // Fix #3 — per-destination authorization. The Principal set at
    // CONNECT is carried on the STOMP session by Spring, so it's
    // available here without re-parsing the JWT; one DB lookup confirms
    // the caller's current id/role (subscriptions are low-frequency —
    // once per topic per connection — so this costs nothing meaningful).
    private void authorizeSubscribe(StompHeaderAccessor accessor) {
        String destination = accessor.getDestination();
        var principal = accessor.getUser();

        if (destination == null || principal == null) {
            throw new IllegalArgumentException("Unauthorized subscription");
        }

        // Shared with the 11 REST controllers that resolve the
        // authenticated principal the same way — see
        // AuthenticatedUserResolver's own doc. The Principal set at
        // CONNECT (see authenticateConnect above) is always the
        // Authentication token this interceptor itself created.
        User user;
        try {
            user = authenticatedUserResolver.resolve((Authentication) principal);
        } catch (NotFoundException | ClassCastException e) {
            throw new IllegalArgumentException("Unauthorized subscription");
        }

        boolean isAdmin = user.getRole() == User.Role.ADMIN;

        if (isAdmin) {
            return; // Admin sees everything — dashboards need this.
        }

        if (destination.startsWith("/topic/admin/")) {
            throw new IllegalArgumentException(
                    "Not authorized to subscribe to " + destination);
        }

        // The exchange rate is broadcast to /topic/exchange-rate on
        // change; this allows subscribing to it. Not role-specific: the rate
        // is readable by any authenticated user via GET /api/exchange-rate
        // (see ExchangeRateController), so any authenticated user may
        // also subscribe to its live updates.
        if (destination.equals("/topic/exchange-rate")) {
            return;
        }

        if (destination.startsWith("/topic/driver/")) {
            requireOwnId(destination, "/topic/driver/", user, User.Role.DRIVER);
            return;
        }

        if (destination.startsWith("/topic/merchant/")) {
            requireOwnId(destination, "/topic/merchant/", user, User.Role.MERCHANT);
            return;
        }

        if (destination.startsWith("/topic/order/")) {
            authorizeOrderTopic(destination, user);
            return;
        }

        // Unrecognized destination — fail closed rather than silently
        // allowing a future topic to go unauthorized by default.
        throw new IllegalArgumentException(
                "Not authorized to subscribe to " + destination);
    }

    private void requireOwnId(String destination, String prefix,
                               User user, User.Role expectedRole) {
        Long topicId = parseTrailingId(destination, prefix);
        if (user.getRole() != expectedRole
                || topicId == null
                || !topicId.equals(user.getId())) {
            throw new IllegalArgumentException(
                    "Not authorized to subscribe to " + destination);
        }
    }

    private void authorizeOrderTopic(String destination, User user) {
        Long orderId = parseTrailingId(destination, "/topic/order/");
        if (orderId == null) {
            throw new IllegalArgumentException(
                    "Not authorized to subscribe to " + destination);
        }

        Order order = orderRepository.findById(orderId).orElse(null);
        if (order == null) {
            throw new IllegalArgumentException(
                    "Not authorized to subscribe to " + destination);
        }

        boolean isParty =
                (order.getCustomer() != null && order.getCustomer().getId().equals(user.getId()))
                || (order.getDriver() != null && order.getDriver().getId().equals(user.getId()))
                || (order.getMerchant() != null && order.getMerchant().getId().equals(user.getId()));

        if (!isParty) {
            throw new IllegalArgumentException(
                    "Not authorized to subscribe to " + destination);
        }
    }

    private Long parseTrailingId(String destination, String prefix) {
        try {
            String idPart = destination.substring(prefix.length());
            // Guard against a sub-path slipping through, e.g.
            // "/topic/driver/5/extra" — only a bare numeric id is valid.
            if (idPart.isEmpty() || idPart.contains("/")) {
                return null;
            }
            return Long.parseLong(idPart);
        } catch (NumberFormatException e) {
            return null;
        }
    }
}
