package com.faster.backend.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;

import java.math.BigDecimal;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.MediaType;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.faster.backend.entity.Order;
import com.faster.backend.entity.User;
import com.faster.backend.exception.GlobalExceptionHandler;
import com.faster.backend.repository.ItemAddonRepository;
import com.faster.backend.repository.ItemRepository;
import com.faster.backend.repository.ModifierOptionRepository;
import com.faster.backend.repository.OrderRepository;
import com.faster.backend.repository.UserRepository;
import com.faster.backend.security.AuthenticatedUserResolver;
import com.faster.backend.service.CommunicationService;
import com.faster.backend.service.LedgerService;
import com.faster.backend.service.LocationService;
import com.faster.backend.service.OrderService;
import com.faster.backend.service.PricingService;
import com.faster.backend.service.PushNotificationService;

/**
 * {@code OrderControllerAdversarialTest} mocks {@code OrderService}
 * entirely, so its tests for the public tracking-location endpoint only
 * prove the controller/Jackson layer doesn't crash — never that the
 * endpoint's actual business logic (coordinate validation, the
 * flag-vs-reject distance-cap path) behaves correctly. This file wires
 * the REAL {@link OrderController} -> REAL {@link OrderService} -> REAL
 * {@link PricingService} (only the lowest-level repositories/messaging
 * are mocked) under real MockMvc/Jackson/{@link GlobalExceptionHandler},
 * so every assertion here is about genuine end-to-end behavior, not
 * mocked pass-through.
 */
@ExtendWith(MockitoExtension.class)
class OrderControllerRealServiceAdversarialTest {

    @Mock private OrderRepository orderRepository;
    @Mock private UserRepository userRepository;
    @Mock private LocationService locationService;
    @Mock private SimpMessagingTemplate messagingTemplate;
    @Mock private LedgerService ledgerService;
    @Mock private CommunicationService communicationService;
    @Mock private PushNotificationService pushNotificationService;
    @Mock private ItemRepository itemRepository;
    @Mock private ModifierOptionRepository modifierOptionRepository;
    @Mock private ItemAddonRepository addonRepository;
    @Mock private AuthenticatedUserResolver authResolver;

    private MockMvc mockMvc;

    private static final String TRACKING_CODE = "FST-REAL-TEST";
    private static final String RECIPIENT_PHONE = "+96170000000";
    private static final double VALID_LAT = 33.5;
    private static final double VALID_LNG = 36.3;

    @BeforeEach
    void setUp() {
        PricingService pricingService = new PricingService(
                itemRepository, modifierOptionRepository, addonRepository);
        ReflectionTestUtils.setField(pricingService, "maxDeliveryDistanceKm", 6.0);
        ReflectionTestUtils.setField(
                pricingService, "deliveryBaseFee", new BigDecimal("1.00"));
        ReflectionTestUtils.setField(
                pricingService, "deliveryRatePerKm", new BigDecimal("0.50"));
        ReflectionTestUtils.setField(
                pricingService, "deliveryMinFee", new BigDecimal("1.50"));

        OrderService orderService = new OrderService(
                orderRepository, userRepository, locationService,
                messagingTemplate, ledgerService, communicationService,
                pricingService, pushNotificationService);

        OrderController controller =
                new OrderController(orderService, orderRepository, authResolver);

        mockMvc = MockMvcBuilders.standaloneSetup(controller)
                .setControllerAdvice(new GlobalExceptionHandler())
                .build();

        lenient().when(authResolver.resolve(any(Authentication.class)))
                .thenReturn(User.builder().id(1L).phone(RECIPIENT_PHONE).build());
    }

    private Order existingOrder() {
        return Order.builder()
                .id(99L)
                .trackingCode(TRACKING_CODE)
                .status(Order.OrderStatus.ACCEPTED)
                .offlineCustomerPhone(RECIPIENT_PHONE)
                .pickupLat(VALID_LAT)
                .pickupLng(VALID_LNG)
                .deliveryLat(VALID_LAT)
                .deliveryLng(VALID_LNG)
                .deliveryFee(new BigDecimal("5.00"))
                .commissionAmount(new BigDecimal("1.00"))
                .totalPrice(new BigDecimal("15.00"))
                .grandTotal(new BigDecimal("20.00"))
                .isDistanceFlagged(false)
                .build();
    }

    // ───────────── PATCH /api/tracking/public/{code}/location (PUBLIC, unauthenticated) ─────────────

