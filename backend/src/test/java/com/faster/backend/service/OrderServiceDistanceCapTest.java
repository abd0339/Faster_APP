package com.faster.backend.service;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.messaging.simp.SimpMessagingTemplate;

import com.faster.backend.dto.OrderItemLineRequest;
import com.faster.backend.entity.Order;
import com.faster.backend.entity.User;
import com.faster.backend.exception.BusinessException;
import com.faster.backend.repository.OrderRepository;
import com.faster.backend.repository.UserRepository;

/**
 * Covers Task 5 of the input-hardening plan — the three order-creation
 * entry points (LOGISTICS branch of createOrder, createDirectDeliveryOrder,
 * createO2OOrder) must reject at creation time when
 * PricingService.exceedsMaxDeliveryDistance(...) (Task 3) says the
 * pickup→delivery pair is too far apart, and must NOT touch
 * orderRepository.save in that case.
 *
 * createO2OOrder's "phone bridge" flow (offline customer shares location
 * later) legitimately creates orders with null delivery coordinates —
 * exceedsMaxDeliveryDistance already returns false for that by design
 * (Task 3), so that path must keep working unchanged.
 */
@ExtendWith(MockitoExtension.class)
class OrderServiceDistanceCapTest {

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

    @BeforeEach
    void setUp() {
        orderService = new OrderService(
                orderRepository, userRepository, locationService,
                messagingTemplate, ledgerService, communicationService,
                pricingService, pushNotificationService);
    }

    private User userWithNoStoreLocation(Long id) {
        return User.builder().id(id).build();
    }

    @Test
    void createOrder_rejectsLogisticsOrderBeyondMaxDistance() {
        Long merchantId = 1L;
        Long customerId = 2L;

        when(userRepository.findById(merchantId))
                .thenReturn(Optional.of(userWithNoStoreLocation(merchantId)));
        when(userRepository.findById(customerId))
                .thenReturn(Optional.of(userWithNoStoreLocation(customerId)));
        when(pricingService.calculateItemsTotal(eq(merchantId), any()))
                .thenReturn(new BigDecimal("10.00"));
        when(pricingService.calculateDeliveryFee(any(), any(), any(), any()))
                .thenReturn(new BigDecimal("1.00"));
        when(pricingService.exceedsMaxDeliveryDistance(any(), any(), any(), any()))
                .thenReturn(true);

        assertThrows(BusinessException.class, () -> orderService.createOrder(
                merchantId, customerId, List.<OrderItemLineRequest>of(),
                33.5, 36.3, "Pickup address",
                34.5, 37.3, "Delivery address",
                "notes", Order.OrderType.LOGISTICS));

        verifyNoSave();
    }

    @Test
    void createDirectDeliveryOrder_rejectsBeyondMaxDistance() {
        Long customerId = 2L;

        when(userRepository.findById(customerId))
                .thenReturn(Optional.of(userWithNoStoreLocation(customerId)));
        when(pricingService.calculateDeliveryFee(any(), any(), any(), any()))
                .thenReturn(new BigDecimal("1.00"));
        when(pricingService.exceedsMaxDeliveryDistance(any(), any(), any(), any()))
                .thenReturn(true);

        assertThrows(BusinessException.class, () -> orderService.createDirectDeliveryOrder(
                customerId, new BigDecimal("15.00"),
                33.5, 36.3, "Pickup address",
                34.5, 37.3, "Delivery address",
                "+96170000000", "notes"));

        verifyNoSave();
    }

    @Test
    void createO2OOrder_rejectsBeyondMaxDistance() {
        Long merchantId = 1L;

        when(userRepository.findById(merchantId))
                .thenReturn(Optional.of(userWithNoStoreLocation(merchantId)));
        when(pricingService.validateO2OPrice(any())).thenReturn(null);
        when(pricingService.calculateDeliveryFee(any(), any(), any(), any()))
                .thenReturn(new BigDecimal("1.00"));
        when(pricingService.exceedsMaxDeliveryDistance(any(), any(), any(), any()))
                .thenReturn(true);

        assertThrows(BusinessException.class, () -> orderService.createO2OOrder(
                merchantId, "+96170000000", "Near the big mosque",
                new BigDecimal("50.00"),
                33.5, 36.3, "Pickup address",
                34.5, 37.3));

        verifyNoSave();
    }

    @Test
    void createO2OOrder_allowsWhenDeliveryCoordsNullAtCreation() {
        Long merchantId = 1L;

        when(userRepository.findById(merchantId))
                .thenReturn(Optional.of(userWithNoStoreLocation(merchantId)));
        when(pricingService.validateO2OPrice(any())).thenReturn(null);
        when(pricingService.calculateDeliveryFee(any(), any(), any(), any()))
                .thenReturn(new BigDecimal("1.00"));
        // Per Task 3's null-safety contract: can't evaluate distance
        // without delivery coords, so this returns false, not true.
        when(pricingService.exceedsMaxDeliveryDistance(any(), any(), any(), any()))
                .thenReturn(false);
        when(locationService.findNearestPackageDrivers(anyDouble(), anyDouble(), anyDouble()))
                .thenReturn(List.of());
        when(orderRepository.save(any(Order.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        Order saved = assertDoesNotThrow(() -> orderService.createO2OOrder(
                merchantId, "+96170000000", "Near the big mosque",
                new BigDecimal("50.00"),
                33.5, 36.3, "Pickup address",
                null, null));

        org.junit.jupiter.api.Assertions.assertNotNull(saved);
    }

    private void verifyNoSave() {
        verify(orderRepository, never()).save(any());
    }
}
