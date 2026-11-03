package com.faster.backend.service;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.util.Map;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.messaging.simp.SimpMessagingTemplate;

import com.faster.backend.entity.Order;
import com.faster.backend.exception.BusinessException;
import com.faster.backend.repository.OrderRepository;
import com.faster.backend.repository.UserRepository;

/**
 * Covers Task 6 of the input-hardening plan — confirmRecipientLocation and
 * updateTrackingLocation must FLAG (not reject-and-rollback) location
 * updates that fall beyond PricingService.exceedsMaxDeliveryDistance(...)'s
 * cap (Task 3), using Order.isDistanceFlagged/distanceFlagReason (Task 4).
 *
 * Unlike order-creation (Task 5), these methods act on an order that
 * already exists and may already be accepted by a driver, so a beyond-cap
 * location must NOT throw — that would roll back the whole @Transactional
 * method, including the flag itself. Instead: skip the lat/lng mutation
 * and the fee/commission/grandTotal recompute, set the flag, save, and
 * broadcast + return exactly as the normal path does.
 */
@ExtendWith(MockitoExtension.class)
class OrderServiceLocationFlagTest {

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
    private PricingService pricingService;

    @Mock
    private PushNotificationService pushNotificationService;

    private OrderService orderService;

    private static final String TRACKING_CODE = "FST-20261103-TEST";
    private static final String RECIPIENT_PHONE = "+96170000000";
    private static final double PICKUP_LAT = 33.5;
    private static final double PICKUP_LNG = 36.3;
    private static final double EXISTING_DELIVERY_LAT = 33.52;
    private static final double EXISTING_DELIVERY_LNG = 36.32;
    private static final BigDecimal EXISTING_DELIVERY_FEE = new BigDecimal("5.00");
    private static final BigDecimal EXISTING_COMMISSION = new BigDecimal("1.00");
    private static final BigDecimal EXISTING_GRAND_TOTAL = new BigDecimal("20.00");

    // A location far enough that exceedsMaxDeliveryDistance is mocked true
    // for it; the actual value doesn't matter since the check is stubbed.
    private static final double FAR_LAT = 40.0;
    private static final double FAR_LNG = 45.0;

    // A location within cap; exceedsMaxDeliveryDistance mocked false.
    private static final double NEAR_LAT = 33.55;
    private static final double NEAR_LNG = 36.35;

    @BeforeEach
    void setUp() {
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
                .pickupLat(PICKUP_LAT)
                .pickupLng(PICKUP_LNG)
                .deliveryLat(EXISTING_DELIVERY_LAT)
                .deliveryLng(EXISTING_DELIVERY_LNG)
                .deliveryFee(EXISTING_DELIVERY_FEE)
                .commissionAmount(EXISTING_COMMISSION)
                .totalPrice(new BigDecimal("15.00"))
                .grandTotal(EXISTING_GRAND_TOTAL)
                .isDistanceFlagged(false)
                .build();
    }

    // ───────────────────────── updateTrackingLocation ─────────────────────────

