package com.faster.backend.service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.util.List;
import java.util.Map;

import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.faster.backend.entity.LedgerEntry;
import com.faster.backend.entity.Order;
import com.faster.backend.entity.User;
import com.faster.backend.repository.LedgerRepository;
import com.faster.backend.repository.UserRepository;

import lombok.RequiredArgsConstructor;

@Service
@RequiredArgsConstructor
public class LedgerService {

    private final LedgerRepository ledgerRepository;
    private final UserRepository userRepository;
    private final SimpMessagingTemplate messagingTemplate;

    // ─── Commission rates ─────────────────────────────
    private static final BigDecimal DRIVER_COMMISSION_RATE = new BigDecimal("0.20");
    private static final BigDecimal MERCHANT_COMMISSION_RATE = new BigDecimal("0.10");

    // ─────────────────────────────────────────────────
    // DRIVER — Record commission on delivery
    // Called automatically when order = DELIVERED
    // ─────────────────────────────────────────────────
    @Transactional
    public LedgerEntry recordDriverCommission(
            Order order) {

        // Prevent double-recording
        if (ledgerRepository.existsByOrderIdAndCategory(
                order.getId(),
                LedgerEntry.EntryCategory.DRIVER_COMMISSION)) {
            throw new RuntimeException(
                    "Commission already recorded " +
                            "for this order");
        }

        User driver = order.getDriver();
        if (driver == null)
            return null;

        // Commission = 20% of delivery fee
        BigDecimal commission = order.getDeliveryFee()
                .multiply(DRIVER_COMMISSION_RATE)
                .setScale(2, RoundingMode.HALF_UP);

        // New balance = current debt + commission
        BigDecimal currentDebt = driver.getDebtAmount() != null
                ? driver.getDebtAmount()
                : BigDecimal.ZERO;

        BigDecimal newBalance = currentDebt
                .add(commission)
                .setScale(2, RoundingMode.HALF_UP);

        // Create ledger entry
        LedgerEntry entry = LedgerEntry.builder()
                .user(driver)
                .order(order)
                .type(LedgerEntry.EntryType.DEBIT)
                .category(LedgerEntry.EntryCategory.DRIVER_COMMISSION)
                .deliveryFee(order.getDeliveryFee())
                .amount(commission)
                .balanceAfter(newBalance)
                .description(
                        "Commission 20% of delivery fee $"
                                + order.getDeliveryFee()
                                + " for order "
                                + order.getTrackingCode())
                .build();

        LedgerEntry saved = ledgerRepository.save(entry);

        // Update driver debt in users table
        driver.setDebtAmount(newBalance);

        // Auto-block if debt >= $20
        if (newBalance.compareTo(
                new BigDecimal("20.00")) >= 0) {
            // Notify driver of commission recorded
            messagingTemplate.convertAndSend(
                    "/topic/driver/" + driver.getId(),
                    Map.of(
                            "type", "COMMISSION_RECORDED",
                            "message", "Commission $" + commission
                                    + " added. Total debt: $" + newBalance,
                            "commissionAmount", commission,
                            "totalDebt", newBalance));
        }

        userRepository.save(driver);
        return saved;
    }

    // ─────────────────────────────────────────────────
    // DRIVER — Admin settles driver debt manually
    // Admin confirms payment received via OMT/WishMoney
    // Future: auto via WishMoney webhook
    // ─────────────────────────────────────────────────
    @Transactional
    public LedgerEntry settleDriverDebt(
            Long driverId,
            BigDecimal amountPaid,
            String paymentReference,
            Long adminId) {

        User driver = userRepository
                .findById(driverId)
                .orElseThrow(() -> new RuntimeException(
                        "Driver not found"));

        if (driver.getRole() != User.Role.DRIVER) {
            throw new RuntimeException(
                    "User is not a driver");
        }

        BigDecimal currentDebt = driver.getDebtAmount() != null
                ? driver.getDebtAmount()
                : BigDecimal.ZERO;

        if (amountPaid.compareTo(BigDecimal.ZERO) <= 0) {
            throw new RuntimeException(
                    "Payment amount must be greater than 0");
        }

        // New balance after payment
        BigDecimal newBalance = currentDebt
                .subtract(amountPaid)
                .setScale(2, RoundingMode.HALF_UP);

        // Cannot go below zero
        if (newBalance.compareTo(BigDecimal.ZERO) < 0) {
            newBalance = BigDecimal.ZERO;
        }

        // Create credit ledger entry
        LedgerEntry entry = LedgerEntry.builder()
                .user(driver)
                .type(LedgerEntry.EntryType.CREDIT)
                .category(LedgerEntry.EntryCategory.DRIVER_SETTLEMENT)
                .amount(amountPaid)
                .balanceAfter(newBalance)
                .description(
                        "Debt settlement payment of $"
                                + amountPaid
                                + " received via OMT/WishMoney")
                .paymentReference(paymentReference)
                .processedBy(adminId)
                .build();

        LedgerEntry saved = ledgerRepository.save(entry);

        // Update driver — reset debt + unblock
        driver.setDebtAmount(newBalance);
        driver.setIsBlocked(false);
        userRepository.save(driver);

        // Notify driver account is active again
        messagingTemplate.convertAndSend(
                "/topic/driver/" + driverId,
                Map.of(
                        "type", "ACCOUNT_REACTIVATED",
                        "message",
                        "Your account is active again. " +
                                "Remaining balance: $" + newBalance,
                        "remainingDebt", newBalance));

        return saved;
    }

