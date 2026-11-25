package com.faster.backend.service;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.when;

import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.messaging.simp.SimpMessagingTemplate;

import com.faster.backend.entity.Order;
import com.faster.backend.entity.User;
import com.faster.backend.exception.BusinessException;
import com.faster.backend.repository.OrderRepository;
import com.faster.backend.repository.UserRepository;

/**
 * Full-codebase review fix round (2026-11) — acceptOrder used to check
 * only driver.getIsBlocked(), never driver.getVerificationStatus(). Only
 * goOnline enforced APPROVED, and nothing forces an already-online driver
 * offline when an admin later rejects their verification — so a driver
 * rejected for fraud after going online could keep accepting orders
 * indefinitely.
 */
@ExtendWith(MockitoExtension.class)
class OrderServiceAcceptOrderTest {

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

    private static final long DRIVER_ID = 2L;
    private static final long ORDER_ID = 99L;

    @BeforeEach
    void setUp() {
        orderService = new OrderService(
                orderRepository, userRepository, locationService,
                messagingTemplate, ledgerService, communicationService,
                pricingService, pushNotificationService);
    }

    private User driverWith(User.DriverVerificationStatus status, boolean blocked) {
        return User.builder()
                .id(DRIVER_ID)
                .role(User.Role.DRIVER)
                .isBlocked(blocked)
                .verificationStatus(status)
                .build();
    }

    @Test
    void acceptOrder_rejectsRejectedDriverEvenIfNotBlocked() {
        when(userRepository.findById(DRIVER_ID))
                .thenReturn(Optional.of(
                        driverWith(User.DriverVerificationStatus.REJECTED, false)));

        assertThrows(BusinessException.class,
                () -> orderService.acceptOrder(DRIVER_ID, ORDER_ID));
    }

    @Test
    void acceptOrder_rejectsPendingVerificationDriver() {
        when(userRepository.findById(DRIVER_ID))
                .thenReturn(Optional.of(
                        driverWith(User.DriverVerificationStatus.PENDING, false)));

        assertThrows(BusinessException.class,
                () -> orderService.acceptOrder(DRIVER_ID, ORDER_ID));
    }

    @Test
    void acceptOrder_allowsApprovedUnblockedDriver() {
        User driver = driverWith(User.DriverVerificationStatus.APPROVED, false);
        Order order = Order.builder().id(ORDER_ID).build();

        when(userRepository.findById(DRIVER_ID)).thenReturn(Optional.of(driver));
        when(orderRepository.assignDriver(anyLong(), anyLong(), any())).thenReturn(1);
        lenient().when(orderRepository.findById(ORDER_ID)).thenReturn(Optional.of(order));

        assertDoesNotThrow(() -> orderService.acceptOrder(DRIVER_ID, ORDER_ID));
    }
}
