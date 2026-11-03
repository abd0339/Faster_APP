package com.faster.backend.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.when;

import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.faster.backend.entity.Order;
import com.faster.backend.repository.LedgerRepository;
import com.faster.backend.repository.OrderRepository;
import com.faster.backend.repository.UserRepository;

/**
 * Covers AdminService.getDistanceFlaggedOrders (input-hardening plan,
 * Task 4) — exact mirror of the existing isPriceFlagged review-queue
 * pattern, for orders flagged by PricingService.exceedsMaxDeliveryDistance
 * (Task 3) and set by Task 6.
 */
@ExtendWith(MockitoExtension.class)
class AdminServiceDistanceFlagTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private OrderRepository orderRepository;

    @Mock
    private LedgerRepository ledgerRepository;

    @Mock
    private LedgerService ledgerService;

    private AdminService adminService;

    @BeforeEach
    void setUp() {
        adminService = new AdminService(
                userRepository, orderRepository, ledgerRepository, ledgerService);
    }

    @Test
    void getDistanceFlaggedOrders_delegatesToRepository() {
        Order order = new Order();
        when(orderRepository.findByIsDistanceFlaggedTrueOrderByCreatedAtDesc())
                .thenReturn(List.of(order));

        assertEquals(List.of(order), adminService.getDistanceFlaggedOrders());
    }
}
