package com.faster.backend.repository;

import com.faster.backend.entity.LedgerEntry;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

@Repository
public interface LedgerRepository
        extends JpaRepository<LedgerEntry, Long> {

    // ─── All entries for a user ───────────────────────
    List<LedgerEntry> findByUserIdOrderByCreatedAtDesc(
            Long userId);

    // ─── Entries by category ──────────────────────────
    List<LedgerEntry> findByUserIdAndCategoryOrderByCreatedAtDesc(
            Long userId,
            LedgerEntry.EntryCategory category);

    // ─── Entries by type (DEBIT/CREDIT) ──────────────
    List<LedgerEntry> findByUserIdAndTypeOrderByCreatedAtDesc(
            Long userId,
            LedgerEntry.EntryType type);

    // ─── Get latest balance for a user ───────────────
    // Uses Pageable instead of LIMIT (LIMIT is not standard JPQL)
    // Returns the most recent balanceAfter value
    @Query("SELECT l.balanceAfter FROM LedgerEntry l " +
           "WHERE l.user.id = :userId " +
           "ORDER BY l.createdAt DESC")
    List<BigDecimal> findLatestBalancePage(
            @Param("userId") Long userId,
            Pageable pageable);

    // ─── Convenience default method ───────────────────
    // Call this everywhere instead of findLatestBalancePage directly
    default BigDecimal getLatestBalance(Long userId) {
        List<BigDecimal> results = findLatestBalancePage(
                userId, PageRequest.of(0, 1));
        return results.isEmpty() ? null : results.get(0);
    }

    // ─── Total driver commission (sum of all DEBIT entries) ──
    @Query("SELECT COALESCE(SUM(l.amount), 0) " +
           "FROM LedgerEntry l " +
           "WHERE l.user.id = :driverId " +
           "AND l.category = 'DRIVER_COMMISSION' " +
           "AND l.type = 'DEBIT'")
    BigDecimal sumDriverTotalCommission(
            @Param("driverId") Long driverId);

    // ─── Driver entries in date range ─────────────────
    @Query("SELECT l FROM LedgerEntry l " +
           "WHERE l.user.id = :userId " +
           "AND l.createdAt BETWEEN :from AND :to " +
           "ORDER BY l.createdAt DESC")
    List<LedgerEntry> findByUserIdAndDateRange(
            @Param("userId") Long userId,
            @Param("from") LocalDateTime from,
            @Param("to") LocalDateTime to);

    // ─── Merchant daily sales total ──────────────────
    // Sums merchantCommission from delivered orders in a day
    @Query("SELECT COALESCE(SUM(o.merchantCommission), 0) " +
           "FROM Order o " +
           "WHERE o.merchant.id = :merchantId " +
           "AND o.status = 'DELIVERED' " +
           "AND o.deliveredAt >= :startOfDay " +
           "AND o.deliveredAt < :endOfDay")
    BigDecimal getMerchantDailyCommission(
            @Param("merchantId") Long merchantId,
            @Param("startOfDay") LocalDateTime startOfDay,
            @Param("endOfDay") LocalDateTime endOfDay);

    // ─── Merchant monthly commission total ────────────
    @Query("SELECT COALESCE(SUM(o.merchantCommission), 0) " +
           "FROM Order o " +
           "WHERE o.merchant.id = :merchantId " +
           "AND o.status = 'DELIVERED' " +
           "AND o.deliveredAt >= :startOfMonth " +
           "AND o.deliveredAt < :endOfMonth")
    BigDecimal getMerchantMonthlyCommission(
            @Param("merchantId") Long merchantId,
            @Param("startOfMonth") LocalDateTime startOfMonth,
            @Param("endOfMonth") LocalDateTime endOfMonth);

    // ─── Platform total revenue (all commissions ever) ──
    @Query("SELECT COALESCE(SUM(l.amount), 0) " +
           "FROM LedgerEntry l " +
           "WHERE l.category IN " +
           "('DRIVER_COMMISSION', 'MERCHANT_COMMISSION') " +
           "AND l.type = 'DEBIT'")
    BigDecimal getPlatformTotalRevenue();

    // ─── Platform revenue in date range ───────────────
    @Query("SELECT COALESCE(SUM(l.amount), 0) " +
           "FROM LedgerEntry l " +
           "WHERE l.category IN " +
           "('DRIVER_COMMISSION', 'MERCHANT_COMMISSION') " +
           "AND l.type = 'DEBIT' " +
           "AND l.createdAt BETWEEN :from AND :to")
    BigDecimal getPlatformRevenueInRange(
            @Param("from") LocalDateTime from,
            @Param("to") LocalDateTime to);

    // ─── All driver commission entries (admin view) ───
    @Query("SELECT l FROM LedgerEntry l " +
           "WHERE l.category = 'DRIVER_COMMISSION' " +
           "ORDER BY l.createdAt DESC")
    List<LedgerEntry> findAllDriverCommissions();

    // ─── Unsettled commissions for one driver ─────────
    @Query("SELECT l FROM LedgerEntry l " +
           "WHERE l.user.id = :driverId " +
           "AND l.category = 'DRIVER_COMMISSION' " +
           "AND l.type = 'DEBIT' " +
           "ORDER BY l.createdAt DESC")
    List<LedgerEntry> findUnsettledCommissions(
            @Param("driverId") Long driverId);

    // ─── Check if order already has a ledger entry ────
    // Used in recordDriverCommission() to prevent double-recording
    boolean existsByOrderIdAndCategory(
            Long orderId,
            LedgerEntry.EntryCategory category);
}