    @Test
    void updateTrackingLocation_flagsWithoutMutatingWhenBeyondCap() {
        Order order = existingOrder();
        when(orderRepository.findByTrackingCode(TRACKING_CODE))
                .thenReturn(Optional.of(order));
        when(pricingService.exceedsMaxDeliveryDistance(
                PICKUP_LAT, PICKUP_LNG, FAR_LAT, FAR_LNG))
                .thenReturn(true);
        when(orderRepository.save(any(Order.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        Order result = orderService.updateTrackingLocation(TRACKING_CODE, FAR_LAT, FAR_LNG);

        // Location and money must be UNCHANGED from before the call.
        assertEquals(EXISTING_DELIVERY_LAT, result.getDeliveryLat());
        assertEquals(EXISTING_DELIVERY_LNG, result.getDeliveryLng());
        assertEquals(EXISTING_DELIVERY_FEE, result.getDeliveryFee());
        assertEquals(EXISTING_COMMISSION, result.getCommissionAmount());
        assertEquals(EXISTING_GRAND_TOTAL, result.getGrandTotal());

        assertTrue(result.getIsDistanceFlagged());
        assertNotNull(result.getDistanceFlagReason());

        verify(orderRepository).save(order);
        verify(messagingTemplate).convertAndSend(
                eq("/topic/order/" + order.getId()),
                any(Object.class));
    }

    @Test
    void updateTrackingLocation_doesNotThrowWhenBeyondCap() {
        Order order = existingOrder();
        when(orderRepository.findByTrackingCode(TRACKING_CODE))
                .thenReturn(Optional.of(order));
        when(pricingService.exceedsMaxDeliveryDistance(
                PICKUP_LAT, PICKUP_LNG, FAR_LAT, FAR_LNG))
                .thenReturn(true);
        when(orderRepository.save(any(Order.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        assertDoesNotThrow(() -> orderService.updateTrackingLocation(TRACKING_CODE, FAR_LAT, FAR_LNG));
    }

    @Test
    void updateTrackingLocation_appliesNormallyWhenWithinCap() {
        Order order = existingOrder();
        BigDecimal newFee = new BigDecimal("6.00");
        when(orderRepository.findByTrackingCode(TRACKING_CODE))
                .thenReturn(Optional.of(order));
        when(pricingService.exceedsMaxDeliveryDistance(
                PICKUP_LAT, PICKUP_LNG, NEAR_LAT, NEAR_LNG))
                .thenReturn(false);
        when(pricingService.calculateDeliveryFee(
                PICKUP_LAT, PICKUP_LNG, NEAR_LAT, NEAR_LNG))
                .thenReturn(newFee);
        when(orderRepository.save(any(Order.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        Order result = orderService.updateTrackingLocation(TRACKING_CODE, NEAR_LAT, NEAR_LNG);

        assertEquals(NEAR_LAT, result.getDeliveryLat());
        assertEquals(NEAR_LNG, result.getDeliveryLng());
        assertEquals(newFee, result.getDeliveryFee());
        assertFalse(result.getIsDistanceFlagged());
    }

    // ──────────────────────── confirmRecipientLocation ─────────────────────────

    @Test
    void confirmRecipientLocation_flagsWithoutMutatingWhenBeyondCap() {
        Order order = existingOrder();
        when(orderRepository.findById(order.getId()))
                .thenReturn(Optional.of(order));
        when(pricingService.exceedsMaxDeliveryDistance(
                PICKUP_LAT, PICKUP_LNG, FAR_LAT, FAR_LNG))
                .thenReturn(true);
        when(orderRepository.save(any(Order.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        Order result = orderService.confirmRecipientLocation(
                order.getId(), RECIPIENT_PHONE, FAR_LAT, FAR_LNG);

        assertEquals(EXISTING_DELIVERY_LAT, result.getDeliveryLat());
        assertEquals(EXISTING_DELIVERY_LNG, result.getDeliveryLng());
        assertEquals(EXISTING_DELIVERY_FEE, result.getDeliveryFee());
        assertEquals(EXISTING_COMMISSION, result.getCommissionAmount());
        assertEquals(EXISTING_GRAND_TOTAL, result.getGrandTotal());

        assertTrue(result.getIsDistanceFlagged());
        assertNotNull(result.getDistanceFlagReason());

        verify(orderRepository).save(order);
    }

    @Test
    void confirmRecipientLocation_doesNotThrowWhenBeyondCap() {
        Order order = existingOrder();
        when(orderRepository.findById(order.getId()))
                .thenReturn(Optional.of(order));
        when(pricingService.exceedsMaxDeliveryDistance(
                PICKUP_LAT, PICKUP_LNG, FAR_LAT, FAR_LNG))
                .thenReturn(true);
        when(orderRepository.save(any(Order.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        assertDoesNotThrow(() -> orderService.confirmRecipientLocation(
                order.getId(), RECIPIENT_PHONE, FAR_LAT, FAR_LNG));
    }

    @Test
    void confirmRecipientLocation_appliesNormallyWhenWithinCap() {
        Order order = existingOrder();
        BigDecimal newFee = new BigDecimal("6.50");
        when(orderRepository.findById(order.getId()))
                .thenReturn(Optional.of(order));
        when(pricingService.exceedsMaxDeliveryDistance(
                PICKUP_LAT, PICKUP_LNG, NEAR_LAT, NEAR_LNG))
                .thenReturn(false);
        when(pricingService.calculateDeliveryFee(
                PICKUP_LAT, PICKUP_LNG, NEAR_LAT, NEAR_LNG))
                .thenReturn(newFee);
        when(orderRepository.save(any(Order.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        Order result = orderService.confirmRecipientLocation(
                order.getId(), RECIPIENT_PHONE, NEAR_LAT, NEAR_LNG);

        assertEquals(NEAR_LAT, result.getDeliveryLat());
        assertEquals(NEAR_LNG, result.getDeliveryLng());
        assertEquals(newFee, result.getDeliveryFee());
        assertFalse(result.getIsDistanceFlagged());
    }

    // ──────────────────────────────────────────────────────────────────
    // "A flood of updateTrackingLocation calls" is not exercised here —
    // each call is independent/stateless from this method's own logic
    // (no in-memory debounce or rate limit exists, by design, same as
    // every other public endpoint in this codebase); the only risk a
    // flood introduces is a classic concurrent read-modify-write race on
    // the Order row across two overlapping requests, which is a
    // datastore-locking concern spanning the whole app, not something
    // Task 6 introduced or this task should redesign. Flagged in the
    // task-12 report instead.

    @Test
    void updateTrackingLocation_rejectsWhenOrderAlreadyDelivered() {
        Order order = existingOrder();
        order.setStatus(Order.OrderStatus.DELIVERED);
        when(orderRepository.findByTrackingCode(TRACKING_CODE))
                .thenReturn(Optional.of(order));

        assertThrows(BusinessException.class, () -> orderService.updateTrackingLocation(
                TRACKING_CODE, NEAR_LAT, NEAR_LNG));

        verify(orderRepository, never()).save(any());
    }

    @Test
    void updateTrackingLocation_rejectsWhenOrderAlreadyCancelled() {
        Order order = existingOrder();
        order.setStatus(Order.OrderStatus.CANCELLED);
        when(orderRepository.findByTrackingCode(TRACKING_CODE))
                .thenReturn(Optional.of(order));

        assertThrows(BusinessException.class, () -> orderService.updateTrackingLocation(
                TRACKING_CODE, NEAR_LAT, NEAR_LNG));

        verify(orderRepository, never()).save(any());
    }

    @Test
    void confirmRecipientLocation_rejectsWhenOrderAlreadyDelivered() {
        Order order = existingOrder();
        order.setStatus(Order.OrderStatus.DELIVERED);
        when(orderRepository.findById(order.getId()))
                .thenReturn(Optional.of(order));

        assertThrows(BusinessException.class, () -> orderService.confirmRecipientLocation(
                order.getId(), RECIPIENT_PHONE, NEAR_LAT, NEAR_LNG));

        verify(orderRepository, never()).save(any());
    }

    @Test
    void confirmRecipientLocation_rejectsWhenOrderAlreadyCancelled() {
        Order order = existingOrder();
        order.setStatus(Order.OrderStatus.CANCELLED);
        when(orderRepository.findById(order.getId()))
                .thenReturn(Optional.of(order));

        assertThrows(BusinessException.class, () -> orderService.confirmRecipientLocation(
                order.getId(), RECIPIENT_PHONE, NEAR_LAT, NEAR_LNG));

        verify(orderRepository, never()).save(any());
    }

    // ───────────────── Final whole-branch review, finding #1 ─────────────────
    // Two gaps the final review found in this already-implemented flag
    // path: (a) a PREVIOUSLY-flagged order that's later successfully
    // retried within the cap must have the flag cleared — otherwise
    // OrderController's new honest flagged/success response (reads
    // this method's returned Order.isDistanceFlagged) would stay stuck
    // reporting "flagged" forever after a single bad attempt, even
    // though the retry worked; and (b) buildStatusUpdate's broadcast
    // must carry the flag so anyone watching /topic/order/{id}
    // (including an admin dashboard) can see it, not just the DB.

    @Test
    void updateTrackingLocation_clearsPreviousFlagOnceWithinCap() {
        Order order = existingOrder();
        order.setIsDistanceFlagged(true);
        order.setDistanceFlagReason("Reported location is beyond the maximum delivery distance from pickup");
        BigDecimal newFee = new BigDecimal("6.00");
        when(orderRepository.findByTrackingCode(TRACKING_CODE))
                .thenReturn(Optional.of(order));
        when(pricingService.exceedsMaxDeliveryDistance(
                PICKUP_LAT, PICKUP_LNG, NEAR_LAT, NEAR_LNG))
                .thenReturn(false);
        when(pricingService.calculateDeliveryFee(
                PICKUP_LAT, PICKUP_LNG, NEAR_LAT, NEAR_LNG))
                .thenReturn(newFee);
        when(orderRepository.save(any(Order.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        Order result = orderService.updateTrackingLocation(TRACKING_CODE, NEAR_LAT, NEAR_LNG);

        assertFalse(result.getIsDistanceFlagged());
        assertNull(result.getDistanceFlagReason());
    }

    @Test
    void confirmRecipientLocation_clearsPreviousFlagOnceWithinCap() {
        Order order = existingOrder();
        order.setIsDistanceFlagged(true);
        order.setDistanceFlagReason("Reported location is beyond the maximum delivery distance from pickup");
        BigDecimal newFee = new BigDecimal("6.50");
        when(orderRepository.findById(order.getId()))
                .thenReturn(Optional.of(order));
        when(pricingService.exceedsMaxDeliveryDistance(
                PICKUP_LAT, PICKUP_LNG, NEAR_LAT, NEAR_LNG))
                .thenReturn(false);
        when(pricingService.calculateDeliveryFee(
                PICKUP_LAT, PICKUP_LNG, NEAR_LAT, NEAR_LNG))
                .thenReturn(newFee);
        when(orderRepository.save(any(Order.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        Order result = orderService.confirmRecipientLocation(
                order.getId(), RECIPIENT_PHONE, NEAR_LAT, NEAR_LNG);

        assertFalse(result.getIsDistanceFlagged());
        assertNull(result.getDistanceFlagReason());
    }

    @Test
    @SuppressWarnings("unchecked")
    void updateTrackingLocation_broadcastsDistanceFlaggedWhenBeyondCap() {
        Order order = existingOrder();
        when(orderRepository.findByTrackingCode(TRACKING_CODE))
                .thenReturn(Optional.of(order));
        when(pricingService.exceedsMaxDeliveryDistance(
                PICKUP_LAT, PICKUP_LNG, FAR_LAT, FAR_LNG))
                .thenReturn(true);
        when(orderRepository.save(any(Order.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        orderService.updateTrackingLocation(TRACKING_CODE, FAR_LAT, FAR_LNG);

        ArgumentCaptor<Map<String, Object>> captor = ArgumentCaptor.forClass(Map.class);
        verify(messagingTemplate).convertAndSend(
                eq("/topic/order/" + order.getId()), captor.capture());

        assertEquals(Boolean.TRUE, captor.getValue().get("distanceFlagged"));
    }

    @Test
    @SuppressWarnings("unchecked")
    void updateTrackingLocation_broadcastsDistanceNotFlaggedWhenWithinCap() {
        Order order = existingOrder();
        BigDecimal newFee = new BigDecimal("6.00");
        when(orderRepository.findByTrackingCode(TRACKING_CODE))
                .thenReturn(Optional.of(order));
        when(pricingService.exceedsMaxDeliveryDistance(
                PICKUP_LAT, PICKUP_LNG, NEAR_LAT, NEAR_LNG))
                .thenReturn(false);
        when(pricingService.calculateDeliveryFee(
                PICKUP_LAT, PICKUP_LNG, NEAR_LAT, NEAR_LNG))
                .thenReturn(newFee);
        when(orderRepository.save(any(Order.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        orderService.updateTrackingLocation(TRACKING_CODE, NEAR_LAT, NEAR_LNG);

        ArgumentCaptor<Map<String, Object>> captor = ArgumentCaptor.forClass(Map.class);
        verify(messagingTemplate).convertAndSend(
                eq("/topic/order/" + order.getId()), captor.capture());

        assertEquals(Boolean.FALSE, captor.getValue().get("distanceFlagged"));
    }
}
