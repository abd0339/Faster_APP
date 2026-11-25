package com.faster.backend.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.messaging.simp.SimpMessagingTemplate;

import com.faster.backend.entity.LedgerEntry;
import com.faster.backend.entity.User;
import com.faster.backend.repository.LedgerRepository;
import com.faster.backend.repository.UserRepository;

/**
 * Full-codebase review fix round (2026-11) — settleDriverDebt used to
 * clear isBlocked unconditionally on ANY payment, including a trivially
 * small partial one: a driver blocked for a $500 debt could pay $0.01 and
 * be told "Account reactivated" while still owing $499.99, with no
 * re-block mechanism anywhere in the codebase. Only a payment that
 * actually brings the balance to zero should reactivate the account.
 */
@ExtendWith(MockitoExtension.class)
class LedgerServiceDebtSettlementTest {

    @Mock
    private LedgerRepository ledgerRepository;

    @Mock
    private UserRepository userRepository;

    @Mock
    private SimpMessagingTemplate messagingTemplate;

    @Mock
    private PricingService pricingService;

    private LedgerService ledgerService;

    private static final long DRIVER_ID = 5L;

    @BeforeEach
    void setUp() {
        ledgerService = new LedgerService(
                ledgerRepository, userRepository, messagingTemplate, pricingService);
    }

    private User blockedDriverWithDebt(BigDecimal debt) {
        return User.builder()
                .id(DRIVER_ID)
                .role(User.Role.DRIVER)
                .isBlocked(true)
                .debtAmount(debt)
                .build();
    }

    @Test
    void partialPayment_leavesDriverBlocked() {
        User driver = blockedDriverWithDebt(new BigDecimal("500.00"));
        when(userRepository.findByIdForUpdate(DRIVER_ID))
                .thenReturn(Optional.of(driver));
        when(ledgerRepository.save(any(LedgerEntry.class)))
                .thenAnswer(inv -> inv.getArgument(0));

        ledgerService.settleDriverDebt(
                DRIVER_ID, new BigDecimal("0.01"), "ref-1", 1L);

        assertTrue(driver.getIsBlocked(),
                "a $0.01 payment against a $500 debt must not unblock the driver");
        assertEquals(new BigDecimal("499.99"), driver.getDebtAmount());

        ArgumentCaptor<java.util.Map<String, Object>> payload =
                ArgumentCaptor.forClass(java.util.Map.class);
        org.mockito.Mockito.verify(messagingTemplate)
                .convertAndSend(org.mockito.ArgumentMatchers.eq("/topic/driver/" + DRIVER_ID),
                        payload.capture());
        assertEquals("PARTIAL_PAYMENT_RECEIVED", payload.getValue().get("type"));
    }

    @Test
    void fullPayment_unblocksDriver() {
        User driver = blockedDriverWithDebt(new BigDecimal("500.00"));
        when(userRepository.findByIdForUpdate(DRIVER_ID))
                .thenReturn(Optional.of(driver));
        when(ledgerRepository.save(any(LedgerEntry.class)))
                .thenAnswer(inv -> inv.getArgument(0));

        ledgerService.settleDriverDebt(
                DRIVER_ID, new BigDecimal("500.00"), "ref-2", 1L);

        assertFalse(driver.getIsBlocked());
        assertEquals(BigDecimal.ZERO.setScale(2), driver.getDebtAmount());
    }

    @Test
    void overpayment_clampsToZeroAndUnblocks() {
        User driver = blockedDriverWithDebt(new BigDecimal("100.00"));
        when(userRepository.findByIdForUpdate(DRIVER_ID))
                .thenReturn(Optional.of(driver));
        when(ledgerRepository.save(any(LedgerEntry.class)))
                .thenAnswer(inv -> inv.getArgument(0));

        ledgerService.settleDriverDebt(
                DRIVER_ID, new BigDecimal("150.00"), "ref-3", 1L);

        assertFalse(driver.getIsBlocked());
        assertEquals(0, BigDecimal.ZERO.compareTo(driver.getDebtAmount()));
    }
}
