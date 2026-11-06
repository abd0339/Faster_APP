package com.faster.backend.security;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.messaging.Message;
import org.springframework.messaging.MessageChannel;
import org.springframework.messaging.simp.stomp.StompCommand;
import org.springframework.messaging.simp.stomp.StompHeaderAccessor;
import org.springframework.messaging.support.MessageBuilder;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.authority.SimpleGrantedAuthority;

import com.faster.backend.entity.Order;
import com.faster.backend.entity.User;
import com.faster.backend.repository.OrderRepository;
import com.faster.backend.repository.UserRepository;

/**
 * Covers the final whole-branch-review fix wave, finding #2:
 * StompChannelInterceptor's fail-closed SUBSCRIBE default rejected
 * /topic/exchange-rate because no allow-rule for it was ever added when
 * Task 1 wired up that broadcast. No test file for this class existed
 * at all before this one.
 *
 * Scope, per the dispatch: prove the new rule works (any authenticated
 * user can subscribe to /topic/exchange-rate), AND confirm every
 * pre-existing authorization rule still behaves exactly as before —
 * not just the new rule in isolation.
 *
 * These tests exercise {@link StompChannelInterceptor#preSend} directly
 * with hand-built SUBSCRIBE frames, each with its Principal set on the
 * accessor already (simulating what Spring's STOMP session carries
 * forward from an earlier CONNECT frame) — authenticateConnect's own
 * JWT/blacklist logic is Task-irrelevant here and is not re-tested.
 */
@ExtendWith(MockitoExtension.class)
class StompChannelInterceptorTest {

    @Mock
    private JwtAuthenticationSupport jwtAuthenticationSupport;

    @Mock
    private UserRepository userRepository;

    @Mock
    private OrderRepository orderRepository;

    private StompChannelInterceptor interceptor;

    private static final String CUSTOMER_EMAIL = "customer@test.com";
    private static final String DRIVER_EMAIL = "driver@test.com";
    private static final String MERCHANT_EMAIL = "merchant@test.com";
    private static final String ADMIN_EMAIL = "admin@test.com";

    @BeforeEach
    void setUp() {
        // These tests exercise authorizeSubscribe only (see class doc) —
        // jwtAuthenticationSupport is unused here and stays an
        // unstubbed mock. AuthenticatedUserResolver is real, backed by
        // the same mocked userRepository stubUser() below already sets
        // up, since authorizeSubscribe now resolves through it instead
        // of calling userRepository directly.
        interceptor = new StompChannelInterceptor(
                jwtAuthenticationSupport,
                new AuthenticatedUserResolver(userRepository),
                orderRepository);
    }

    private Authentication principal(String email) {
        return new UsernamePasswordAuthenticationToken(
                email, null, List.of(new SimpleGrantedAuthority("ROLE_USER")));
    }

    private Message<byte[]> subscribeMessage(String destination, Authentication principal) {
        StompHeaderAccessor accessor = StompHeaderAccessor.create(StompCommand.SUBSCRIBE);
        accessor.setDestination(destination);
        accessor.setLeaveMutable(true);
        if (principal != null) {
            accessor.setUser(principal);
        }
        return MessageBuilder.createMessage(new byte[0], accessor.getMessageHeaders());
    }

    private void preSend(String destination, Authentication principal) {
        interceptor.preSend(
                subscribeMessage(destination, principal),
                mock(MessageChannel.class));
    }

    private void stubUser(String email, User.Role role, Long id) {
        lenient().when(userRepository.findByEmail(email))
                .thenReturn(Optional.of(User.builder()
                        .id(id)
                        .email(email)
                        .role(role)
                        .build()));
    }

    // ───────────────────────── NEW RULE: /topic/exchange-rate ─────────────────────────

    @Test
    void customerCanSubscribeToExchangeRateTopic() {
        stubUser(CUSTOMER_EMAIL, User.Role.CUSTOMER, 1L);

        assertDoesNotThrow(() ->
                preSend("/topic/exchange-rate", principal(CUSTOMER_EMAIL)));
    }

    @Test
    void driverCanSubscribeToExchangeRateTopic() {
        stubUser(DRIVER_EMAIL, User.Role.DRIVER, 2L);

        assertDoesNotThrow(() ->
                preSend("/topic/exchange-rate", principal(DRIVER_EMAIL)));
    }

    @Test
    void merchantCanSubscribeToExchangeRateTopic() {
        stubUser(MERCHANT_EMAIL, User.Role.MERCHANT, 3L);

        assertDoesNotThrow(() ->
                preSend("/topic/exchange-rate", principal(MERCHANT_EMAIL)));
    }

