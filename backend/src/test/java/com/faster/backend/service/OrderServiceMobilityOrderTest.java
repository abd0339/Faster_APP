package com.faster.backend.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.messaging.simp.SimpMessagingTemplate;

import com.faster.backend.entity.Order;
import com.faster.backend.entity.User;
import com.faster.backend.repository.OrderRepository;
import com.faster.backend.repository.UserRepository;

/**
 * Full-codebase review fix round (2026-11) — createMobilityOrder received
 * a recipientPhone parameter (the same offlineCustomerPhone field O2O/
 * Direct-Delivery use) but never persisted it onto the Order and never
 * notified the recipient, unlike its two siblings which both do.
 */
@ExtendWith(MockitoExtension.class)
class OrderServiceMobilityOrderTest {

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

    private static final long CUSTOMER_ID = 1L;
    private static final String RECIPIENT_PHONE = "+96171111111";

    @BeforeEach
    void setUp() {
        orderService = new OrderService(
                orderRepository, userRepository, locationService,
                messagingTemplate, ledgerService, communicationService,
                pricingService, pushNotificationService);

        when(userRepository.findById(CUSTOMER_ID))
                .thenReturn(Optional.of(User.builder().id(CUSTOMER_ID).build()));
        when(pricingService.calculateRideFee(any(), any(), any(), any()))
                .thenReturn(new BigDecimal("5.00"));
        when(orderRepository.save(any(Order.class)))
                .thenAnswer(inv -> inv.getArgument(0));
    }

    @Test
    void createMobilityOrder_persistsAndNotifiesRecipientPhoneWhenProvided() {
        Order saved = orderService.createMobilityOrder(
                CUSTOMER_ID, 33.5, 36.3, "pickup",
                33.6, 36.4, "dropoff", RECIPIENT_PHONE, "notes");

        assertEquals(RECIPIENT_PHONE, saved.getOfflineCustomerPhone());
        verify(communicationService, times(1)).sendO2OTrackingLink(saved);
    }

    @Test
    void createMobilityOrder_noRecipientPhone_doesNotCrashAndStillSaves() {
        Order saved = orderService.createMobilityOrder(
                CUSTOMER_ID, 33.5, 36.3, "pickup",
                33.6, 36.4, "dropoff", null, "notes");

        assertEquals(null, saved.getOfflineCustomerPhone());
        verify(communicationService, times(1)).sendO2OTrackingLink(saved);
    }
}