    @Test
    void updateTrackingLocation_rejectsOverflowingCoordinate_asCleanRejection_notSilentFlag()
            throws Exception {
        // Without coordinate range validation: "1e400" overflows to
        // Double.POSITIVE_INFINITY, which PricingService's non-finite
        // check treats as "exceeding" — taking the FLAG path (200 OK,
        // order silently flagged) instead of a clean rejection, on a
        // PUBLIC, unauthenticated endpoint. Must be a clean 4xx, and
        // the order must never even be fetched.
        var result = mockMvc.perform(patch("/api/tracking/public/{code}/location", TRACKING_CODE)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"lat\": 1e400, \"lng\": 35.5}"))
                .andReturn();

        int status = result.getResponse().getStatus();
        assertThat(status).isGreaterThanOrEqualTo(400).isLessThan(500);
        org.mockito.Mockito.verify(orderRepository, org.mockito.Mockito.never())
                .findByTrackingCode(any());
    }

    @Test
    void updateTrackingLocation_rejectsOutOfRangeLatitude_asCleanRejection() throws Exception {
        // A finite-but-garbage coordinate (pickupLat + 360) wraps back
        // onto a real point on the sphere and would compute a near-zero
        // distance, defeating the distance cap entirely rather than
        // merely mis-flagging it — must be rejected outright.
        var result = mockMvc.perform(patch("/api/tracking/public/{code}/location", TRACKING_CODE)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"lat\": 393.8938, \"lng\": 35.5}"))
                .andReturn();

        int status = result.getResponse().getStatus();
        assertThat(status).isGreaterThanOrEqualTo(400).isLessThan(500);
        // The stronger assertion: must be rejected before the order is
        // even fetched, not merely happen to 404 because the repository
        // mock is unstubbed. A real order WOULD be found in production,
        // and without this check the request would wrongly proceed to
        // the flag/fee-calc path.
        org.mockito.Mockito.verify(orderRepository, org.mockito.Mockito.never())
                .findByTrackingCode(any());
    }

    @Test
    void updateTrackingLocation_acceptsValidCoordinates() throws Exception {
        Order order = existingOrder();
        when(orderRepository.findByTrackingCode(TRACKING_CODE))
                .thenReturn(Optional.of(order));
        when(orderRepository.save(any(Order.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        var result = mockMvc.perform(patch("/api/tracking/public/{code}/location", TRACKING_CODE)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"lat\": 33.51, \"lng\": 36.31}"))
                .andReturn();

        assertThat(result.getResponse().getStatus()).isEqualTo(200);
    }

    // ───────────── PATCH /api/orders/{orderId}/confirm-my-location ─────────────

    @Test
    void confirmMyLocation_rejectsOutOfRangeLongitude_asCleanRejection() throws Exception {
        var result = mockMvc.perform(patch("/api/orders/{id}/confirm-my-location", 99L)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"lat\": 33.5, \"lng\": 720.5}")
                        .principal(new UsernamePasswordAuthenticationToken(RECIPIENT_PHONE, null)))
                .andReturn();

        int status = result.getResponse().getStatus();
        assertThat(status).isGreaterThanOrEqualTo(400).isLessThan(500);
        org.mockito.Mockito.verify(orderRepository, org.mockito.Mockito.never())
                .findById(any());
    }

    // ───────────── POST /api/orders/quote-delivery-fee ─────────────

    @Test
    void quoteDeliveryFee_rejectsNonFiniteCoordinate_asCleanRejection() throws Exception {
        var result = mockMvc.perform(post("/api/orders/quote-delivery-fee")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"pickupLat\": 1e400, \"pickupLng\": 35.5,"
                                + " \"deliveryLat\": 33.9, \"deliveryLng\": 35.5}"))
                .andReturn();

        int status = result.getResponse().getStatus();
        assertThat(status).isGreaterThanOrEqualTo(400).isLessThan(500);
    }

    @Test
    void quoteDeliveryFee_acceptsValidCoordinates() throws Exception {
        var result = mockMvc.perform(post("/api/orders/quote-delivery-fee")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"pickupLat\": 33.5, \"pickupLng\": 36.3,"
                                + " \"deliveryLat\": 33.51, \"deliveryLng\": 36.31}"))
                .andReturn();

        assertThat(result.getResponse().getStatus()).isEqualTo(200);
    }
}
