package com.faster.backend.service;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTimeoutPreemptively;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.time.Duration;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.test.util.ReflectionTestUtils;

import com.faster.backend.entity.Order;
import com.faster.backend.exception.BusinessException;
import com.faster.backend.repository.ItemAddonRepository;
import com.faster.backend.repository.ItemRepository;
import com.faster.backend.repository.ModifierOptionRepository;
import com.faster.backend.repository.OrderRepository;
import com.faster.backend.repository.UserRepository;

/**
 * Coordinate and price validation on OrderService:
 *
 * quoteDeliveryFee, updateTrackingLocation, and confirmRecipientLocation
 * all take raw lat/lng off a Map&lt;String, Double&gt; request body with no
 * DTO/@Valid layer (unlike OrderRequest/createOrder). A finite-but-out-of-
 * range coordinate (e.g. pickupLat + 360, which wraps back onto a real
 * point on the sphere) is never caught by PricingService's non-finite-
 * distance guard alone, so without an explicit range check it would pass
 * the distance cap at a near-zero computed distance and get persisted/
 * broadcast as a corrupted location — most seriously on
 * updateTrackingLocation, which is PUBLIC and unauthenticated. This uses
 * the REAL OrderService (not a mocked one), so it genuinely exercises the
 * validation path all the way through.
 *
 * Direct Delivery's itemValue also has no upper bound otherwise, while
 * Order.totalPrice/grandTotal are NUMERIC(10,2) columns (max
 * 99,999,999.99) — an oversized value would overflow them with a raw,
 * leaky DataIntegrityViolationException once actually persisted.
 */
@ExtendWith(MockitoExtension.class)
class OrderServiceCoordinateAndPriceValidationTest {

    @Mock
    private OrderRepository orderRepository;

    @Mock
    private UserRepository userRepository;

    @Mock
    private LocationService locationService;

    @Mock
    private SimpMessagingTemplate messagingTemplate;

    @Mock
    private LedgerService ledgerService;

    @Mock
    private CommunicationService communicationService;

    @Mock
    private PushNotificationService pushNotificationService;

    @Mock
    private ItemRepository itemRepository;

    @Mock
    private ModifierOptionRepository modifierOptionRepository;

    @Mock
    private ItemAddonRepository addonRepository;

    private PricingService pricingService;
    private OrderService orderService;

    private static final String TRACKING_CODE = "FST-20261103-COORD";
    private static final String RECIPIENT_PHONE = "+96170000000";
    private static final double VALID_LAT = 33.5;
    private static final double VALID_LNG = 36.3;

    // A coordinate that "wraps" to a real point on the sphere once you
    // apply trig functions to it, but is not a legitimate latitude.
    private static final double OUT_OF_RANGE_LAT = 393.8938;
    private static final double OUT_OF_RANGE_LNG = 720.5018;

