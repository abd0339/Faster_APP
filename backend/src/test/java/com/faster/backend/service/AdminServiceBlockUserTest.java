package com.faster.backend.service;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.messaging.simp.SimpMessagingTemplate;

import com.faster.backend.entity.User;
import com.faster.backend.repository.LedgerRepository;
import com.faster.backend.repository.OrderRepository;
import com.faster.backend.repository.UserRepository;

/**
 * Full-codebase review fix round (2026-11) — driver_dashboard_screen.dart
 * already has a handler for a "BLOCKED" message on /topic/driver/{id}
 * (stops the GPS stream, disconnects, shows "Account paused"), but
 * nothing in the backend ever sent one — a driver blocked while already
 * online and connected got no proactive signal.
 */
@ExtendWith(MockitoExtension.class)
class AdminServiceBlockUserTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private OrderRepository orderRepository;

    @Mock
    private LedgerRepository ledgerRepository;

    @Mock
    private LedgerService ledgerService;

    @Mock
    private OrderService orderService;

    @Mock
    private SimpMessagingTemplate messagingTemplate;

    private AdminService adminService;

    private static final long DRIVER_ID = 7L;
    private static final long MERCHANT_ID = 8L;

    @BeforeEach
    void setUp() {
        adminService = new AdminService(
                userRepository, orderRepository, ledgerRepository, ledgerService,
                orderService, messagingTemplate);
    }

    @Test
    void blockUser_broadcastsBlockedToDriverTopic() {
        User driver = User.builder().id(DRIVER_ID).role(User.Role.DRIVER).build();
        when(userRepository.findById(DRIVER_ID)).thenReturn(Optional.of(driver));

        adminService.blockUser(DRIVER_ID);

        verify(messagingTemplate, times(1))
                .convertAndSend(eq("/topic/driver/" + DRIVER_ID), any(Object.class));
    }

    @Test
    void blockUser_doesNotBroadcastForNonDrivers() {
        User merchant = User.builder().id(MERCHANT_ID).role(User.Role.MERCHANT).build();
        when(userRepository.findById(MERCHANT_ID)).thenReturn(Optional.of(merchant));

        adminService.blockUser(MERCHANT_ID);

        verify(messagingTemplate, never())
                .convertAndSend(eq("/topic/driver/" + MERCHANT_ID), any(Object.class));
    }
}
