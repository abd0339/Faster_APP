package com.faster.backend.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.LocalDateTime;
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
 * Full-codebase review fix round (2026-11) — covers the lost-update races
 * on cancelOrderByCustomer/disputeOrder (a stale-snapshot save() could
 * silently overwrite a concurrent acceptOrder's commit), the stock-restore
 * gap on cancellation (ItemService.releaseStock had no caller anywhere),
 * disputeOrder's notification blackout (no /topic/order/{id} broadcast, no
 * push — a total blackout for MOBILITY orders, which never have a
 * merchant), and AdminService.resolveDispute bypassing OrderService's
 * state machine entirely (no commission recorded, no broadcast).
 */
@ExtendWith(MockitoExtension.class)
class OrderServiceDisputeAndCancelTest {

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

    private static final long ORDER_ID = 99L;
    private static final long CUSTOMER_ID = 1L;
    private static final long DRIVER_ID = 2L;

    @BeforeEach
    void setUp() {
        orderService = new OrderService(
                orderRepository, userRepository, locationService,
                messagingTemplate, ledgerService, communicationService,
                pricingService, pushNotificationService);
    }

    private User customer() {
        return User.builder().id(CUSTOMER_ID).build();
    }

    private Order pendingOrder() {
        return Order.builder()
                .id(ORDER_ID)
                .status(Order.OrderStatus.PENDING)
                .customer(customer())
                .createdAt(LocalDateTime.now())
                .build();
    }

    // ───────────────────── cancelOrderByCustomer ─────────────────────

    @Test
    void cancelOrderByCustomer_throwsWhenConcurrentAcceptWinsTheRace() {
        when(orderRepository.findById(ORDER_ID))
                .thenReturn(Optional.of(pendingOrder()));
        // Simulates a driver's acceptOrder committing ACCEPTED between this
        // method's read above and its atomic write below — the atomic
        // UPDATE's WHERE status='PENDING' guard matches zero rows.
        when(orderRepository.cancelIfPending(eq(ORDER_ID), any())).thenReturn(0);

        assertThrows(BusinessException.class,
                () -> orderService.cancelOrderByCustomer(ORDER_ID, CUSTOMER_ID));

        verify(pricingService, never()).restoreStockForOrder(anyLong());
    }

    @Test
    void cancelOrderByCustomer_restoresStockOnSuccess() {
        Order pending = pendingOrder();
        Order cancelled = Order.builder()
                .id(ORDER_ID)
                .status(Order.OrderStatus.CANCELLED)
                .customer(customer())
                .createdAt(pending.getCreatedAt())
                .build();

        when(orderRepository.findById(ORDER_ID))
                .thenReturn(Optional.of(pending))
                .thenReturn(Optional.of(cancelled));
        when(orderRepository.cancelIfPending(eq(ORDER_ID), any())).thenReturn(1);

        Order result = orderService.cancelOrderByCustomer(ORDER_ID, CUSTOMER_ID);

        assertEquals(Order.OrderStatus.CANCELLED, result.getStatus());
        verify(pricingService, times(1)).restoreStockForOrder(ORDER_ID);
    }

    // ───────────────────────── disputeOrder ──────────────────────────

    @Test
    void disputeOrder_throwsWhenConcurrentChangeWinsTheRace() {
        when(orderRepository.findById(ORDER_ID))
                .thenReturn(Optional.of(pendingOrder()));
        when(orderRepository.disputeIfNotTerminal(eq(ORDER_ID), any(), any()))
                .thenReturn(0);

        assertThrows(BusinessException.class,
                () -> orderService.disputeOrder(ORDER_ID, "never arrived", CUSTOMER_ID));
    }