    @Scheduled(cron = "0 0 0 * * *", zone = "Asia/Beirut")
    @Transactional
    public void recordDailyDriverCommissionSummary() {
        List<User> drivers = userRepository
                .findByRoleAndIsActiveTrue(User.Role.DRIVER);

        for (User driver : drivers) {
            BigDecimal debt = driver.getDebtAmount() != null
                    ? driver.getDebtAmount()
                    : BigDecimal.ZERO;

            if (debt.compareTo(BigDecimal.ZERO) > 0) {
                // Notify admin of driver outstanding debt
                messagingTemplate.convertAndSend(
                        "/topic/admin/driver-debts",
                        Map.of(
                                "driverId", driver.getId(),
                                "driverName", driver.getFullName(),
                                "totalDebt", debt,
                                "date", LocalDate.now().toString()));
            }
        }
    }

    // ─────────────────────────────────────────────────
    // MERCHANT — Record daily commission
    // Runs automatically every day at midnight
    // Records 10% of that day's total delivered sales
    // ─────────────────────────────────────────────────
    @Scheduled(cron = "0 0 0 * * *", zone = "Asia/Beirut")
    @Transactional
    public void recordDailyMerchantCommissions() {

        // Get yesterday's date range
        LocalDate yesterday = LocalDate.now().minusDays(1);
        LocalDateTime startOfDay = yesterday.atStartOfDay();
        LocalDateTime endOfDay = yesterday.atTime(LocalTime.MAX);

        // Get all active merchants
        List<User> merchants = userRepository
                .findByRoleAndIsActiveTrue(
                        User.Role.MERCHANT);

        for (User merchant : merchants) {
            try {
                recordMerchantDailyCommission(
                        merchant, startOfDay, endOfDay);
            } catch (Exception e) {
                System.err.println(
                        "Failed to record commission " +
                                "for merchant " +
                                merchant.getId() + ": " +
                                e.getMessage());
            }
        }
    }

    // ─── Record commission for one merchant one day ───
    @Transactional
    public LedgerEntry recordMerchantDailyCommission(
            User merchant,
            LocalDateTime startOfDay,
            LocalDateTime endOfDay) {

        // Get total sales for that day
        BigDecimal dailySales = ledgerRepository
                .getMerchantDailyCommission(
                        merchant.getId(),
                        startOfDay,
                        endOfDay);

        if (dailySales == null ||
                dailySales.compareTo(BigDecimal.ZERO) == 0) {
            return null; // No sales that day
        }

        // Commission = 10% of daily sales
        BigDecimal commission = dailySales
                .multiply(MERCHANT_COMMISSION_RATE)
                .setScale(2, RoundingMode.HALF_UP);

        // Get current merchant balance
        BigDecimal currentBalance = ledgerRepository.getLatestBalance(
                merchant.getId());
        if (currentBalance == null) {
            currentBalance = BigDecimal.ZERO;
        }

        BigDecimal newBalance = currentBalance
                .add(commission)
                .setScale(2, RoundingMode.HALF_UP);

        LedgerEntry entry = LedgerEntry.builder()
                .user(merchant)
                .type(LedgerEntry.EntryType.DEBIT)
                .category(LedgerEntry.EntryCategory.MERCHANT_COMMISSION)
                .amount(commission)
                .balanceAfter(newBalance)
                .description(
                        "Daily commission 10% of $"
                                + dailySales
                                + " sales on "
                                + startOfDay.toLocalDate())
                .build();

        LedgerEntry saved = ledgerRepository.save(entry);

        // Notify admin of new merchant commission
        messagingTemplate.convertAndSend(
                "/topic/admin/merchant-commissions",
                Map.of(
                        "merchantId", merchant.getId(),
                        "merchantName", merchant.getFullName(),
                        "dailySales", dailySales,
                        "commission", commission,
                        "date", startOfDay.toLocalDate()
                                .toString()));

        return saved;
    }