    @BeforeEach
    void setUp() {
        pricingService = new PricingService(
                itemRepository, modifierOptionRepository, addonRepository);
        ReflectionTestUtils.setField(pricingService, "maxDeliveryDistanceKm", 6.0);
        ReflectionTestUtils.setField(
                pricingService, "deliveryBaseFee", new BigDecimal("1.00"));
        ReflectionTestUtils.setField(
                pricingService, "deliveryRatePerKm", new BigDecimal("0.50"));
        ReflectionTestUtils.setField(
                pricingService, "deliveryMinFee", new BigDecimal("1.50"));
        ReflectionTestUtils.setField(
                pricingService, "directDeliveryMaxItemValue", new BigDecimal("50000.00"));
        ReflectionTestUtils.setField(
                pricingService, "o2oMinPrice", new BigDecimal("1.00"));
        ReflectionTestUtils.setField(
                pricingService, "o2oMaxPrice", new BigDecimal("1000.00"));
        ReflectionTestUtils.setField(
                pricingService, "o2oReviewThreshold", new BigDecimal("5.00"));

        orderService = new OrderService(
                orderRepository, userRepository, locationService,
                messagingTemplate, ledgerService, communicationService,
                pricingService, pushNotificationService);
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

    // ───────────────────────── quoteDeliveryFee ─────────────────────────

    @Test
    void quoteDeliveryFee_rejectsOutOfRangeLatitude() {
        assertThrows(BusinessException.class, () -> orderService.quoteDeliveryFee(
                OUT_OF_RANGE_LAT, VALID_LNG, VALID_LAT, VALID_LNG));
    }

    @Test
    void quoteDeliveryFee_rejectsOutOfRangeLongitude() {
        assertThrows(BusinessException.class, () -> orderService.quoteDeliveryFee(
                VALID_LAT, OUT_OF_RANGE_LNG, VALID_LAT, VALID_LNG));
    }

    @Test
    void quoteDeliveryFee_rejectsNonFiniteCoordinate() {
        assertThrows(BusinessException.class, () -> orderService.quoteDeliveryFee(
                Double.POSITIVE_INFINITY, VALID_LNG, VALID_LAT, VALID_LNG));
    }

    @Test
    void quoteDeliveryFee_acceptsValidCoordinates() {
        BigDecimal fee = assertDoesNotThrow(() -> orderService.quoteDeliveryFee(
                VALID_LAT, VALID_LNG, VALID_LAT + 0.01, VALID_LNG + 0.01));
        org.junit.jupiter.api.Assertions.assertNotNull(fee);
    }

    // ───────────────────────── updateTrackingLocation ─────────────────────────
    // PUBLIC, unauthenticated endpoint — the highest-risk one to get
    // wrong. Must reject BEFORE the flag-path/fee-calc logic runs, and
    // must never touch the repository for an invalid request.

    @Test
    void updateTrackingLocation_rejectsOutOfRangeLatitude_withoutTouchingRepository() {
        assertThrows(BusinessException.class, () -> orderService.updateTrackingLocation(
                TRACKING_CODE, OUT_OF_RANGE_LAT, VALID_LNG));

        verify(orderRepository, never()).findByTrackingCode(any());
        verify(orderRepository, never()).save(any());
    }

    @Test
    void updateTrackingLocation_rejectsOutOfRangeLongitude_withoutTouchingRepository() {
        assertThrows(BusinessException.class, () -> orderService.updateTrackingLocation(
                TRACKING_CODE, VALID_LAT, OUT_OF_RANGE_LNG));

        verify(orderRepository, never()).findByTrackingCode(any());
    }

    @Test
    void updateTrackingLocation_rejectsNonFiniteLatitude_insteadOfSilentlyFlagging() {
        // Without this guard: Double.POSITIVE_INFINITY would make
        // exceedsMaxDeliveryDistance's non-finite check return true,
        // taking the FLAG path (200 OK,
        // order silently flagged "beyond max delivery distance") instead
        // of a clean rejection — on a public, unauthenticated endpoint.
        // This must now throw before ever reaching that logic — and
        // before the order is even fetched.
        assertThrows(BusinessException.class, () -> orderService.updateTrackingLocation(
                TRACKING_CODE, Double.POSITIVE_INFINITY, VALID_LNG));

        verify(orderRepository, never()).findByTrackingCode(any());
        verify(orderRepository, never()).save(any());
    }

    @Test
    void updateTrackingLocation_acceptsValidCoordinates() {
        Order order = existingOrder();
        when(orderRepository.findByTrackingCode(TRACKING_CODE))
                .thenReturn(Optional.of(order));
        when(orderRepository.save(any(Order.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        Order result = assertDoesNotThrow(() -> orderService.updateTrackingLocation(
                TRACKING_CODE, VALID_LAT + 0.0001, VALID_LNG + 0.0001));

        org.junit.jupiter.api.Assertions.assertNotNull(result);
    }

    // ───────────────────────── confirmRecipientLocation ─────────────────────────

    @Test
    void confirmRecipientLocation_rejectsOutOfRangeLatitude_withoutTouchingRepository() {
        assertThrows(BusinessException.class, () -> orderService.confirmRecipientLocation(
                99L, RECIPIENT_PHONE, OUT_OF_RANGE_LAT, VALID_LNG));

        verify(orderRepository, never()).findById(any());
    }

    @Test
    void confirmRecipientLocation_rejectsNonFiniteLongitude_insteadOfSilentlyFlagging() {
        assertThrows(BusinessException.class, () -> orderService.confirmRecipientLocation(
                99L, RECIPIENT_PHONE, VALID_LAT, Double.NEGATIVE_INFINITY));

        verify(orderRepository, never()).save(any());
    }

    // ───────────────────────── createDirectDeliveryOrder ─────────────────────────

    @Test
    void createDirectDeliveryOrder_rejectsItemValueAboveMax() {
        when(userRepository.findById(2L))
                .thenReturn(Optional.of(com.faster.backend.entity.User.builder().id(2L).build()));

        assertThrows(BusinessException.class, () -> orderService.createDirectDeliveryOrder(
                2L, new BigDecimal("50000.01"),
                VALID_LAT, VALID_LNG, "Pickup",
                VALID_LAT + 0.01, VALID_LNG + 0.01, "Delivery",
                RECIPIENT_PHONE, "notes"));

        verify(orderRepository, never()).save(any());
    }

    @Test
    void createDirectDeliveryOrder_rejectsAbsurdlyHugeItemValue() {
        when(userRepository.findById(2L))
                .thenReturn(Optional.of(com.faster.backend.entity.User.builder().id(2L).build()));

        // "1e10" and a many-digit value, per the task brief's own
        // adversarial examples.
        assertThrows(BusinessException.class, () -> orderService.createDirectDeliveryOrder(
                2L, new BigDecimal("1E10"),
                VALID_LAT, VALID_LNG, "Pickup",
                VALID_LAT + 0.01, VALID_LNG + 0.01, "Delivery",
                RECIPIENT_PHONE, "notes"));

        verify(orderRepository, never()).save(any());
    }

    @Test
    void createDirectDeliveryOrder_acceptsItemValueAtExactMax() {
        when(userRepository.findById(2L))
                .thenReturn(Optional.of(com.faster.backend.entity.User.builder().id(2L).build()));
        when(locationService.findNearestPackageDrivers(
                org.mockito.ArgumentMatchers.anyDouble(),
                org.mockito.ArgumentMatchers.anyDouble(),
                org.mockito.ArgumentMatchers.anyDouble()))
                .thenReturn(java.util.List.of());
        when(orderRepository.save(any(Order.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        Order result = assertDoesNotThrow(() -> orderService.createDirectDeliveryOrder(
                2L, new BigDecimal("50000.00"),
                VALID_LAT, VALID_LNG, "Pickup",
                VALID_LAT + 0.01, VALID_LNG + 0.01, "Delivery",
                RECIPIENT_PHONE, "notes"));

        org.junit.jupiter.api.Assertions.assertEquals(
                new BigDecimal("50000.00"), result.getTotalPrice());
    }

    // ───────────────────────────────────────────────────────────
    // BigDecimal scale/exponent DoS: a huge-exponent itemValue/
    // totalPrice makes an unguarded `.setScale(2, ...)` call in both
    // createDirectDeliveryOrder and createO2OOrder take ~8.8 SECONDS,
    // measured directly in this codebase, before the bound checks
    // (validateDirectDeliveryItemValue/validateO2OPrice) ever get a
    // chance to run. assertTimeoutPreemptively is the proof
    // this needs — it fails the test outright if execution takes
    // anywhere near that long, which a reordering regression (guard
    // moved back to after setScale) would immediately trigger,
    // regardless of which exception eventually surfaces.
    // ───────────────────────────────────────────────────────────
    @Test
    void createDirectDeliveryOrder_rejectsHugeExponentItemValue_withinTwoSeconds() {
        when(userRepository.findById(2L))
                .thenReturn(Optional.of(com.faster.backend.entity.User.builder().id(2L).build()));
        BigDecimal huge = new BigDecimal("1e10000000");

        assertTimeoutPreemptively(Duration.ofSeconds(2), () ->
                assertThrows(BusinessException.class, () -> orderService.createDirectDeliveryOrder(
                        2L, huge,
                        VALID_LAT, VALID_LNG, "Pickup",
                        VALID_LAT + 0.01, VALID_LNG + 0.01, "Delivery",
                        RECIPIENT_PHONE, "notes")));

        verify(orderRepository, never()).save(any());
    }

    @Test
    void createDirectDeliveryOrder_rejectsHugeNegativeExponentItemValue_withinTwoSeconds() {
        when(userRepository.findById(2L))
                .thenReturn(Optional.of(com.faster.backend.entity.User.builder().id(2L).build()));
        BigDecimal tiny = new BigDecimal("1e-10000000");

        assertTimeoutPreemptively(Duration.ofSeconds(2), () ->
                assertThrows(BusinessException.class, () -> orderService.createDirectDeliveryOrder(
                        2L, tiny,
                        VALID_LAT, VALID_LNG, "Pickup",
                        VALID_LAT + 0.01, VALID_LNG + 0.01, "Delivery",
                        RECIPIENT_PHONE, "notes")));
    }

    @Test
    void createDirectDeliveryOrder_acceptsTypicalItemValue() {
        when(userRepository.findById(2L))
                .thenReturn(Optional.of(com.faster.backend.entity.User.builder().id(2L).build()));
        when(locationService.findNearestPackageDrivers(
                org.mockito.ArgumentMatchers.anyDouble(),
                org.mockito.ArgumentMatchers.anyDouble(),
                org.mockito.ArgumentMatchers.anyDouble()))
                .thenReturn(java.util.List.of());
        when(orderRepository.save(any(Order.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        assertDoesNotThrow(() -> orderService.createDirectDeliveryOrder(
                2L, new BigDecimal("25.00"),
                VALID_LAT, VALID_LNG, "Pickup",
                VALID_LAT + 0.01, VALID_LNG + 0.01, "Delivery",
                RECIPIENT_PHONE, "notes"));
    }

    // ───────────────────────────────────────────────────────────
    // createO2OOrder has the identical exposure: it also calls
    // setScale on a client-influenced BigDecimal before any bounds
    // check (totalPrice.setScale(2, ...) ran before validateO2OPrice).
    // ───────────────────────────────────────────────────────────
    @Test
    void createO2OOrder_rejectsHugeExponentPrice_withinTwoSeconds() {
        when(userRepository.findById(1L))
                .thenReturn(Optional.of(com.faster.backend.entity.User.builder().id(1L).build()));
        BigDecimal huge = new BigDecimal("1e10000000");

        assertTimeoutPreemptively(Duration.ofSeconds(2), () ->
                assertThrows(BusinessException.class, () -> orderService.createO2OOrder(
                        1L, RECIPIENT_PHONE, "Near the mosque", huge,
                        VALID_LAT, VALID_LNG, "Pickup",
                        VALID_LAT + 0.01, VALID_LNG + 0.01)));

        verify(orderRepository, never()).save(any());
    }

    @Test
    void createO2OOrder_rejectsHugeNegativeExponentPrice_withinTwoSeconds() {
        when(userRepository.findById(1L))
                .thenReturn(Optional.of(com.faster.backend.entity.User.builder().id(1L).build()));
        BigDecimal tiny = new BigDecimal("1e-10000000");

        assertTimeoutPreemptively(Duration.ofSeconds(2), () ->
                assertThrows(BusinessException.class, () -> orderService.createO2OOrder(
                        1L, RECIPIENT_PHONE, "Near the mosque", tiny,
                        VALID_LAT, VALID_LNG, "Pickup",
                        VALID_LAT + 0.01, VALID_LNG + 0.01)));
    }

    @Test
    void createO2OOrder_acceptsTypicalPrice() {
        when(userRepository.findById(1L))
                .thenReturn(Optional.of(com.faster.backend.entity.User.builder().id(1L).build()));
        when(locationService.findNearestPackageDrivers(
                org.mockito.ArgumentMatchers.anyDouble(),
                org.mockito.ArgumentMatchers.anyDouble(),
                org.mockito.ArgumentMatchers.anyDouble()))
                .thenReturn(java.util.List.of());
        when(orderRepository.save(any(Order.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        assertDoesNotThrow(() -> orderService.createO2OOrder(
                1L, RECIPIENT_PHONE, "Near the mosque", new BigDecimal("50.00"),
                VALID_LAT, VALID_LNG, "Pickup",
                VALID_LAT + 0.01, VALID_LNG + 0.01));
    }
}