    @Test
    void disputeOrder_broadcastsToOrderTopicAndNotifiesDriver() {
        // FIX regression: a MOBILITY order has no merchant at all — before
        // this fix, disputing one produced zero broadcast to /topic/order
        // and zero push to either party, since the old code only ever
        // messaged /topic/merchant/{id} (guarded on merchant != null) and
        // /topic/admin/disputes.
        User driver = User.builder().id(DRIVER_ID).build();
        Order pending = Order.builder()
                .id(ORDER_ID)
                .status(Order.OrderStatus.ACCEPTED)
                .customer(customer())
                .driver(driver)
                .trackingCode("FST-TEST")
                .build();
        Order disputed = Order.builder()
                .id(ORDER_ID)
                .status(Order.OrderStatus.DISPUTED)
                .customer(customer())
                .driver(driver)
                .trackingCode("FST-TEST")
                .build();

        when(orderRepository.findById(ORDER_ID))
                .thenReturn(Optional.of(pending))
                .thenReturn(Optional.of(disputed));
        when(orderRepository.disputeIfNotTerminal(eq(ORDER_ID), any(), any()))
                .thenReturn(1);

        orderService.disputeOrder(ORDER_ID, "never arrived", DRIVER_ID);

        verify(messagingTemplate, times(1))
                .convertAndSend(eq("/topic/order/" + ORDER_ID), any(Object.class));
        verify(messagingTemplate, times(1))
                .convertAndSend(eq("/topic/admin/disputes"), any(Object.class));
        verify(pushNotificationService, times(1))
                .sendToUser(eq(CUSTOMER_ID), any(), any(), any());
        verify(pushNotificationService, times(1))
                .sendToUser(eq(DRIVER_ID), any(), any(), any());
    }

    // ──────────────────────── resolveDispute ─────────────────────────

    @Test
    void resolveDispute_rejectsAnyResolutionOtherThanDeliveredOrCancelled() {
        assertThrows(BusinessException.class,
                () -> orderService.resolveDispute(ORDER_ID, Order.OrderStatus.PENDING));
        assertThrows(BusinessException.class,
                () -> orderService.resolveDispute(ORDER_ID, Order.OrderStatus.ACCEPTED));

        verify(orderRepository, never()).resolveIfDisputed(anyLong(), any(), any());
    }

    @Test
    void resolveDispute_throwsWhenOrderIsNotDisputed() {
        when(orderRepository.resolveIfDisputed(
                eq(ORDER_ID), eq(Order.OrderStatus.DELIVERED), any()))
                .thenReturn(0);

        assertThrows(BusinessException.class,
                () -> orderService.resolveDispute(ORDER_ID, Order.OrderStatus.DELIVERED));

        verify(ledgerService, never()).recordDriverCommission(any());
    }

    @Test
    void resolveDispute_toDelivered_recordsDriverCommission() {
        User driver = User.builder().id(DRIVER_ID).build();
        Order disputed = Order.builder()
                .id(ORDER_ID)
                .status(Order.OrderStatus.DISPUTED)
                .customer(customer())
                .driver(driver)
                .trackingCode("FST-TEST")
                .build();

        when(orderRepository.resolveIfDisputed(
                eq(ORDER_ID), eq(Order.OrderStatus.DELIVERED), any()))
                .thenReturn(1);
        when(orderRepository.findById(ORDER_ID)).thenReturn(Optional.of(disputed));
        when(orderRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        orderService.resolveDispute(ORDER_ID, Order.OrderStatus.DELIVERED);

        verify(ledgerService, times(1)).recordDriverCommission(any());
        verify(pricingService, never()).restoreStockForOrder(anyLong());
    }

    @Test
    void resolveDispute_toCancelled_restoresStockNotCommission() {
        Order disputed = Order.builder()
                .id(ORDER_ID)
                .status(Order.OrderStatus.DISPUTED)
                .customer(customer())
                .trackingCode("FST-TEST")
                .build();

        when(orderRepository.resolveIfDisputed(
                eq(ORDER_ID), eq(Order.OrderStatus.CANCELLED), any()))
                .thenReturn(1);
        when(orderRepository.findById(ORDER_ID)).thenReturn(Optional.of(disputed));

        orderService.resolveDispute(ORDER_ID, Order.OrderStatus.CANCELLED);

        verify(pricingService, times(1)).restoreStockForOrder(ORDER_ID);
        verify(ledgerService, never()).recordDriverCommission(any());
    }
}