    // ─────────────────────────────────────────────────
    // MERCHANT — Admin settles merchant commission
    // ─────────────────────────────────────────────────
    @Transactional
    public LedgerEntry settleMerchantCommission(
            Long merchantId,
            BigDecimal amountPaid,
            String paymentReference,
            Long adminId) {

        User merchant = userRepository
                .findById(merchantId)
                .orElseThrow(() -> new RuntimeException(
                        "Merchant not found"));

        BigDecimal currentBalance = ledgerRepository.getLatestBalance(
                merchantId);
        if (currentBalance == null) {
            currentBalance = BigDecimal.ZERO;
        }

        BigDecimal newBalance = currentBalance
                .subtract(amountPaid)
                .setScale(2, RoundingMode.HALF_UP);

        if (newBalance.compareTo(BigDecimal.ZERO) < 0) {
            newBalance = BigDecimal.ZERO;
        }

        LedgerEntry entry = LedgerEntry.builder()
                .user(merchant)
                .type(LedgerEntry.EntryType.CREDIT)
                .category(LedgerEntry.EntryCategory.MERCHANT_SETTLEMENT)
                .amount(amountPaid)
                .balanceAfter(newBalance)
                .description(
                        "Merchant commission payment $"
                                + amountPaid + " received")
                .paymentReference(paymentReference)
                .processedBy(adminId)
                .build();

        return ledgerRepository.save(entry);
    }

    // ─────────────────────────────────────────────────
    // GET LEDGER — Driver sees own history
    // ─────────────────────────────────────────────────
    public List<LedgerEntry> getDriverLedger(
            Long driverId) {
        return ledgerRepository
                .findByUserIdOrderByCreatedAtDesc(driverId);
    }

    // ─────────────────────────────────────────────────
    // GET LEDGER — Merchant sees own history
    // ─────────────────────────────────────────────────
    public List<LedgerEntry> getMerchantLedger(
            Long merchantId) {
        return ledgerRepository
                .findByUserIdOrderByCreatedAtDesc(merchantId);
    }

    // ─────────────────────────────────────────────────
    // GET CURRENT DEBT — Driver
    // ─────────────────────────────────────────────────
    public Map<String, Object> getDriverDebtSummary(Long driverId) {
        User driver = userRepository.findById(driverId)
                .orElseThrow(() -> new RuntimeException("Driver not found"));

        BigDecimal debt = driver.getDebtAmount() != null
                ? driver.getDebtAmount()
                : BigDecimal.ZERO;

        return Map.of(
                "driverId", driverId,
                "currentDebt", debt,
                "isBlocked", Boolean.TRUE.equals(driver.getIsBlocked()),
                "currency", "USD",
                "paymentMethods", List.of("OMT", "WishMoney"),
                "message", Boolean.TRUE.equals(driver.getIsBlocked())
                        ? "Account paused by admin. Pay $" + debt
                                + " via OMT or WishMoney then contact admin."
                        : "Active. Accumulated commission: $" + debt);
    }

    // ─────────────────────────────────────────────────
    // PLATFORM REVENUE SUMMARY (admin)
    // ─────────────────────────────────────────────────
    public Map<String, Object> getPlatformRevenue(
            LocalDateTime from,
            LocalDateTime to) {

        BigDecimal totalRevenue = from != null && to != null
                ? ledgerRepository
                        .getPlatformRevenueInRange(from, to)
                : ledgerRepository
                        .getPlatformTotalRevenue();

        return Map.of(
                "totalRevenue",
                totalRevenue != null
                        ? totalRevenue
                        : BigDecimal.ZERO,
                "currency", "USD",
                "from", from != null
                        ? from.toString()
                        : "all time",
                "to", to != null
                        ? to.toString()
                        : "now");
    }
}