    @Test
    void adminCanSubscribeToExchangeRateTopic() {
        stubUser(ADMIN_EMAIL, User.Role.ADMIN, 4L);

        assertDoesNotThrow(() ->
                preSend("/topic/exchange-rate", principal(ADMIN_EMAIL)));
    }

    @Test
    void unauthenticatedCannotSubscribeToExchangeRateTopic() {
        assertThrows(IllegalArgumentException.class, () ->
                preSend("/topic/exchange-rate", null));
    }

    // ───────────────────────── REGRESSION: pre-existing rules unchanged ─────────────────────────

    @Test
    void adminCanSubscribeToAdminTopic() {
        stubUser(ADMIN_EMAIL, User.Role.ADMIN, 4L);

        assertDoesNotThrow(() ->
                preSend("/topic/admin/orders", principal(ADMIN_EMAIL)));
    }

    @Test
    void nonAdminCannotSubscribeToAdminTopic() {
        stubUser(CUSTOMER_EMAIL, User.Role.CUSTOMER, 1L);

        assertThrows(IllegalArgumentException.class, () ->
                preSend("/topic/admin/orders", principal(CUSTOMER_EMAIL)));
    }

    @Test
    void driverCanSubscribeToOwnDriverTopic() {
        stubUser(DRIVER_EMAIL, User.Role.DRIVER, 2L);

        assertDoesNotThrow(() ->
                preSend("/topic/driver/2", principal(DRIVER_EMAIL)));
    }

    @Test
    void driverCannotSubscribeToAnotherDriversTopic() {
        stubUser(DRIVER_EMAIL, User.Role.DRIVER, 2L);

        assertThrows(IllegalArgumentException.class, () ->
                preSend("/topic/driver/99", principal(DRIVER_EMAIL)));
    }

    @Test
    void nonDriverCannotSubscribeToDriverTopicEvenWithMatchingId() {
        stubUser(CUSTOMER_EMAIL, User.Role.CUSTOMER, 2L);

        assertThrows(IllegalArgumentException.class, () ->
                preSend("/topic/driver/2", principal(CUSTOMER_EMAIL)));
    }

    @Test
    void merchantCanSubscribeToOwnMerchantTopic() {
        stubUser(MERCHANT_EMAIL, User.Role.MERCHANT, 3L);

        assertDoesNotThrow(() ->
                preSend("/topic/merchant/3", principal(MERCHANT_EMAIL)));
    }

    @Test
    void merchantCannotSubscribeToAnotherMerchantsTopic() {
        stubUser(MERCHANT_EMAIL, User.Role.MERCHANT, 3L);

        assertThrows(IllegalArgumentException.class, () ->
                preSend("/topic/merchant/99", principal(MERCHANT_EMAIL)));
    }

    @Test
    void orderPartyCanSubscribeToOrderTopic() {
        stubUser(CUSTOMER_EMAIL, User.Role.CUSTOMER, 1L);
        User customer = User.builder().id(1L).email(CUSTOMER_EMAIL)
                .role(User.Role.CUSTOMER).build();
        Order order = Order.builder().id(5L).customer(customer).build();
        when(orderRepository.findById(5L)).thenReturn(Optional.of(order));

        assertDoesNotThrow(() ->
                preSend("/topic/order/5", principal(CUSTOMER_EMAIL)));
    }

    @Test
    void nonPartyCannotSubscribeToOrderTopic() {
        stubUser(CUSTOMER_EMAIL, User.Role.CUSTOMER, 1L);
        User someoneElse = User.builder().id(999L).email("other@test.com")
                .role(User.Role.CUSTOMER).build();
        Order order = Order.builder().id(5L).customer(someoneElse).build();
        when(orderRepository.findById(5L)).thenReturn(Optional.of(order));

        assertThrows(IllegalArgumentException.class, () ->
                preSend("/topic/order/5", principal(CUSTOMER_EMAIL)));
    }

    @Test
    void subscribingToOrderTopicForMissingOrderIsRejected() {
        stubUser(CUSTOMER_EMAIL, User.Role.CUSTOMER, 1L);
        when(orderRepository.findById(anyLong())).thenReturn(Optional.empty());

        assertThrows(IllegalArgumentException.class, () ->
                preSend("/topic/order/404", principal(CUSTOMER_EMAIL)));
    }

    @Test
    void unrecognizedDestinationStillFailsClosed() {
        stubUser(CUSTOMER_EMAIL, User.Role.CUSTOMER, 1L);

        assertThrows(IllegalArgumentException.class, () ->
                preSend("/topic/some-future-topic", principal(CUSTOMER_EMAIL)));
    }
}
