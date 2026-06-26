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
    private static final BigDecimal DRIVER_COMMISSION_RATE =
            new BigDecimal("0.20");
    private static final BigDecimal MERCHANT_COMMISSION_RATE =
            new BigDecimal("0.10");

    // ─────────────────────────────────────────────────
    // DRIVER — Record commission on delivery
    // Called automatically by OrderService when order = DELIVERED
    //
    // BUSINESS RULE:
    //   - 20% of delivery fee is recorded as DEBIT on the driver
    //   - Driver debt accumulates with NO automatic blocking
    //   - Admin reviews debts daily via dashboard
    //   - Admin manually blocks driver when they decide to collect
    //   - Admin manually unblocks after payment confirmed
    // ─────────────────────────────────────────────────
    @Transactional
    public LedgerEntry recordDriverCommission(Order order) {

        // Prevent double-recording if called twice for same order
        if (ledgerRepository.existsByOrderIdAndCategory(
                order.getId(),
                LedgerEntry.EntryCategory.DRIVER_COMMISSION)) {
            // Already recorded — return silently, do not throw
            // This is a safety guard, not an error state
            System.out.println(
                    "⚠️ Commission already recorded for order "
                    + order.getTrackingCode() + " — skipping.");
            return null;
        }

        User driver = order.getDriver();
        if (driver == null) return null;

        // Commission = 20% of delivery fee
        BigDecimal commission = order.getDeliveryFee()
                .multiply(DRIVER_COMMISSION_RATE)
                .setScale(2, RoundingMode.HALF_UP);

        // Current debt from users table (source of truth)
        BigDecimal currentDebt = driver.getDebtAmount() != null
                ? driver.getDebtAmount()
                : BigDecimal.ZERO;

        // New accumulated debt
        BigDecimal newDebt = currentDebt
                .add(commission)
                .setScale(2, RoundingMode.HALF_UP);

        // ─── Create ledger entry ──────────────────────
        LedgerEntry entry = LedgerEntry.builder()
                .user(driver)
                .order(order)
                .type(LedgerEntry.EntryType.DEBIT)
                .category(LedgerEntry.EntryCategory.DRIVER_COMMISSION)
                .deliveryFee(order.getDeliveryFee())
                .amount(commission)
                .balanceAfter(newDebt)
                .description(
                        "Commission 20% of delivery fee $"
                        + order.getDeliveryFee()
                        + " for order "
                        + order.getTrackingCode())
                .build();

        ledgerRepository.save(entry);

        // ─── Update driver debt in users table ────────
        driver.setDebtAmount(newDebt);
        userRepository.save(driver);

        // ─── Notify driver of commission recorded ─────
        // No blocking — just informational notification
        messagingTemplate.convertAndSend(
                "/topic/driver/" + driver.getId(),
                Map.of(
                        "type", "COMMISSION_RECORDED",
                        "message", "Commission $" + commission
                                + " recorded for order "
                                + order.getTrackingCode()
                                + ". Total due: $" + newDebt,
                        "commissionAmount", commission,
                        "totalDebt", newDebt,
                        "orderTrackingCode", order.getTrackingCode()));

        // ─── Notify admin dashboard of new debt ───────
        // Admin reviews this and decides when to collect
        messagingTemplate.convertAndSend(
                "/topic/admin/driver-debts",
                Map.of(
                        "type", "DRIVER_COMMISSION_RECORDED",
                        "driverId", driver.getId(),
                        "driverName", driver.getFullName(),
                        "orderTrackingCode", order.getTrackingCode(),
                        "commissionAmount", commission,
                        "totalDebt", newDebt,
                        "message", "Driver " + driver.getFullName()
                                + " now owes $" + newDebt));

        System.out.println(
                "💰 Commission $" + commission
                + " recorded for driver " + driver.getFullName()
                + " | Total debt: $" + newDebt
                + " | Order: " + order.getTrackingCode());

        return entry;
    }

    // ─────────────────────────────────────────────────
    // DRIVER — Admin settles driver debt manually
    // Admin confirms payment received via OMT/WishMoney
    // Then calls this to reset debt and unblock driver
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
            throw new RuntimeException("User is not a driver");
        }

        if (amountPaid == null ||
                amountPaid.compareTo(BigDecimal.ZERO) <= 0) {
            throw new RuntimeException(
                    "Payment amount must be greater than 0");
        }

        BigDecimal currentDebt = driver.getDebtAmount() != null
                ? driver.getDebtAmount()
                : BigDecimal.ZERO;

        // New balance after payment
        BigDecimal newBalance = currentDebt
                .subtract(amountPaid)
                .setScale(2, RoundingMode.HALF_UP);

        // Cannot go below zero
        if (newBalance.compareTo(BigDecimal.ZERO) < 0) {
            newBalance = BigDecimal.ZERO;
        }

        // ─── Create credit ledger entry ───────────────
        LedgerEntry entry = LedgerEntry.builder()
                .user(driver)
                .type(LedgerEntry.EntryType.CREDIT)
                .category(LedgerEntry.EntryCategory.DRIVER_SETTLEMENT)
                .amount(amountPaid)
                .balanceAfter(newBalance)
                .description(
                        "Debt settlement: $"
                        + amountPaid
                        + " received via OMT/WishMoney")
                .paymentReference(paymentReference)
                .processedBy(adminId)
                .build();

        LedgerEntry saved = ledgerRepository.save(entry);

        // ─── Update driver: reset debt + unblock ──────
        driver.setDebtAmount(newBalance);
        driver.setIsBlocked(false);
        userRepository.save(driver);

        // ─── Notify driver account is active again ────
        messagingTemplate.convertAndSend(
                "/topic/driver/" + driverId,
                Map.of(
                        "type", "ACCOUNT_REACTIVATED",
                        "message",
                        "Payment of $" + amountPaid
                        + " received. Your account is active. "
                        + "Remaining balance: $" + newBalance,
                        "amountPaid", amountPaid,
                        "remainingDebt", newBalance));

        System.out.println(
                "✅ Driver " + driver.getFullName()
                + " settled $" + amountPaid
                + " | Remaining debt: $" + newBalance
                + " | Ref: " + paymentReference);

        return saved;
    }

    // ─────────────────────────────────────────────────
    // DAILY JOB — Send admin a summary of all driver debts
    // Runs every day at midnight Beirut time
    // Admin uses this to decide who to collect from / block
    // ─────────────────────────────────────────────────
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
                // Push to admin dashboard for review
                messagingTemplate.convertAndSend(
                        "/topic/admin/driver-debts",
                        Map.of(
                                "type", "DAILY_DEBT_SUMMARY",
                                "driverId", driver.getId(),
                                "driverName", driver.getFullName(),
                                "totalDebt", debt,
                                "isBlocked",
                                Boolean.TRUE.equals(
                                        driver.getIsBlocked()),
                                "date", LocalDate.now().toString(),
                                "message", "Driver "
                                        + driver.getFullName()
                                        + " has outstanding debt of $"
                                        + debt));
            }
        }

        System.out.println(
                "📊 Daily driver debt summary sent to admin dashboard");
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
                .findByRoleAndIsActiveTrue(User.Role.MERCHANT);

        for (User merchant : merchants) {
            try {
                recordMerchantDailyCommission(
                        merchant, startOfDay, endOfDay);
            } catch (Exception e) {
                System.err.println(
                        "Failed to record commission for merchant "
                        + merchant.getId() + ": " + e.getMessage());
            }
        }
    }

    // ─── Record commission for one merchant for one day ──
    @Transactional
    public LedgerEntry recordMerchantDailyCommission(
            User merchant,
            LocalDateTime startOfDay,
            LocalDateTime endOfDay) {

        // Get total delivered sales for that day
        BigDecimal dailySales = ledgerRepository
                .getMerchantDailyCommission(
                        merchant.getId(),
                        startOfDay,
                        endOfDay);

        if (dailySales == null ||
                dailySales.compareTo(BigDecimal.ZERO) == 0) {
            return null; // No sales that day — nothing to record
        }

        // Commission = 10% of daily sales
        BigDecimal commission = dailySales
                .multiply(MERCHANT_COMMISSION_RATE)
                .setScale(2, RoundingMode.HALF_UP);

        // Get current merchant ledger balance
        BigDecimal currentBalance = ledgerRepository
                .getLatestBalance(merchant.getId());
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
                        + dailySales + " sales on "
                        + startOfDay.toLocalDate())
                .build();

        LedgerEntry saved = ledgerRepository.save(entry);

        // Notify admin dashboard
        messagingTemplate.convertAndSend(
                "/topic/admin/merchant-commissions",
                Map.of(
                        "type", "MERCHANT_COMMISSION_RECORDED",
                        "merchantId", merchant.getId(),
                        "merchantName", merchant.getFullName(),
                        "dailySales", dailySales,
                        "commission", commission,
                        "date", startOfDay.toLocalDate().toString(),
                        "message", "Merchant " + merchant.getFullName()
                                + " owes $" + commission
                                + " (10% of $" + dailySales + ")"));

        System.out.println(
                "🏪 Merchant " + merchant.getFullName()
                + " commission: $" + commission
                + " (10% of $" + dailySales + " sales)");

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

        if (amountPaid == null ||
                amountPaid.compareTo(BigDecimal.ZERO) <= 0) {
            throw new RuntimeException(
                    "Payment amount must be greater than 0");
        }

        BigDecimal currentBalance = ledgerRepository
                .getLatestBalance(merchantId);
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
    public List<LedgerEntry> getDriverLedger(Long driverId) {
        return ledgerRepository
                .findByUserIdOrderByCreatedAtDesc(driverId);
    }

    // ─────────────────────────────────────────────────
    // GET LEDGER — Merchant sees own history
    // ─────────────────────────────────────────────────
    public List<LedgerEntry> getMerchantLedger(Long merchantId) {
        return ledgerRepository
                .findByUserIdOrderByCreatedAtDesc(merchantId);
    }

    // ─────────────────────────────────────────────────
    // GET CURRENT DEBT — Driver
    // ─────────────────────────────────────────────────
    public Map<String, Object> getDriverDebtSummary(Long driverId) {
        User driver = userRepository.findById(driverId)
                .orElseThrow(() ->
                        new RuntimeException("Driver not found"));

        BigDecimal debt = driver.getDebtAmount() != null
                ? driver.getDebtAmount()
                : BigDecimal.ZERO;

        boolean isBlocked = Boolean.TRUE.equals(driver.getIsBlocked());

        return Map.of(
                "driverId", driverId,
                "currentDebt", debt,
                "isBlocked", isBlocked,
                "currency", "USD",
                "paymentMethods", List.of("OMT", "WishMoney"),
                "message", isBlocked
                        ? "Account paused by admin. Pay $" + debt
                                + " via OMT or WishMoney, "
                                + "then contact admin to reactivate."
                        : "Account active. Accumulated commission: $"
                                + debt);
    }

    // ─────────────────────────────────────────────────
    // PLATFORM REVENUE SUMMARY (admin)
    // ─────────────────────────────────────────────────
    public Map<String, Object> getPlatformRevenue(
            LocalDateTime from,
            LocalDateTime to) {

        BigDecimal totalRevenue = from != null && to != null
                ? ledgerRepository.getPlatformRevenueInRange(from, to)
                : ledgerRepository.getPlatformTotalRevenue();

        return Map.of(
                "totalRevenue",
                totalRevenue != null
                        ? totalRevenue
                        : BigDecimal.ZERO,
                "currency", "USD",
                "from", from != null ? from.toString() : "all time",
                "to", to != null ? to.toString() : "now");
    }
}